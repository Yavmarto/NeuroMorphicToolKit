from __future__ import annotations

import os
import re
import subprocess
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import requests
from dotenv import load_dotenv

SCRIPT_DIR = Path(__file__).resolve().parent
ENV_PATH = SCRIPT_DIR / ".env"
load_dotenv(ENV_PATH)

JULES_BASE_URL = (os.getenv("JULES_BASE_URL") or "https://jules.googleapis.com/v1alpha").rstrip("/")
DEFAULT_REQUEST_TIMEOUT_SECONDS = int(os.getenv("JULES_REQUEST_TIMEOUT_SECONDS", "15"))
DEFAULT_SOURCE_CACHE_TTL_SECONDS = int(os.getenv("JULES_SOURCE_CACHE_TTL_SECONDS", "300"))
TRANSIENT_STATUS_CODES = {429, 500, 502, 503, 504}


class JulesApiError(RuntimeError):
    def __init__(
        self,
        message: str,
        *,
        status_code: int | None = None,
        response_text: str | None = None,
    ) -> None:
        super().__init__(message)
        self.status_code = status_code
        self.response_text = response_text

    @property
    def is_transient(self) -> bool:
        return self.status_code in TRANSIENT_STATUS_CODES or self.status_code is None


@dataclass(frozen=True)
class ResolvedSource:
    name: str
    repo_identifier: str | None
    default_branch: str | None
    branches: tuple[str, ...]


def normalize_repo_identifier(repo_identifier: str) -> str:
    normalized = repo_identifier.strip()
    normalized = normalized.replace("Yavmarto/", "Completed-Spoon-6/")
    if "/" in normalized:
        owner, repo = normalized.split("/", 1)
        if repo.lower().startswith("neuro") and repo[0].islower():
            repo = repo[0].upper() + repo[1:]
        normalized = f"{owner}/{repo}"
    return normalized


