"""Load conventional accelerator manifests and construct backends."""

from __future__ import annotations

import re
from functools import lru_cache

from neurochip.conventional_accelerators.interface import ConventionalAccelerator
from neurochip.conventional_accelerators.manifest import (
    ConventionalAcceleratorManifest,
    load_manifest,
)
from neurochip.conventional_accelerators.paths import conventional_targets_dir

_VALID_ID_RE = re.compile(r"^[A-Za-z0-9_\-]+$")


@lru_cache
def list_manifests() -> tuple[ConventionalAcceleratorManifest, ...]:
    """Return all valid conventional accelerator manifests."""
    targets_dir = conventional_targets_dir()
    manifests: list[ConventionalAcceleratorManifest] = []
    if not targets_dir.exists():
        return tuple(manifests)

    for path in sorted(targets_dir.glob("*.json")):
        manifests.append(load_manifest(path))
    return tuple(manifests)


def get_manifest(accelerator_id: str) -> ConventionalAcceleratorManifest:
    """Load one manifest by id."""
    if not _VALID_ID_RE.match(accelerator_id):
        raise ValueError(f"Invalid accelerator id: {accelerator_id}")

    path = conventional_targets_dir() / f"{accelerator_id}.json"
    if not path.resolve().is_relative_to(conventional_targets_dir().resolve()):
        raise ValueError(f"Invalid accelerator id: {accelerator_id}")
    if not path.exists():
        raise FileNotFoundError(f"Conventional accelerator manifest not found: {accelerator_id}")
    return load_manifest(path)


def get_accelerator(accelerator_id: str) -> ConventionalAccelerator:
    """Construct a backend for ``accelerator_id``."""
    from neurochip.conventional_accelerators.backends.voyager import VoyagerAccelerator

    backends: dict[str, type[ConventionalAccelerator]] = {
        "voyager_axelera": VoyagerAccelerator,
    }
    manifest = get_manifest(accelerator_id)
    backend_cls = backends.get(accelerator_id)
    if backend_cls is None:
        raise NotImplementedError(
            f"No backend registered for {accelerator_id!r}; manifest exists for future spikes."
        )
    return backend_cls(manifest)
