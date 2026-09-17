"""Contract tests for GitHub-backed Neurohub workspaces."""

from __future__ import annotations

import pytest
from pydantic import ValidationError

from neurohub.contracts.workspace_contracts import (
    NeurohubWorkspaceManifest,
    WorkspaceCreate,
    WorkspacePayloadRef,
)

_DIGEST = "a" * 64


def test_manifest_round_trip_is_stable() -> None:
    """A persisted manifest can be parsed without losing fields."""
    manifest = NeurohubWorkspaceManifest(
        slug="mnist-akida",
        display_name="MNIST Akida",
        tags=["MNIST", "akida", "mnist"],
        payload=WorkspacePayloadRef(sha256=_DIGEST),
        nmtk={"source_module": "neurocnl"},
    )
    restored = NeurohubWorkspaceManifest.model_validate_json(manifest.model_dump_json())
    assert restored == manifest
    assert restored.tags == ["mnist", "akida"]


@pytest.mark.parametrize("slug", ["Uppercase", "-leading", "has space", "a" * 65])
def test_workspace_slug_rejects_unsafe_repository_names(slug: str) -> None:
    """Unsafe or unstable repository slugs are rejected at the API boundary."""
    with pytest.raises(ValidationError, match="slug must be"):
        WorkspaceCreate(slug=slug, display_name="Demo", workspace={})


@pytest.mark.parametrize("path", ["/absolute.json", "../outside.json", ".neurohub/other.json"])
def test_payload_path_cannot_escape_or_overwrite_metadata(path: str) -> None:
    """Payload paths cannot escape the repository or replace its manifest."""
    with pytest.raises(ValidationError, match="payload path"):
        WorkspacePayloadRef(path=path, sha256=_DIGEST)


def test_manifest_rejects_unknown_fields() -> None:
    """Schema drift fails explicitly instead of silently dropping metadata."""
    with pytest.raises(ValidationError, match="Extra inputs"):
        NeurohubWorkspaceManifest.model_validate(
            {
                "slug": "demo",
                "display_name": "Demo",
                "payload": {"sha256": _DIGEST},
                "unexpected": True,
            }
        )