def get_repo_identifier(repo_path: str) -> str | None:
    try:
        url = subprocess.check_output(
            ["git", "-C", repo_path, "remote", "get-url", "origin"],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
    except Exception:
        return None

    match = re.search(r"[:/]([^/:]+/[^/.]+)(\.git)?$", url)
    if not match:
        return None
    return normalize_repo_identifier(match.group(1))


def source_to_repo_identifier(source_payload: dict[str, Any]) -> str | None:
    github_repo = source_payload.get("githubRepo")
    if not isinstance(github_repo, dict):
        return None
    owner = github_repo.get("owner")
    repo = github_repo.get("repo")
    if not owner or not repo:
        return None
    return normalize_repo_identifier(f"{owner}/{repo}")


def source_branches(source_payload: dict[str, Any]) -> tuple[str, ...]:
    github_repo = source_payload.get("githubRepo")
    if not isinstance(github_repo, dict):
        return ()
    branches = github_repo.get("branches")
    if not isinstance(branches, list):
        return ()
    values = [
        branch.get("displayName")
        for branch in branches
        if isinstance(branch, dict) and branch.get("displayName")
    ]
    return tuple(values)


def default_branch(source_payload: dict[str, Any]) -> str | None:
    github_repo = source_payload.get("githubRepo")
    if not isinstance(github_repo, dict):
        return None
    default_value = github_repo.get("defaultBranch")
    if isinstance(default_value, dict):
        return default_value.get("displayName")
    return None


class JulesClient:
    def __init__(
        self,
        api_key: str,
        *,
        base_url: str = JULES_BASE_URL,
        session: requests.Session | Any | None = None,
        request_timeout_seconds: int = DEFAULT_REQUEST_TIMEOUT_SECONDS,
        source_cache_ttl_seconds: int = DEFAULT_SOURCE_CACHE_TTL_SECONDS,
    ) -> None:
        self.api_key = api_key
        self.base_url = base_url.rstrip("/")
        self.session = session or requests.Session()
        self._owns_session = session is None
        self.request_timeout_seconds = request_timeout_seconds
        self.source_cache_ttl_seconds = source_cache_ttl_seconds
        self._sources_cache: list[dict[str, Any]] | None = None
        self._sources_cache_at: float = 0.0

    def close(self) -> None:
        if self._owns_session and hasattr(self.session, "close"):
            self.session.close()

    def _headers(self) -> dict[str, str]:
        return {
            "Content-Type": "application/json",
            "x-goog-api-key": self.api_key,
        }

    def _request(
        self,
        method: str,
        path: str,
        *,
        params: dict[str, Any] | None = None,
        json_body: dict[str, Any] | None = None,
        expected_statuses: tuple[int, ...] = (200,),
    ) -> dict[str, Any]:
        url = f"{self.base_url}/{path.lstrip('/')}"
        requester = getattr(self.session, method.lower())
        try:
            response = requester(
                url,
                headers=self._headers(),
                params=params,
                json=json_body,
                timeout=self.request_timeout_seconds,
            )
        except requests.RequestException as exc:
            raise JulesApiError(
                f"Jules API {method.upper()} {path} request failed: {exc}",
                response_text=str(exc),
            ) from exc
        if response.status_code not in expected_statuses:
            raise JulesApiError(
                f"Jules API {method.upper()} {path} failed with status {response.status_code}",
                status_code=response.status_code,
                response_text=getattr(response, "text", None),
            )
        if response.status_code == 204:
            return {}
        return response.json()

    def list_sources(self, *, filter_expression: str | None = None, force_refresh: bool = False) -> list[dict[str, Any]]:
        now = time.monotonic()
        if (
            not filter_expression
            and not force_refresh
            and self._sources_cache is not None
            and now - self._sources_cache_at < self.source_cache_ttl_seconds
        ):
            return self._sources_cache

        params = {"filter": filter_expression} if filter_expression else None
        payload = self._request("get", "/sources", params=params)
        sources = payload.get("sources", [])
        if not isinstance(sources, list):
            raise JulesApiError("Jules API returned an invalid sources payload.")

        if not filter_expression:
            self._sources_cache = sources
            self._sources_cache_at = now
        return sources

    def build_source_map(self) -> dict[str, str]:
        mapping: dict[str, str] = {}
        for source in self.list_sources():
            source_name = source.get("name") or source.get("id")
            if not source_name:
                continue
            source_id = source.get("id")
            if source_id:
                mapping[source_id] = source_name
            repo_identifier = source_to_repo_identifier(source)
            if repo_identifier:
                mapping[repo_identifier] = source_name
                mapping[f"github/{repo_identifier}"] = source_name
        return mapping

    def resolve_source(
        self,
        *,
        source_name: str | None = None,
        repo_identifier: str | None = None,
    ) -> ResolvedSource:
        if source_name:
            for source in self.list_sources():
                if source.get("name") == source_name or source.get("id") == source_name:
                    return ResolvedSource(
                        name=source.get("name") or source_name,
                        repo_identifier=source_to_repo_identifier(source),
                        default_branch=default_branch(source),
                        branches=source_branches(source),
                    )
            raise JulesApiError(f"Jules source not found: {source_name}")

        if repo_identifier:
            normalized_repo = normalize_repo_identifier(repo_identifier)
            for source in self.list_sources():
                if source_to_repo_identifier(source) == normalized_repo:
                    return ResolvedSource(
                        name=source.get("name"),
                        repo_identifier=normalized_repo,
                        default_branch=default_branch(source),
                        branches=source_branches(source),
                    )
            raise JulesApiError(f"Jules source not found for repo: {normalized_repo}")

        raise JulesApiError("A Jules source name or repo identifier is required.")

    def validate_branch(self, resolved_source: ResolvedSource, branch: str | None) -> str:
        effective_branch = (branch or resolved_source.default_branch or "").strip()
        if not effective_branch:
            raise JulesApiError(
                f"No starting branch available for Jules source {resolved_source.name}."
            )
        if resolved_source.branches and effective_branch not in resolved_source.branches:
            raise JulesApiError(
                f"Branch '{effective_branch}' is not available on Jules source {resolved_source.name}."
            )
        return effective_branch

    def create_session(
        self,
        *,
        prompt: str,
        title: str | None = None,
        source_name: str | None = None,
        branch: str | None = None,
        require_plan_approval: bool = False,
        automation_mode: str = "AUTO_CREATE_PR",
    ) -> dict[str, Any]:
        payload: dict[str, Any] = {
            "prompt": prompt,
            "automationMode": automation_mode,
        }
        if title:
            payload["title"] = title
        if source_name:
            github_repo_context: dict[str, Any] = {}
            if branch:
                github_repo_context["startingBranch"] = branch
            payload["sourceContext"] = {"source": source_name}
            if github_repo_context:
                payload["sourceContext"]["githubRepoContext"] = github_repo_context
        if require_plan_approval:
            payload["requirePlanApproval"] = True
        return self._request("post", "/sessions", json_body=payload)

    def get_session(self, session_name: str) -> dict[str, Any]:
        return self._request("get", f"/{self._normalize_session_name(session_name)}")

    def list_activities(self, session_name: str, *, page_size: int = 100) -> list[dict[str, Any]]:
        activities: list[dict[str, Any]] = []
        next_page_token: str | None = None
        normalized_session = self._normalize_session_name(session_name)
        while True:
            params: dict[str, Any] = {"pageSize": page_size}
            if next_page_token:
                params["pageToken"] = next_page_token
            payload = self._request(
                "get",
                f"/{normalized_session}/activities",
                params=params,
            )
            page_activities = payload.get("activities", [])
            if not isinstance(page_activities, list):
                raise JulesApiError("Jules API returned an invalid activities payload.")
            activities.extend(page_activities)
            next_page_token = payload.get("nextPageToken")
            if not next_page_token:
                break
        return activities

    def delete_session(self, session_name: str) -> None:
        self._request(
            "delete",
            f"/{self._normalize_session_name(session_name)}",
            expected_statuses=(200, 204),
        )

    def send_message(self, session_name: str, prompt: str) -> None:
        self._request(
            "post",
            f"/{self._normalize_session_name(session_name)}:sendMessage",
            json_body={"prompt": prompt},
        )

    def approve_plan(self, session_name: str) -> None:
        self._request(
            "post",
            f"/{self._normalize_session_name(session_name)}:approvePlan",
            json_body={},
        )

    @staticmethod
    def _normalize_session_name(session_name: str) -> str:
        normalized = session_name.strip()
        if normalized.startswith("sessions/"):
            return normalized
        return f"sessions/{normalized}"


def extract_pull_request(session_payload: dict[str, Any]) -> dict[str, Any] | None:
    outputs = session_payload.get("outputs")
    if not isinstance(outputs, list):
        return None
    for output in outputs:
        if not isinstance(output, dict):
            continue
        pull_request = output.get("pullRequest")
        if isinstance(pull_request, dict):
            return pull_request
    return None
