"""Workspace store and API tests using an in-memory GitHub boundary fake."""

# ruff: noqa: D102, D107

from __future__ import annotations

import base64
import hashlib
from typing import Any

import pytest
from fastapi.testclient import TestClient

from neurohub.app.main import app
from neurohub.app.routers.workspaces import get_workspace_store
from neurohub.app.services.github_client import GitHubError
from neurohub.app.services.github_workspace_store import GitHubWorkspaceStore
from neurohub.contracts.workspace_contracts import WorkspaceCreate, WorkspaceUpdate


class FakeGitHubClient:
    """Minimal stateful implementation of the GitHub calls used by the store."""

    def __init__(self) -> None:
        self.user = {"id": 1, "login": "alice"}
        self.repo: dict[str, Any] | None = None
        self.files: dict[str, bytes] = {}
        self.head = "initial-commit"
        self.commits = 0
        self.collaborators: dict[str, str] = {}

    def current_user(self) -> dict[str, Any]:
        return self.user

    def list_current_user_repositories(self) -> list[dict[str, Any]]:
        return [self.repo] if self.repo is not None else []

    def create_repository(self, *, name: str, description: str, private: bool) -> dict[str, Any]:
        if self.repo is not None:
            raise GitHubError("already exists", status_code=422)
        self.repo = {
            "name": name,
            "description": description,
            "private": private,
            "archived": False,
            "updated_at": "2026-08-13T20:00:00Z",
            "html_url": f"https://github.com/alice/{name}",
            "owner": {"login": "alice"},
            "permissions": {"admin": True, "push": True, "pull": True},
            "topics": [],
        }
        return self.repo

    def get_repository(self, owner: str, repo: str) -> dict[str, Any]:
        if self.repo is None or owner != "alice" or repo != self.repo["name"]:
            raise GitHubError("not found", status_code=404)
        return self.repo

    def edit_repository(self, owner: str, repo: str, **changes: Any) -> dict[str, Any]:
        current = self.get_repository(owner, repo)
        current.update(changes)
        return current

    def set_topics(self, owner: str, repo: str, topics: list[str]) -> None:
        self.get_repository(owner, repo)["topics"] = topics

    def branch_head_commit(self, owner: str, repo: str, branch: str = "main") -> str:
        del branch
        self.get_repository(owner, repo)
        return self.head

    def content(
        self, owner: str, repo: str, path: str, *, ref: str | None = None
    ) -> dict[str, Any]:
        del ref
        self.get_repository(owner, repo)
        if path not in self.files:
            raise GitHubError("not found", status_code=404)
        return {"content": base64.b64encode(self.files[path]).decode("ascii"), "sha": path}

    def decoded_content(self, owner: str, repo: str, path: str, *, ref: str | None = None) -> bytes:
        item = self.content(owner, repo, path, ref=ref)
        return base64.b64decode(item["content"])

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
        del branch, message
        self.get_repository(owner, repo)
        if base_commit != self.head:
            raise GitHubError("Update is not a fast forward", status_code=422)
        for path, content in files:
            self.files[path] = content
        self.commits += 1
        self.head = f"commit-{self.commits}"
        return self.head

    def add_collaborator(self, owner: str, repo: str, username: str, permission: str) -> None:
        self.get_repository(owner, repo)
        self.collaborators[username] = permission

    def remove_collaborator(self, owner: str, repo: str, username: str) -> None:
        self.get_repository(owner, repo)
        self.collaborators.pop(username, None)


@pytest.fixture
def workspace_store() -> GitHubWorkspaceStore:
    """Return a fresh workspace store over the in-memory boundary fake."""
    return GitHubWorkspaceStore(FakeGitHubClient())


def _create(store: GitHubWorkspaceStore):
    return store.create_workspace(
        WorkspaceCreate(
            slug="mnist-akida",
            display_name="MNIST Akida",
            tags=["mnist", "akida"],
            workspace={"revision": 1, "nodes": []},
        )
    )


