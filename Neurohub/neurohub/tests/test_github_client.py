"""HTTP boundary tests for the typed GitHub client."""

from __future__ import annotations

import json

import httpx
import pytest

from neurohub.app.services.github_client import GitHubClient, GitHubError


def test_current_user_uses_bearer_token_without_query_secret() -> None:
    """OAuth credentials stay in the Authorization header."""

    def handler(request: httpx.Request) -> httpx.Response:
        assert request.url.path == "/user"
        assert request.url.query == b""
        assert request.headers["Authorization"] == "Bearer secret-token"
        return httpx.Response(200, json={"id": 1, "login": "alice"})

    client = GitHubClient("secret-token", transport=httpx.MockTransport(handler))
    try:
        assert client.current_user()["login"] == "alice"
    finally:
        client.close()


def test_github_error_maps_permission_to_actionable_message() -> None:
    """Raw upstream failures do not leak through the Neurohub API."""

    def handler(request: httpx.Request) -> httpx.Response:
        del request
        return httpx.Response(403, content=b"forbidden but internal")

    client = GitHubClient("token", transport=httpx.MockTransport(handler))
    try:
        with pytest.raises(GitHubError, match="do not have permission") as raised:
            client.current_user()
        assert raised.value.status_code == 403
        assert "internal" not in str(raised.value)
    finally:
        client.close()


def test_rate_limit_exhaustion_maps_to_429_with_retry_after() -> None:
    """A 403 with zero remaining quota is reported as a retryable rate limit."""

    def handler(request: httpx.Request) -> httpx.Response:
        del request
        return httpx.Response(
            403,
            headers={"X-RateLimit-Remaining": "0", "X-RateLimit-Reset": "1700000000"},
            json={"message": "rate limit exceeded"},
        )

    client = GitHubClient("token", transport=httpx.MockTransport(handler))
    try:
        with pytest.raises(GitHubError, match="rate limit") as raised:
            client.current_user()
        assert raised.value.status_code == 429
        assert raised.value.retry_after == "1700000000"
    finally:
        client.close()


def test_commit_files_builds_one_atomic_commit_via_git_data_api() -> None:
    """Manifest and workspace changes land in one commit via blob/tree/commit/ref."""
    calls: list[tuple[str, str]] = []

    def handler(request: httpx.Request) -> httpx.Response:
        calls.append((request.method, request.url.path))
        if request.url.path == "/repos/alice/demo/git/commits/base-sha":
            return httpx.Response(200, json={"sha": "base-sha", "tree": {"sha": "base-tree"}})
        if request.url.path == "/repos/alice/demo/git/blobs":
            return httpx.Response(201, json={"sha": f"blob-{len(calls)}"})
        if request.url.path == "/repos/alice/demo/git/trees":
            payload = json.loads(request.content)
            assert payload["base_tree"] == "base-tree"
            assert len(payload["tree"]) == 2
            return httpx.Response(201, json={"sha": "new-tree"})
        if request.url.path == "/repos/alice/demo/git/commits":
            payload = json.loads(request.content)
            assert payload["parents"] == ["base-sha"]
            assert payload["tree"] == "new-tree"
            return httpx.Response(201, json={"sha": "new-head"})
        if request.url.path == "/repos/alice/demo/git/refs/heads/main":
            payload = json.loads(request.content)
            assert payload["sha"] == "new-head"
            assert payload["force"] is False
            return httpx.Response(200, json={"ref": "refs/heads/main"})
        raise AssertionError(f"unexpected request: {request.method} {request.url.path}")

    client = GitHubClient("token", transport=httpx.MockTransport(handler))
    try:
        new_sha = client.commit_files(
            "alice",
            "demo",
            branch="main",
            message="Save workspace",
            base_commit="base-sha",
            files=[(".neurohub/manifest.json", b"{}"), ("workspace.nmtk.json", b"{}")],
        )
        assert new_sha == "new-head"
    finally:
        client.close()


def test_commit_files_raises_on_non_fast_forward_ref_update() -> None:
    """A ref update that isn't a fast-forward means someone else moved the branch."""

    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.path == "/repos/alice/demo/git/commits/base-sha":
            return httpx.Response(200, json={"sha": "base-sha", "tree": {"sha": "base-tree"}})
        if request.url.path == "/repos/alice/demo/git/blobs":
            return httpx.Response(201, json={"sha": "blob-1"})
        if request.url.path == "/repos/alice/demo/git/trees":
            return httpx.Response(201, json={"sha": "new-tree"})
        if request.url.path == "/repos/alice/demo/git/commits":
            return httpx.Response(201, json={"sha": "new-head"})
        if request.url.path == "/repos/alice/demo/git/refs/heads/main":
            return httpx.Response(422, json={"message": "Update is not a fast forward"})
        raise AssertionError(f"unexpected request: {request.method} {request.url.path}")

    client = GitHubClient("token", transport=httpx.MockTransport(handler))
    try:
        with pytest.raises(GitHubError) as raised:
            client.commit_files(
                "alice",
                "demo",
                branch="main",
                message="Save workspace",
                base_commit="base-sha",
                files=[(".neurohub/manifest.json", b"{}")],
            )
        assert raised.value.status_code == 422
    finally:
        client.close()
