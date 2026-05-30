"""Configurable filesystem paths for the launcher control service.

All paths default to locations relative to the repository root. Set
``NMTK_STATE_DIR`` or ``NMTK_DATA_DIR`` as environment variables to redirect
them — this is required when running the service in a Docker container where
state must live on a persistent volume rather than inside the image.

Environment variables
---------------------
NMTK_STATE_DIR
    Directory that holds the four JSON state files (module_states,
    launcher_settings, workspace_state, deployment_state).
    Default: ``<repo_root>/nmtk/neuro_toolkit/``

NMTK_DATA_DIR
    Directory that holds deployment secrets and the suite_api venv.
    Default: ``<repo_root>/.nmtk/``

Note
----
These constants are resolved **once at first import**. Set the env vars
before the Python process starts (e.g. in Docker ``ENV`` directives or
``docker compose`` ``environment:`` blocks). Changing them after the
module is already imported has no effect on the cached ``Path`` values.
"""

from __future__ import annotations

import os
from pathlib import Path

# Resolved once at import time so callers get a stable object.
# Tests that need different values should reload this module inside a
# mock.patch.dict(os.environ, ...) block.

REPO_ROOT: Path = Path(__file__).resolve().parents[2]


def _state_dir() -> Path:
    env = os.environ.get("NMTK_STATE_DIR", "").strip()
    return Path(env) if env else REPO_ROOT / "nmtk" / "neuro_toolkit"


def _data_dir() -> Path:
    env = os.environ.get("NMTK_DATA_DIR", "").strip()
    return Path(env) if env else REPO_ROOT / ".nmtk"


# ── Paths resolved from env vars ──────────────────────────────────────────────

STATE_FILE: Path = _state_dir() / "module_states.json"
SETTINGS_FILE: Path = _state_dir() / "launcher_settings.json"
WORKSPACE_FILE: Path = _state_dir() / "workspace_state.json"
DEPLOYMENT_STATE_FILE: Path = _state_dir() / "deployment_state.json"

DEPLOYMENT_SECRET_FILE: Path = _data_dir() / "deployment_secrets.json"
SUITE_API_ENV_ROOT: Path = _data_dir() / "suite_api_env"

# ── Paths always relative to the repo root (baked into the image) ─────────────

MODULES_MANIFEST: Path = REPO_ROOT / "nmtk" / "neuro_toolkit" / "assets" / "modules.json"
