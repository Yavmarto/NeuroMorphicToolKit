"""Manifest reader — single source of truth for NMTK module metadata.

Reads ``nmtk/neuro_toolkit/assets/modules.json`` and exposes typed
``ModuleEntry`` objects.  Every command that needs a module's port,
install path, or uvicorn target must go through this module.
"""

from __future__ import annotations

import json
import os
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


class ManifestNotFoundError(Exception):
    """Raised when modules.json cannot be located."""


_MANIFEST_REL = Path("nmtk") / "neuro_toolkit" / "assets" / "modules.json"


@dataclass
class ModuleEntry:
    id: str
    name: str
    port: int | None
    install_path: str
    uvicorn_target: str
    has_frontend: bool
    required: bool
    install_extras: list[str] = field(default_factory=list)
    health_path: str = "/health"


def _find_manifest_path(start: Path) -> Path:
    """Walk up from *start* until modules.json is found."""
    # Environment variable override
    env_root = os.environ.get("NMTK_ROOT")
    if env_root:
        candidate = Path(env_root) / _MANIFEST_REL
        if candidate.exists():
            return candidate

    # Walk upward
    current = start.resolve()
    for _ in range(20):
        candidate = current / _MANIFEST_REL
        if candidate.exists():
            return candidate
        parent = current.parent
        if parent == current:
            break
        current = parent

    raise ManifestNotFoundError(
        f"Could not find {_MANIFEST_REL} walking up from {start}. "
        "Set NMTK_ROOT to the repository root."
    )


def _entry_from_raw(raw: dict[str, Any]) -> ModuleEntry:
    deployment: dict[str, Any] = raw.get("deployment", {})
    return ModuleEntry(
        id=raw["id"],
        name=raw["name"],
        port=raw.get("port"),
        install_path=raw.get("installPath", ""),
        uvicorn_target=raw.get("uvicornTarget", ""),
        has_frontend=raw.get("hasFrontend", False),
        required=raw.get("required", False),
        install_extras=raw.get("installExtras", []),
        health_path=deployment.get("healthPath", "/health"),
    )


def load_manifest(root: Path) -> list[ModuleEntry]:
    """Load and parse modules.json, returning a list of :class:`ModuleEntry`."""
    path = _find_manifest_path(root)
    raw_list: list[dict[str, Any]] = json.loads(path.read_text())
    # Deduplicate by id (manifest has a duplicate 'version' key per entry — JSON
    # parsers keep the last value, so raw_list is already clean).
    seen: set[str] = set()
    entries: list[ModuleEntry] = []
    for raw in raw_list:
        mid = raw["id"]
        if mid not in seen:
            seen.add(mid)
            entries.append(_entry_from_raw(raw))
    return entries


def find_module(modules: list[ModuleEntry], module_id: str) -> ModuleEntry | None:
    """Return the :class:`ModuleEntry` with the given *module_id*, or None."""
    for m in modules:
        if m.id == module_id:
            return m
    return None
