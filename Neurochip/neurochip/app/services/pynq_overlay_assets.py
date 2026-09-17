"""Helpers for resolving and validating canonical PYNQ overlay assets."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from ...contracts.pynq_runtime_artifact_contract import PynqOverlayManifestContract
from .pynq_overlay_manifest import (
    DEFAULT_PYNQ_OVERLAY_DIR as _DEFAULT_PYNQ_OVERLAY_DIR,
)
from .pynq_overlay_manifest import (
    DEFAULT_PYNQ_OVERLAY_MANIFEST_NAME,
    runtime_overlay_dir,
    runtime_overlay_manifest_path,
)

DEFAULT_PYNQ_BITSTREAM_NAME = "snn_overlay.bit"
DEFAULT_PYNQ_OVERLAY_DIR = _DEFAULT_PYNQ_OVERLAY_DIR


@dataclass(frozen=True)
class OverlayAssetStatus:
    """Filesystem readiness of the canonical PYNQ overlay package."""

    requested_bitstream_path: str
    bitstream_path: str
    hwh_path: str
    manifest_path: str
    bitstream_exists: bool
    hwh_exists: bool
    manifest_exists: bool
    manifest_valid: bool
    overlay_id: str | None
    overlay_version: str | None
    ready_for_hardware: bool
    issues: tuple[str, ...]

    def to_dict(self) -> dict[str, object]:
        return {
            "requested_bitstream_path": self.requested_bitstream_path,
            "bitstream_path": self.bitstream_path,
            "hwh_path": self.hwh_path,
            "manifest_path": self.manifest_path,
            "bitstream_exists": self.bitstream_exists,
            "hwh_exists": self.hwh_exists,
            "manifest_exists": self.manifest_exists,
            "manifest_valid": self.manifest_valid,
            "overlay_id": self.overlay_id,
            "overlay_version": self.overlay_version,
            "ready_for_hardware": self.ready_for_hardware,
            "issues": list(self.issues),
        }


def overlay_dir() -> Path:
    """Resolve the active overlay directory for the current process."""
    return runtime_overlay_dir()


def resolve_bitstream_path(bitstream_path: str | None = None) -> Path:
    """Resolve a bitstream path against Neurochip's canonical overlay directory."""
    requested = Path(bitstream_path or DEFAULT_PYNQ_BITSTREAM_NAME)
    if requested.is_absolute():
        return requested
    return overlay_dir() / requested


def inspect_overlay_assets(bitstream_path: str | None = None) -> OverlayAssetStatus:
    """Inspect the bitstream, ``.hwh`` sidecar, and manifest for real-board runs."""
    requested = bitstream_path or DEFAULT_PYNQ_BITSTREAM_NAME
    resolved = resolve_bitstream_path(bitstream_path)
    hwh_path = resolved.with_suffix(".hwh")
    manifest_path = (
        resolved.with_name(DEFAULT_PYNQ_OVERLAY_MANIFEST_NAME)
        if Path(requested).is_absolute()
        else runtime_overlay_manifest_path()
    )

    issues: list[str] = []
    if resolved.suffix != ".bit":
        issues.append(f"bitstream must end with .bit (got {resolved.name})")
    if not resolved.exists():
        issues.append(f"bitstream not found at {resolved}")
    if not hwh_path.exists():
        issues.append(f"hardware handoff file not found at {hwh_path}")

    manifest_exists = manifest_path.exists()
    manifest_valid = True
    manifest: PynqOverlayManifestContract | None = None
    if not manifest_exists:
        manifest_valid = False
        issues.append(f"overlay manifest not found at {manifest_path}")
    else:
        try:
            manifest = PynqOverlayManifestContract.model_validate_json(
                manifest_path.read_text(encoding="utf-8")
            )
        except ValueError as exc:
            manifest_valid = False
            issues.append(f"overlay manifest is invalid: {exc}")

    ready_for_hardware = not issues
    return OverlayAssetStatus(
        requested_bitstream_path=requested,
        bitstream_path=str(resolved),
        hwh_path=str(hwh_path),
        manifest_path=str(manifest_path),
        bitstream_exists=resolved.exists(),
        hwh_exists=hwh_path.exists(),
        manifest_exists=manifest_exists,
        manifest_valid=manifest_valid,
        overlay_id=manifest.overlay_id if manifest is not None else None,
        overlay_version=manifest.overlay_version if manifest is not None else None,
        ready_for_hardware=ready_for_hardware,
        issues=tuple(issues),
    )
