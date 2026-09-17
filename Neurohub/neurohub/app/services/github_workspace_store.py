"""GitHub repository mapping for Neurohub workspaces.

Save pipeline:

    client base SHA -> one atomic Git Data API commit (manifest + workspace)
        -> fast-forward-only ref update -> return new main SHA

Every save updates both the workspace and its checksum-bearing manifest, so a
partial revision cannot be observed through Neurohub. The ref update is
fast-forward-only, so a stale base commit fails the write instead of racing
another writer.
"""

from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass
from typing import Any, Literal

from neurohub.app.services.github_client import GitHubClient, GitHubError
from neurohub.contracts.workspace_contracts import (
    NeurohubWorkspaceManifest,
    WorkspaceCreate,
    WorkspacePayloadRef,
    WorkspaceResponse,
    WorkspaceSummary,
    WorkspaceUpdate,
)

_MANIFEST_PATH = ".neurohub/manifest.json"
_WORKSPACE_PATH = "workspace.nmtk.json"
_TOPICS = ["neurohub", "neurohub-workspace", "studio-workspace"]
_MAX_WORKSPACE_BYTES = 10 * 1024 * 1024

_PERMISSION_TO_GITHUB = {"read": "pull", "write": "push", "admin": "admin"}


@dataclass(frozen=True)
class WorkspaceSaveConflict(Exception):
    """The caller attempted to save from a stale base commit."""

    base_commit: str
    remote_commit: str