def test_create_workspace_is_private_and_checksum_verified(
    workspace_store: GitHubWorkspaceStore,
) -> None:
    """A workspace is private by default and opens from its first commit."""
    created = _create(workspace_store)
    assert created.private is True
    assert created.owner == "alice"
    assert created.head_commit == "commit-1"
    assert created.workspace["revision"] == 1
    assert (
        created.manifest.payload.sha256
        == hashlib.sha256(b'{"nodes":[],"revision":1}\n').hexdigest()
    )


def test_update_creates_one_commit_for_manifest_and_workspace(
    workspace_store: GitHubWorkspaceStore,
) -> None:
    """A logical save creates exactly one GitHub commit."""
    created = _create(workspace_store)
    updated = workspace_store.update_workspace(
        "alice",
        "mnist-akida",
        WorkspaceUpdate(
            base_commit=created.head_commit,
            workspace={"revision": 2, "nodes": ["input"]},
        ),
    )
    fake = workspace_store.client
    assert isinstance(fake, FakeGitHubClient)
    assert fake.commits == 2
    assert updated.head_commit == "commit-2"
    assert updated.workspace["revision"] == 2


def test_stale_save_returns_stable_api_conflict(
    client: TestClient,
    workspace_store: GitHubWorkspaceStore,
) -> None:
    """A stale client gets recovery options and neither revision is overwritten."""
    created = _create(workspace_store)
    workspace_store.update_workspace(
        "alice",
        "mnist-akida",
        WorkspaceUpdate(base_commit=created.head_commit, workspace={"revision": 2}),
    )
    app.dependency_overrides[get_workspace_store] = lambda: workspace_store
    try:
        response = client.put(
            "/api/neurohub/workspaces/alice/mnist-akida",
            json={"base_commit": created.head_commit, "workspace": {"revision": 3}},
        )
    finally:
        app.dependency_overrides.pop(get_workspace_store, None)
    assert response.status_code == 409
    detail = response.json()["detail"]
    assert detail["code"] == "workspace_conflict"
    assert detail["base_commit"] == "commit-1"
    assert detail["remote_commit"] == "commit-2"
    assert detail["recovery"] == ["reload", "save_copy", "resolve"]
    assert workspace_store.get_workspace("alice", "mnist-akida").workspace["revision"] == 2


def test_collaboration_visibility_and_archive_use_github_permissions(
    workspace_store: GitHubWorkspaceStore,
) -> None:
    """Sharing and lifecycle state are native repository operations."""
    _create(workspace_store)
    workspace_store.add_collaborator("alice", "mnist-akida", "bob", "write")
    fake = workspace_store.client
    assert isinstance(fake, FakeGitHubClient)
    assert fake.collaborators == {"bob": "push"}
    assert workspace_store.set_public("alice", "mnist-akida", public=True).private is False
    workspace_store.archive("alice", "mnist-akida")
    assert workspace_store.get_workspace("alice", "mnist-akida").archived is True
    workspace_store.remove_collaborator("alice", "mnist-akida", "bob")
    assert fake.collaborators == {}


def test_workspace_api_requires_sign_in(client: TestClient) -> None:
    """The central workspace surface never inherits the legacy auth bypass."""
    response = client.get("/api/neurohub/workspaces")
    assert response.status_code == 401
    assert response.headers["WWW-Authenticate"] == "Bearer"


def test_large_workspace_is_rejected_before_github_write(
    workspace_store: GitHubWorkspaceStore,
) -> None:
    """Large binary-like payloads are kept out of workspace Git history."""
    with pytest.raises(GitHubError, match="10 MB") as raised:
        workspace_store.create_workspace(
            WorkspaceCreate(
                slug="too-large",
                display_name="Too large",
                workspace={"payload": "x" * (10 * 1024 * 1024)},
            )
        )
    assert raised.value.status_code == 413
    fake = workspace_store.client
    assert isinstance(fake, FakeGitHubClient)
    assert fake.repo is None
