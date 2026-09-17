"""Helpers for loading fixed overlay-v1 manifest files."""

from __future__ import annotations

import json
import os
from pathlib import Path

from ...contracts.pynq_runtime_artifact_contract import (
    DEFAULT_OVERLAY_MANIFEST,
    PynqOverlayManifestContract,
)

PYNQ_OVERLAY_DIR_ENV = "NEUROCHIP_PYNQ_OVERLAY_DIR"
DEFAULT_PYNQ_OVERLAY_DIR = Path(__file__).resolve().parents[2] / "overlays"
DEFAULT_PYNQ_OVERLAY_MANIFEST_NAME = "overlay_manifest.json"


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[3]


def runtime_overlay_dir() -> Path:
    """Resolve the board-local overlay directory for runtime assets."""
    raw = os.getenv(PYNQ_OVERLAY_DIR_ENV, "").strip()
    if raw:
        return Path(raw).expanduser()
    return DEFAULT_PYNQ_OVERLAY_DIR


def runtime_overlay_manifest_path() -> Path:
    """Return the runtime overlay manifest path."""
    return runtime_overlay_dir() / DEFAULT_PYNQ_OVERLAY_MANIFEST_NAME


def design_overlay_manifest_path() -> Path:
    """Return the design-time manifest shipped with the hardware tree."""
    return _repo_root() / "hardware" / "pynq_z2" / DEFAULT_PYNQ_OVERLAY_MANIFEST_NAME


def _load_manifest(path: Path) -> PynqOverlayManifestContract:
    payload = json.loads(path.read_text(encoding="utf-8"))
    return PynqOverlayManifestContract.model_validate(payload)


def load_overlay_manifest_file(path: Path) -> PynqOverlayManifestContract:
    """Load an overlay manifest from an explicit path."""
    return _load_manifest(path)


def load_runtime_overlay_manifest() -> PynqOverlayManifestContract | None:
    """Load the runtime overlay manifest if it exists and is valid."""
    path = runtime_overlay_manifest_path()
    if not path.exists():
        return None
    return _load_manifest(path)


def load_design_overlay_manifest() -> PynqOverlayManifestContract:
    """Load the repo-shipped overlay-v1 manifest, falling back to defaults."""
    path = design_overlay_manifest_path()
    if path.exists():
        return _load_manifest(path)
    return PynqOverlayManifestContract.model_validate(DEFAULT_OVERLAY_MANIFEST)
