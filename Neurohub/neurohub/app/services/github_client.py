"""Typed HTTP client for the GitHub APIs used by Neurohub."""

from __future__ import annotations

import base64
import os
from collections.abc import Mapping
from typing import Any
from urllib.parse import quote

import httpx

_API_VERSION = "2022-11-28"


class GitHubError(Exception):
    """A stable error translated from a GitHub response or transport failure."""

    def __init__(
        self,
        message: str,
        *,
        status_code: int = 503,
        retry_after: str | None = None,
    ) -> None:
        """Create an error with a safe client-facing message."""
        super().__init__(message)
        self.status_code = status_code
        self.retry_after = retry_after


class GitHubClient:
    """Small user-token-scoped GitHub REST client."""

    def __init__(
        self,
        token: str,
        *,
        base_url: str | None = None,
        transport: httpx.BaseTransport | None = None,
        timeout: float = 15.0,
    ) -> None:
        """Create a client for one user-scoped OAuth token."""
        configured_url = (base_url or os.environ.get("GITHUB_API_BASE_URL") or "https://api.github.com").rstrip(
            "/"
        )
        self._client = httpx.Client(
            base_url=configured_url,
            headers={
                "Authorization": f"Bearer {token}",
                "Accept": "application/vnd.github+json",
                "X-GitHub-Api-Version": _API_VERSION,
            },
            timeout=timeout,
            transport=transport,
        )

    def close(self) -> None:
        """Close the underlying HTTP connection pool."""
        self._client.close()

    def request(
        self,
        method: str,
        path: str,
        *,
        params: Mapping[str, Any] | None = None,
        json: Any | None = None,
        expected: tuple[int, ...] = (200,),
    ) -> Any:
        """Send one request and translate GitHub failures."""
        try:
            response = self._client.request(method, path, params=params, json=json)
        except (httpx.TimeoutException, httpx.NetworkError) as exc:
            raise GitHubError(
                "Neurohub cannot reach GitHub. Try again without closing your work."
            ) from exc
        if response.status_code not in expected:
            raise self._translate_error(response)
        if response.status_code == 204 or not response.content:
            return None
        return response.json()

    def _translate_error(self, response: httpx.Response) -> GitHubError:
        if response.status_code == 403 and response.headers.get("X-RateLimit-Remaining") == "0":
            return GitHubError(
                "Your GitHub rate limit is exhausted. Try again after it resets.",
                status_code=429,
                retry_after=response.headers.get("Retry-After") or response.headers.get(
                    "X-RateLimit-Reset"
                ),
            )
        fallback = {
            401: "Your Neurohub session is no longer valid. Sign in again.",
            403: "You do not have permission to change this Neurohub workspace.",
            404: "The Neurohub workspace no longer exists or is not visible to you.",
            409: "The workspace changed on GitHub before this save landed.",
            422: "GitHub rejected the workspace update because its revision changed.",
            429: "Neurohub is receiving too many requests. Try again shortly.",
        }.get(response.status_code, "GitHub could not complete the request.")
        return GitHubError(
            fallback,
            status_code=response.status_code,
            retry_after=response.headers.get("Retry-After"),
        )

    def current_user(self) -> dict[str, Any]:
        """Return the authenticated GitHub user."""
        return dict(self.request("GET", "/user"))

    def list_current_user_repositories(self) -> list[dict[str, Any]]:
        """List all repositories visible to the current user."""
        rows: list[dict[str, Any]] = []
        page = 1
        while page <= 100:
            payload = self.request(
                "GET", "/user/repos", params={"page": page, "per_page": 100, "affiliation": "owner"}
            )
            batch = [dict(row) for row in payload]
            rows.extend(batch)
            if len(batch) < 100:
                return rows
            page += 1
        raise GitHubError("Neurohub repository listing exceeded its safe pagination limit.")

    def create_repository(self, *, name: str, description: str, private: bool) -> dict[str, Any]:
        """Create an initialized user-owned repository."""
        return dict(
            self.request(
                "POST",
                "/user/repos",
                json={
                    "name": name,
                    "description": description,
                    "private": private,
                    "auto_init": True,
                },
                expected=(201,),
            )
        )

    def get_repository(self, owner: str, repo: str) -> dict[str, Any]:
        """Return a repository visible to the user."""
        return dict(self.request("GET", self._repo_path(owner, repo)))

    def edit_repository(self, owner: str, repo: str, **changes: Any) -> dict[str, Any]:
        """Update repository properties such as visibility or archive state."""
        return dict(
            self.request("PATCH", self._repo_path(owner, repo), json=changes, expected=(200,))
        )

    def delete_repository(self, owner: str, repo: str) -> None:
        """Permanently delete a repository for disposable tests."""
        self.request("DELETE", self._repo_path(owner, repo), expected=(204,))

    def set_topics(self, owner: str, repo: str, topics: list[str]) -> None:
        """Replace repository topics."""
        self.request(
            "PUT",
            f"{self._repo_path(owner, repo)}/topics",
            json={"names": topics},
            expected=(200,),
        )

    def branch_head_commit(self, owner: str, repo: str, branch: str = "main") -> str:
        """Return the current commit SHA at the tip of a branch."""
        payload = self.request(
            "GET", f"{self._repo_path(owner, repo)}/branches/{quote(branch, safe='')}"
        )
        return str(payload["commit"]["sha"])

    def content(
        self, owner: str, repo: str, path: str, *, ref: str | None = None
    ) -> dict[str, Any]:
        """Return one repository content entry."""
        params = {"ref": ref} if ref else None
        return dict(
            self.request(
                "GET",
                f"{self._repo_path(owner, repo)}/contents/{quote(path, safe='/')}",
                params=params,
            )
        )

    def decoded_content(self, owner: str, repo: str, path: str, *, ref: str | None = None) -> bytes:
        """Fetch and base64-decode one repository file."""
        item = self.content(owner, repo, path, ref=ref)
        try:
            encoded = "".join(str(item["content"]).split())
            return base64.b64decode(encoded, validate=True)
        except (KeyError, ValueError) as exc:
            raise GitHubError("Neurohub received an invalid workspace file from GitHub.") from exc

    def commit_files(
        self,
        owner: str,
        repo: str,
        *,
        branch: str,
        message: str,
        base_commit: str,
        files: list[tuple[str, bytes]],
    ) -> str:
        """Commit one or more files atomically via the Git Data API.

        GitHub's Contents API only writes one file per request, so an atomic
        multi-file commit is built by hand: blob per file, one new tree layered
        on the base commit's tree, one commit with that tree, then a
        fast-forward-only ref update. The ref update rejects the write with a
        409/422 if ``base_commit`` is no longer the branch tip, which is the
        same optimistic-concurrency guarantee the workspace store relies on.
        """
        base_commit_obj = self.request(
            "GET", f"{self._repo_path(owner, repo)}/git/commits/{base_commit}"
        )
        base_tree_sha = str(base_commit_obj["tree"]["sha"])

        tree_entries = []
        for path, content in files:
            blob = self.request(
                "POST",
                f"{self._repo_path(owner, repo)}/git/blobs",
                json={"content": base64.b64encode(content).decode("ascii"), "encoding": "base64"},
                expected=(201,),
            )
            tree_entries.append(
                {"path": path, "mode": "100644", "type": "blob", "sha": blob["sha"]}
            )

        new_tree = self.request(
            "POST",
            f"{self._repo_path(owner, repo)}/git/trees",
            json={"base_tree": base_tree_sha, "tree": tree_entries},
            expected=(201,),
        )
        new_commit = self.request(
            "POST",
            f"{self._repo_path(owner, repo)}/git/commits",
            json={"message": message, "tree": new_tree["sha"], "parents": [base_commit]},
            expected=(201,),
        )
        new_commit_sha = str(new_commit["sha"])

        ref_response = self._client.request(
            "PATCH",
            f"{self._repo_path(owner, repo)}/git/refs/heads/{quote(branch, safe='')}",
            json={"sha": new_commit_sha, "force": False},
        )
        if ref_response.status_code not in (200,):
            raise self._translate_error(ref_response)
        return new_commit_sha

    def add_collaborator(self, owner: str, repo: str, username: str, permission: str) -> None:
        """Add or update a repository collaborator."""
        self.request(
            "PUT",
            f"{self._repo_path(owner, repo)}/collaborators/{quote(username, safe='')}",
            json={"permission": permission},
            expected=(201, 204),
        )

    def remove_collaborator(self, owner: str, repo: str, username: str) -> None:
        """Remove a repository collaborator."""
        self.request(
            "DELETE",
            f"{self._repo_path(owner, repo)}/collaborators/{quote(username, safe='')}",
            expected=(204,),
        )

    @staticmethod
    def _repo_path(owner: str, repo: str) -> str:
        return f"/repos/{quote(owner, safe='')}/{quote(repo, safe='')}"
