"""Durable storage ownership and compatibility path resolution."""

from __future__ import annotations

import os
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]


def _configured_path(name: str) -> Path | None:
    value = os.environ.get(name, "").strip()
    return Path(value).expanduser() if value else None


def owner_data_dir(
    owner: str,
    *,
    override_env: str,
    legacy_env: str | None = None,
    development_default: Path | None = None,
) -> Path:
    """Resolve one owner's directory without creating or migrating data.

    Owner-specific and legacy overrides win for compatibility. New installs use
    ``NMTK_DATA_DIR/<owner>`` so two modules never silently share a database.
    """
    explicit = _configured_path(override_env)
    if explicit is not None:
        return explicit
    if legacy_env is not None:
        legacy = _configured_path(legacy_env)
        if legacy is not None:
            return legacy
    data_root = _configured_path("NMTK_DATA_DIR")
    if data_root is not None:
        return data_root / owner
    if development_default is not None:
        return development_default
    return REPO_ROOT / ".nmtk-data" / owner


def default_neurohub_db_url() -> str:
    """Return NeuroHub's database URL while preserving explicit legacy paths."""
    explicit_url = os.environ.get("NEUROHUB_DB_URL", "").strip()
    if explicit_url:
        return explicit_url
    directory = owner_data_dir(
        "neurohub",
        override_env="NEUROHUB_DATA_DIR",
        legacy_env="NEUROCNL_DATA_DIR",
        development_default=REPO_ROOT / "Neurohub",
    )
    return f"sqlite:///{directory / 'neurohub.db'}"


def default_neurocnl_data_dir() -> Path:
    """Return NeuroCNL's owned durable directory with legacy compatibility."""
    return owner_data_dir(
        "neurocnl",
        override_env="NEUROCNL_DATA_DIR",
        development_default=Path.home() / ".neurocnl",
    )
