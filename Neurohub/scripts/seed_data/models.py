"""Validated shapes for the declarative seed documents in this directory.

Each JSON file here is data, not code — one document per Neurohub asset or
project the seed script creates. These models exist so a malformed document
fails fast and legibly (a `ValidationError` naming the bad field) instead of
producing a 4xx from the live server or a confusing KeyError deep in the
loader.
"""

from __future__ import annotations

from typing import Any, Literal

from pydantic import BaseModel, ConfigDict


class SourceRef(BaseModel):
    """Points at a file under one of the seed script's known source roots."""

    model_config = ConfigDict(extra="forbid")

    root: Literal["cnl_templates", "dream_hand", "benchmarks"]
    file: str


class CnlAssetSeed(BaseModel):
    """A `.cnl` spec file to copy into `shared_assets/cnl_spec/`."""

    model_config = ConfigDict(extra="forbid")

    id: str
    slug: str
    name: str
    description: str
    src: SourceRef
    tags: list[str]
    metadata: dict[str, Any] = {}
    dest_name: str | None = None


class BenchmarkAssetSeed(BaseModel):
    """A benchmark definition JSON file to copy into `shared_assets/benchmark_definition/`."""

    model_config = ConfigDict(extra="forbid")

    id: str
    slug: str
    src: SourceRef
    tags: list[str]


class EncodingPresetSeed(BaseModel):
    """An encoding preset, written inline into `shared_assets/encoding_preset/`."""

    model_config = ConfigDict(extra="forbid")

    id: str
    slug: str
    name: str
    description: str
    filename: str
    tags: list[str]
    data: dict[str, Any]


class StudioWorkspaceSeed(BaseModel):
    """A CNLStudio workspace, written inline into `shared_assets/studio_workspace/`."""

    model_config = ConfigDict(extra="forbid")

    id: str
    slug: str
    name: str
    description: str
    filename: str
    tags: list[str]
    metadata: dict[str, Any] = {}
    data: dict[str, Any]
    """Mirrors `WorkspaceState.toJson()`. May contain the literal sentinel
    `__BRAILLE_DATASET_PATH__` in `selectedDatasetPath`, substituted by the
    loader with the real copied-dataset path (or `None` if unavailable)."""


class ProjectLinksSeed(BaseModel):
    """The `ProjectLinks` a seeded project ships with."""

    model_config = ConfigDict(extra="forbid")

    neurobench_benchmark_ids: list[str] = []
    cnl_spec_slug: str | None = None
    """Resolved to the matching `CnlAssetSeed`'s computed sha256 at seed
    time — the hash isn't knowable until that asset's file is copied."""
    neurochip_deployment_ids: list[str] = []
    neurobench_baseline_ids: list[str] = []
    neurosense_session_ids: list[str] = []


class ProjectSeed(BaseModel):
    """A Neurohub project that links seeded assets together."""

    model_config = ConfigDict(extra="forbid")

    id: str
    name: str
    description: str
    owner: str
    status: str
    tags: list[str]
    links: ProjectLinksSeed
    members: list[str] = []
