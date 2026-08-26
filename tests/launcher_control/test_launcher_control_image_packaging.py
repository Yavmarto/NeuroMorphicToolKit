"""Regression checks for launcher-control's bundled PYNQ overlay."""

import json
from pathlib import Path

from nmtk.launcher_control.server import _validate_pynq_overlay_manifest


ROOT = Path(__file__).resolve().parents[2]
DOCKERFILE = ROOT / "Dockerfile.control"
OVERLAY_DIRECTORY = ROOT / "Neurochip" / "overlay_staging" / "pynq_z2"
MASTER_MANIFEST = ROOT / "Neurochip" / "hardware" / "pynq_z2" / "overlay_manifest.json"
ARTIFACT_DIRECTORY = "/app/artifacts/neurochip/overlay_staging/pynq_z2"
REQUIRED_OVERLAY_FILES = (
    "snn_overlay.bit",
    "snn_overlay.hwh",
    "overlay_manifest.json",
)


def test_launcher_control_image_build_requires_complete_pynq_overlay() -> None:
    """Keep the release image from omitting files Install Overlay must upload."""
    dockerfile = DOCKERFILE.read_text(encoding="utf-8")

    assert (
        f"COPY Neurochip/overlay_staging/pynq_z2/ {ARTIFACT_DIRECTORY}/" in dockerfile
    )
    for filename in REQUIRED_OVERLAY_FILES:
        assert (OVERLAY_DIRECTORY / filename).is_file()
        assert f"test -s {ARTIFACT_DIRECTORY}/{filename}" in dockerfile


def test_shipped_pynq_overlay_manifest_passes_the_launcher_validator() -> None:
    """The manifest the image carries must be one the launcher will accept.

    Overlay v2 shipped with `register_map.dma_channel` deleted by the offset
    writer. Every fixture in this suite is synthetic and had the key, the build's
    own `--check` did not look for it, and Neurochip's Pydantic model filled it in
    from a default — so the only validator that saw the truth was the launcher's,
    at runtime, on a user's board, reported as "Overlay Missing". This reads the
    real file through the real validator.
    """
    manifest = json.loads(
        (OVERLAY_DIRECTORY / "overlay_manifest.json").read_text(encoding="utf-8")
    )

    _validate_pynq_overlay_manifest(manifest)


def test_staged_pynq_overlay_manifest_matches_the_hardware_master() -> None:
    """`stage_overlay.sh` copies the master; a hand-edit to one must not drift."""
    staged = (OVERLAY_DIRECTORY / "overlay_manifest.json").read_text(encoding="utf-8")

    assert staged == MASTER_MANIFEST.read_text(encoding="utf-8")
