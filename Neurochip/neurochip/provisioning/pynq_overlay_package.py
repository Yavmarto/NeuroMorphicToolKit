"""Validation helpers for host-staged PYNQ overlay packages."""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from ..contracts.pynq_runtime_artifact_contract import PynqOverlayManifestContract

DEFAULT_STAGED_OVERLAY_DIRNAME = "overlay_staging"
DEFAULT_STAGED_OVERLAY_TARGET = "pynq_z2"
DEFAULT_STAGED_OVERLAY_MANIFEST = "overlay_manifest.json"
DEFAULT_STAGED_PYNQ_BITSTREAM_NAME = "snn_overlay.bit"
DEFAULT_STAGED_PYNQ_HWH_NAME = "snn_overlay.hwh"


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


DEFAULT_STAGED_OVERLAY_DIR = (
    _repo_root() / DEFAULT_STAGED_OVERLAY_DIRNAME / DEFAULT_STAGED_OVERLAY_TARGET
)


@dataclass(frozen=True)
class StagedOverlayPackageStatus:
    """Readiness of the host-side staged overlay package."""

    staging_dir: str
    bitstream_path: str
    hwh_path: str
    manifest_path: str
    bitstream_exists: bool
    hwh_exists: bool
    manifest_present: bool
    manifest_valid: bool
    ready: bool
    issues: tuple[str, ...]

    def to_dict(self) -> dict[str, Any]:
        return {
            "stagingDir": self.staging_dir,
            "bitstreamPath": self.bitstream_path,
            "hwhPath": self.hwh_path,
            "manifestPath": self.manifest_path,
            "bitstreamExists": self.bitstream_exists,
            "hwhExists": self.hwh_exists,
            "manifestPresent": self.manifest_present,
            "manifestValid": self.manifest_valid,
            "ready": self.ready,
            "issues": list(self.issues),
        }


def inspect_staged_overlay_package(staging_dir: Path | None = None) -> StagedOverlayPackageStatus:
    """Inspect a host-staged PYNQ overlay package for launcher install."""
    base_dir = (staging_dir or DEFAULT_STAGED_OVERLAY_DIR).resolve()
    bitstream_path = base_dir / DEFAULT_STAGED_PYNQ_BITSTREAM_NAME
    hwh_path = base_dir / DEFAULT_STAGED_PYNQ_HWH_NAME
    manifest_path = base_dir / DEFAULT_STAGED_OVERLAY_MANIFEST

    issues: list[str] = []
    if not base_dir.exists():
        issues.append(f"staged overlay package directory not found at {base_dir}")
    if not bitstream_path.exists():
        issues.append(f"missing staged overlay bitstream at {bitstream_path}")
    if not hwh_path.exists():
        issues.append(f"missing staged overlay hardware handoff file at {hwh_path}")

    manifest_present = manifest_path.exists()
    manifest_valid = True
    if not manifest_present:
        manifest_valid = False
        issues.append(f"missing staged overlay manifest at {manifest_path}")
    else:
        try:
            decoded = json.loads(manifest_path.read_text(encoding="utf-8"))
            PynqOverlayManifestContract.model_validate(decoded)
        except (json.JSONDecodeError, ValueError) as exc:
            manifest_valid = False
            issues.append(f"overlay manifest is invalid: {exc}")

    return StagedOverlayPackageStatus(
        staging_dir=str(base_dir),
        bitstream_path=str(bitstream_path),
        hwh_path=str(hwh_path),
        manifest_path=str(manifest_path),
        bitstream_exists=bitstream_path.exists(),
        hwh_exists=hwh_path.exists(),
        manifest_present=manifest_present,
        manifest_valid=manifest_valid,
        ready=not issues,
        issues=tuple(issues),
    )
