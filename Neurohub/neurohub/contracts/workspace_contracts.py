"""Contracts for GitHub-backed Neurohub workspaces."""

from __future__ import annotations

import re
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator

_SLUG_RE = re.compile(r"[a-z0-9][a-z0-9-]{0,63}\Z")
_SHA256_RE = re.compile(r"[0-9a-f]{64}\Z")


def _validate_slug(value: str) -> str:
    if not _SLUG_RE.fullmatch(value):
        raise ValueError(
            "slug must be 1-64 lowercase alphanumeric or hyphen characters "
            "and start with an alphanumeric"
        )
    return value


def _normalize_tags(value: list[str]) -> list[str]:
    tags = [tag.strip().lower() for tag in value if tag.strip()]
    if any(len(tag) > 50 for tag in tags):
        raise ValueError("workspace tags must be 50 characters or fewer")
    return list(dict.fromkeys(tags))


def _conflict_recovery() -> list[Literal["reload", "save_copy", "resolve"]]:
    return ["reload", "save_copy", "resolve"]


class WorkspacePayloadRef(BaseModel):
    """Location and integrity metadata for a workspace payload."""

    path: str = "workspace.nmtk.json"
    sha256: str
    media_type: str = "application/vnd.nmtk.workspace+json"

    @field_validator("path")
    @classmethod
    def validate_path(cls, value: str) -> str:
        """Keep payloads within the repository and away from metadata files."""
        if value.startswith(("/", ".neurohub/")) or ".." in value.split("/"):
            raise ValueError("payload path must stay inside the workspace repository")
        return value

    @field_validator("sha256")
    @classmethod
    def validate_sha256(cls, value: str) -> str:
        """Require a lowercase SHA-256 digest."""
        if not _SHA256_RE.fullmatch(value):
            raise ValueError("sha256 must be a 64-character lowercase hexadecimal digest")
        return value


class NeurohubWorkspaceManifest(BaseModel):
    """Canonical ``.neurohub/manifest.json`` document for a workspace."""

    model_config = ConfigDict(extra="forbid")

    schema_version: Literal[1] = 1
    kind: Literal["workspace"] = "workspace"
    artefact_type: Literal["studio_workspace"] = "studio_workspace"
    slug: str
    display_name: str = Field(min_length=1, max_length=120)
    description: str = Field(default="", max_length=1000)
    tags: list[str] = Field(default_factory=list, max_length=20)
    payload: WorkspacePayloadRef
    nmtk: dict[str, str] = Field(default_factory=dict)

    @field_validator("slug")
    @classmethod
    def validate_slug(cls, value: str) -> str:
        """Use a stable repository-safe slug."""
        return _validate_slug(value)

    @field_validator("tags")
    @classmethod
    def normalize_tags(cls, value: list[str]) -> list[str]:
        """Normalize tags without silently changing their meaning."""
        return _normalize_tags(value)


class WorkspaceCreate(BaseModel):
    """Request to create a private workspace repository."""

    slug: str
    display_name: str = Field(min_length=1, max_length=120)
    description: str = Field(default="", max_length=1000)
    tags: list[str] = Field(default_factory=list, max_length=20)
    workspace: dict[str, Any]
    private: bool = True
    nmtk: dict[str, str] = Field(default_factory=dict)

    @field_validator("slug")
    @classmethod
    def validate_slug(cls, value: str) -> str:
        """Use a stable repository-safe slug."""
        return _validate_slug(value)

    @field_validator("tags")
    @classmethod
    def normalize_tags(cls, value: list[str]) -> list[str]:
        """Normalize repository topics stored as workspace tags."""
        return _normalize_tags(value)


class WorkspaceUpdate(BaseModel):
    """Optimistic-concurrency update for a workspace repository."""

    base_commit: str = Field(min_length=7, max_length=64)
    workspace: dict[str, Any]
    display_name: str | None = Field(default=None, min_length=1, max_length=120)
    description: str | None = Field(default=None, max_length=1000)
    tags: list[str] | None = Field(default=None, max_length=20)
    message: str = Field(default="Save workspace", min_length=1, max_length=200)

    @field_validator("tags")
    @classmethod
    def normalize_optional_tags(cls, value: list[str] | None) -> list[str] | None:
        """Normalize tags when supplied."""
        if value is None:
            return None
        return _normalize_tags(value)


class WorkspaceSummary(BaseModel):
    """Workspace list item projected from a GitHub repository."""

    owner: str
    slug: str
    display_name: str
    description: str = ""
    tags: list[str] = Field(default_factory=list)
    private: bool
    archived: bool = False
    updated_at: str
    head_commit: str
    repository_url: str
    permission: Literal["read", "write", "admin"] = "read"
    neurohub_uri: str


class WorkspaceResponse(WorkspaceSummary):
    """A workspace plus its current document payload."""

    workspace: dict[str, Any]
    manifest: NeurohubWorkspaceManifest


class WorkspaceConflict(BaseModel):
    """Stable conflict details returned for a stale workspace save."""

    code: Literal["workspace_conflict"] = "workspace_conflict"
    message: str = "The workspace changed in Neurohub after you opened it."
    base_commit: str
    remote_commit: str
    recovery: list[Literal["reload", "save_copy", "resolve"]] = Field(
        default_factory=_conflict_recovery
    )


class CollaboratorUpdate(BaseModel):
    """Requested GitHub collaborator permission."""

    permission: Literal["read", "write", "admin"] = "write"


class WorkspaceVisibilityUpdate(BaseModel):
    """Explicit visibility change for a workspace."""

    public: bool
