"""Module state serialization plus remote-version resolution."""

from __future__ import annotations

import json
import os
import re
import urllib.error
import urllib.request
from typing import Any
from urllib.parse import urlparse

from packaging.version import InvalidVersion, Version
from packaging.version import parse as parse_version

from .module_environment import _effective_port

GITHUB_API_PAGE_SIZE = 100
GITHUB_API_TIMEOUT_SECONDS = 3.0
GITHUB_API_ACCEPT = "application/vnd.github+json"
GITHUB_USER_AGENT = "NeuroMorphicToolkit-LauncherControl"
GITHUB_API_BASE = "https://api.github.com"
GITHUB_HTML_BASE = "https://github.com"
PRERELEASE_VERSION_PATTERN = re.compile(
    r"(?:^|[.\-])(alpha|beta|rc|dev|nightly|snapshot|canary|preview)(?:[.\-\d]|$)",
    re.IGNORECASE,
)


def _normalize_version_string(raw: str) -> str:
    raw = raw.strip()
    raw = raw.removeprefix("v")
    return raw


def _parse_version(version: str) -> Version | None:
    try:
        return parse_version(version)
    except InvalidVersion:
        return None


def _compare_versions(left: str, right: str) -> int:
    try:
        left_parsed = parse_version(left)
        right_parsed = parse_version(right)
        if left_parsed < right_parsed:
            return -1
        if left_parsed > right_parsed:
            return 1
        return 0
    except InvalidVersion:
        normalized_left = _normalize_version_string(left)
        normalized_right = _normalize_version_string(right)
        if normalized_left == normalized_right:
            return 0
        return 1 if normalized_left > normalized_right else -1


def _is_newer_version(current: str, candidate: str) -> bool:
    return _compare_versions(candidate, current) > 0


def _coerce_remote_update_version(current: str, candidate: str | None) -> str:
    if candidate is not None and _is_newer_version(current, candidate):
        return _normalize_version_string(candidate)
    return current


def _is_prerelease_version(version: str) -> bool:
    try:
        parsed = parse_version(version)
        return parsed.is_prerelease
    except InvalidVersion:
        return (
            PRERELEASE_VERSION_PATTERN.search(_normalize_version_string(version))
            is not None
        )


def _normalize_github_repo_api_url(remote_url: str) -> str | None:
    parsed = urlparse(remote_url)
    if parsed.scheme not in {"http", "https"}:
        return None
    path = parsed.path.rstrip("/")
    if parsed.netloc == "api.github.com" and path.startswith("/repos/"):
        return f"{GITHUB_API_BASE}{path}"
    if parsed.netloc == "github.com":
        parts = [part for part in path.split("/") if part]
        if len(parts) < 2:
            return None
        owner, repo = parts[0], parts[1].removesuffix(".git")
        return f"{GITHUB_API_BASE}/repos/{owner}/{repo}"
    return None


def _github_repo_html_url(remote_url: str) -> str | None:
    api_url = _normalize_github_repo_api_url(remote_url)
    if api_url is None:
        return None
    parsed = urlparse(api_url)
    parts = [part for part in parsed.path.split("/") if part]
    if len(parts) < 3 or parts[0] != "repos":
        return None
    return f"{GITHUB_HTML_BASE}/{parts[1]}/{parts[2]}"


def _github_api_headers() -> dict[str, str]:
    headers = {
        "Accept": GITHUB_API_ACCEPT,
        "User-Agent": GITHUB_USER_AGENT,
    }
    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
    if token:
        headers["Authorization"] = f"Bearer {token}"
    return headers


def _read_json_url(url: str) -> Any | None:
    request = urllib.request.Request(url, headers=_github_api_headers())
    try:
        with urllib.request.urlopen(
            request,
            timeout=GITHUB_API_TIMEOUT_SECONDS,
        ) as response:
            return json.loads(response.read().decode("utf-8"))
    except (
        json.JSONDecodeError,
        TimeoutError,
        urllib.error.HTTPError,
        urllib.error.URLError,
    ):
        return None


def _resolve_latest_stable_tag_version(remote_url: str) -> str | None:
    repo_api_url = _normalize_github_repo_api_url(remote_url)
    if repo_api_url is None:
        return None
    payload = _read_json_url(f"{repo_api_url}/tags?per_page={GITHUB_API_PAGE_SIZE}")
    if not isinstance(payload, list):
        return None

    best_version: str | None = None
    for item in payload:
        if not isinstance(item, dict):
            continue
        raw_name = item.get("name")
        if not isinstance(raw_name, str):
            continue
        normalized = _normalize_version_string(raw_name)
        if _parse_version(normalized) is None or _is_prerelease_version(normalized):
            continue
        if best_version is None or _is_newer_version(best_version, normalized):
            best_version = normalized
    return best_version


def _resolve_remote_module_version(module: dict[str, Any]) -> str | None:
    remote_url = module.get("remoteUrl")
    if not isinstance(remote_url, str) or not remote_url.strip():
        return None
    return _resolve_latest_stable_tag_version(remote_url)


class ModuleRegistryMixin:
    def serialize_modules(
        self, *, refresh_updates: bool = False
    ) -> list[dict[str, Any]]:
        if refresh_updates:
            self.refresh_remote_versions()
        with self._lock:
            return [self._serialize_module(module) for module in self._modules.values()]

    def serialize_module(self, module_id: str) -> dict[str, Any]:
        with self._lock:
            module = self._get_module(module_id)
            return self._serialize_module(module)

    def _serialize_module(self, module: dict[str, Any]) -> dict[str, Any]:
        payload = dict(module)
        payload["directory"] = module["directory"]
        payload["effectivePort"] = _effective_port(module)
        return payload

    def refresh_remote_versions(self) -> None:
        with self._lock:
            snapshots = [dict(module) for module in self._modules.values()]

        refreshed_versions: dict[str, str] = {}
        for module in snapshots:
            module_id = str(module["id"])
            current_version = str(module.get("version", "0.0.0"))
            if bool(module.get("versionPinned", False)):
                refreshed_versions[module_id] = current_version
                continue
            existing_remote_version = str(module.get("remoteVersion", current_version))
            resolved_version = self._remote_version_resolver(module)
            refreshed_versions[module_id] = _coerce_remote_update_version(
                current_version,
                resolved_version or existing_remote_version,
            )

        with self._lock:
            changed = False
            for module_id, remote_version in refreshed_versions.items():
                mod = self._modules.get(module_id)
                if mod is None or mod.get("remoteVersion") == remote_version:
                    continue
                mod["remoteVersion"] = remote_version
                changed = True
            if changed:
                self._persist_states()