class GitHubWorkspaceStore:
    """Workspace operations backed by a user-scoped GitHub client."""

    def __init__(self, client: GitHubClient) -> None:
        """Create a workspace store over a user-scoped GitHub client."""
        self.client = client

    def list_workspaces(self) -> list[WorkspaceSummary]:
        """List workspace repositories visible to the authenticated user."""
        summaries: list[WorkspaceSummary] = []
        for repo in self.client.list_current_user_repositories():
            if not self._is_workspace_repository(repo):
                continue
            owner = str(repo["owner"]["login"])
            slug = str(repo["name"])
            try:
                workspace = self.get_workspace(owner, slug)
            except GitHubError as exc:
                if exc.status_code == 404:
                    continue
                raise
            summaries.append(
                WorkspaceSummary(**workspace.model_dump(exclude={"workspace", "manifest"}))
            )
        return sorted(summaries, key=lambda item: item.updated_at, reverse=True)

    def create_workspace(self, request: WorkspaceCreate) -> WorkspaceResponse:
        """Create a private-by-default repository and its first workspace commit."""
        self._ensure_workspace_size(request.workspace)
        user = self.client.current_user()
        owner = str(user["login"])
        self.client.create_repository(
            name=request.slug,
            description=request.description or request.display_name,
            private=request.private,
        )
        self.client.set_topics(owner, request.slug, _TOPICS)
        head = self.client.branch_head_commit(owner, request.slug)
        update = WorkspaceUpdate(
            base_commit=head,
            workspace=request.workspace,
            display_name=request.display_name,
            description=request.description,
            tags=request.tags,
            message="Create Neurohub workspace",
        )
        return self._save(owner, request.slug, update, nmtk=request.nmtk)

    def get_workspace(self, owner: str, slug: str) -> WorkspaceResponse:
        """Load and verify the workspace at the repository's current head."""
        repo = self.client.get_repository(owner, slug)
        head = self.client.branch_head_commit(owner, slug)
        manifest_raw = self.client.decoded_content(owner, slug, _MANIFEST_PATH, ref=head)
        workspace_raw = self.client.decoded_content(owner, slug, _WORKSPACE_PATH, ref=head)
        try:
            manifest = NeurohubWorkspaceManifest.model_validate_json(manifest_raw)
            workspace = json.loads(workspace_raw)
        except (ValueError, TypeError) as exc:
            raise GitHubError(
                "This repository does not contain a valid Neurohub workspace."
            ) from exc
        if not isinstance(workspace, dict):
            raise GitHubError("This Neurohub workspace document must be a JSON object.")
        digest = hashlib.sha256(workspace_raw).hexdigest()
        if digest != manifest.payload.sha256:
            raise GitHubError(
                "The Neurohub workspace checksum does not match its manifest. Download is blocked."
            )
        return self._response(repo, manifest, workspace, head)

    def update_workspace(
        self, owner: str, slug: str, request: WorkspaceUpdate
    ) -> WorkspaceResponse:
        """Save a workspace when its base commit is still current."""
        return self._save(owner, slug, request)

    def add_collaborator(self, owner: str, slug: str, username: str, permission: str) -> None:
        """Grant a collaborator repository access."""
        self.client.add_collaborator(
            owner, slug, username, _PERMISSION_TO_GITHUB.get(permission, permission)
        )

    def remove_collaborator(self, owner: str, slug: str, username: str) -> None:
        """Revoke a collaborator's repository access."""
        self.client.remove_collaborator(owner, slug, username)

    def set_public(self, owner: str, slug: str, *, public: bool) -> WorkspaceResponse:
        """Explicitly change visibility, then return the current workspace."""
        self.client.edit_repository(owner, slug, private=not public)
        return self.get_workspace(owner, slug)

    def archive(self, owner: str, slug: str) -> None:
        """Soft-delete a workspace by archiving its repository."""
        self.client.edit_repository(owner, slug, archived=True)

    def _save(
        self,
        owner: str,
        slug: str,
        request: WorkspaceUpdate,
        *,
        nmtk: dict[str, str] | None = None,
    ) -> WorkspaceResponse:
        remote_commit = self.client.branch_head_commit(owner, slug)
        if remote_commit != request.base_commit:
            raise WorkspaceSaveConflict(request.base_commit, remote_commit)

        current_manifest: NeurohubWorkspaceManifest | None = None
        try:
            current_manifest = NeurohubWorkspaceManifest.model_validate_json(
                self.client.decoded_content(owner, slug, _MANIFEST_PATH, ref=request.base_commit)
            )
        except GitHubError as exc:
            if exc.status_code != 404:
                raise

        workspace_raw = self._canonical_json(request.workspace)
        self._ensure_workspace_size(request.workspace, encoded=workspace_raw)
        manifest = NeurohubWorkspaceManifest(
            slug=slug,
            display_name=request.display_name
            or (current_manifest.display_name if current_manifest else slug),
            description=request.description
            if request.description is not None
            else (current_manifest.description if current_manifest else ""),
            tags=request.tags
            if request.tags is not None
            else (current_manifest.tags if current_manifest else []),
            payload=WorkspacePayloadRef(sha256=hashlib.sha256(workspace_raw).hexdigest()),
            nmtk=nmtk if nmtk is not None else (current_manifest.nmtk if current_manifest else {}),
        )
        manifest_raw = self._canonical_json(manifest.model_dump(mode="json"))

        try:
            self.client.commit_files(
                owner,
                slug,
                branch="main",
                message=request.message,
                base_commit=request.base_commit,
                files=[(_MANIFEST_PATH, manifest_raw), (_WORKSPACE_PATH, workspace_raw)],
            )
        except GitHubError as exc:
            if exc.status_code in {409, 422}:
                raise WorkspaceSaveConflict(
                    request.base_commit, self.client.branch_head_commit(owner, slug)
                ) from exc
            raise

        return self.get_workspace(owner, slug)

    @staticmethod
    def _canonical_json(value: Any) -> bytes:
        return (json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n").encode()

    @classmethod
    def _ensure_workspace_size(
        cls, workspace: dict[str, Any], *, encoded: bytes | None = None
    ) -> None:
        if (
            len(encoded if encoded is not None else cls._canonical_json(workspace))
            > _MAX_WORKSPACE_BYTES
        ):
            raise GitHubError(
                "This workspace is larger than Neurohub's 10 MB Git storage limit. "
                "Keep large recordings, datasets, and models as linked artefacts.",
                status_code=413,
            )

    @staticmethod
    def _is_workspace_repository(repo: dict[str, Any]) -> bool:
        topics = {str(topic) for topic in repo.get("topics", [])}
        return "neurohub-workspace" in topics or str(repo.get("name", "")).startswith("workspace-")

    @staticmethod
    def _permission(repo: dict[str, Any]) -> Literal["read", "write", "admin"]:
        permissions = repo.get("permissions") or {}
        if permissions.get("admin"):
            return "admin"
        if permissions.get("push"):
            return "write"
        return "read"

    def _response(
        self,
        repo: dict[str, Any],
        manifest: NeurohubWorkspaceManifest,
        workspace: dict[str, Any],
        head: str,
    ) -> WorkspaceResponse:
        owner = str(repo["owner"]["login"])
        slug = str(repo["name"])
        return WorkspaceResponse(
            owner=owner,
            slug=slug,
            display_name=manifest.display_name,
            description=manifest.description,
            tags=manifest.tags,
            private=bool(repo.get("private", True)),
            archived=bool(repo.get("archived", False)),
            updated_at=str(repo.get("updated_at", "")),
            head_commit=head,
            repository_url=str(repo.get("html_url", "")),
            permission=self._permission(repo),
            neurohub_uri=f"neurohub://studio_workspace/{owner}/{slug}",
            workspace=workspace,
            manifest=manifest,
        )
