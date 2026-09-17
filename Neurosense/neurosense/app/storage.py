"""Durable storage locations owned by NeuroSense."""

from __future__ import annotations

import os
from pathlib import Path


def default_recordings_dir() -> Path:
    """Resolve recording storage with the legacy module override first."""
    explicit = os.getenv("NEUROSENSE_RECORDINGS_DIR", "").strip()
    if explicit:
        return Path(explicit).expanduser()
    data_root = os.getenv("NMTK_DATA_DIR", "").strip()
    if data_root:
        return Path(data_root).expanduser() / "neurosense" / "recordings"
    return Path("recordings")
