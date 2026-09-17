"""Versioned Neurochip wheel artifacts used by Akida host provisioning."""

from __future__ import annotations

import argparse
import hashlib
import json
import zipfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any

ARTIFACT_MANIFEST_FILENAME = "artifact-manifest.json"


@dataclass(frozen=True)
class NeurochipRuntimeArtifact:
    """A verified Neurochip wheel bundled with launcher-control."""

    wheel_path: Path
    version: str
    sha256: str

    def to_manifest(self) -> dict[str, str]:
        """Return the stable JSON representation shipped in release images."""
        return {
            "schemaVersion": "NeurochipRuntimeArtifactV1",
            "wheelFilename": self.wheel_path.name,
            "version": self.version,
            "sha256": self.sha256,
        }


def _wheel_distribution_version(wheel_path: Path) -> str:
    with zipfile.ZipFile(wheel_path) as wheel:
        metadata_names = [
            name for name in wheel.namelist() if name.endswith(".dist-info/METADATA")
        ]
        if len(metadata_names) != 1:
            raise RuntimeError(
                f"Neurochip wheel must contain exactly one METADATA file: {wheel_path.name}"
            )
        metadata = wheel.read(metadata_names[0]).decode("utf-8")
    for line in metadata.splitlines():
        if line.startswith("Version:"):
            version = line.partition(":")[2].strip()
            if version:
                return version
    raise RuntimeError(f"Neurochip wheel has no package version: {wheel_path.name}")


def inspect_neurochip_runtime_artifact(wheel_path: Path) -> NeurochipRuntimeArtifact:
    """Inspect and checksum one Neurochip wheel."""
    resolved = wheel_path.resolve()
    if not resolved.is_file() or resolved.suffix != ".whl":
        raise RuntimeError(f"Neurochip runtime artifact is not a wheel: {resolved}")
    digest = hashlib.sha256(resolved.read_bytes()).hexdigest()
    return NeurochipRuntimeArtifact(
        wheel_path=resolved,
        version=_wheel_distribution_version(resolved),
        sha256=digest,
    )


def discover_neurochip_runtime_artifact(
    artifact_directory: Path,
) -> NeurochipRuntimeArtifact:
    """Load the single verified Neurochip wheel from an artifact directory."""
    directory = artifact_directory.resolve()
    wheels = sorted(directory.glob("neurochip-*.whl"))
    if len(wheels) != 1:
        raise RuntimeError(
            f"Expected one bundled Neurochip wheel in {directory}, found {len(wheels)}"
        )
    artifact = inspect_neurochip_runtime_artifact(wheels[0])
    manifest_path = directory / ARTIFACT_MANIFEST_FILENAME
    if not manifest_path.is_file():
        raise RuntimeError("Neurochip artifact manifest is missing")
    try:
        manifest: Any = json.loads(manifest_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise RuntimeError("Neurochip artifact manifest is invalid JSON") from exc
    if not isinstance(manifest, dict) or manifest != artifact.to_manifest():
        raise RuntimeError("Neurochip artifact manifest does not match its wheel")
    return artifact


def write_neurochip_runtime_artifact_manifest(artifact_directory: Path) -> Path:
    """Inspect a built wheel and write its checksummed release manifest."""
    directory = artifact_directory.resolve()
    wheels = sorted(directory.glob("neurochip-*.whl"))
    if len(wheels) != 1:
        raise RuntimeError(
            f"Expected one bundled Neurochip wheel in {directory}, found {len(wheels)}"
        )
    artifact = inspect_neurochip_runtime_artifact(wheels[0])
    output_path = directory / ARTIFACT_MANIFEST_FILENAME
    output_path.write_text(
        json.dumps(artifact.to_manifest(), indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return output_path


def main() -> int:
    """Write an artifact manifest for Docker release builds."""
    parser = argparse.ArgumentParser()
    parser.add_argument("artifact_directory", type=Path)
    args = parser.parse_args()
    write_neurochip_runtime_artifact_manifest(args.artifact_directory)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
