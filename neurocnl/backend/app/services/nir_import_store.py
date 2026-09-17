"""Sidecar store for raw .nir bytes uploaded via /api/neurosim/nir/import.

The NIR-to-CNL renderer intentionally drops real tensor weight values, keeping
only shapes (see neurocnl/nir_cnl/renderer.py's `_emit_param_clauses`) so the
CNL text stays compact and editable. That means once a graph round-trips
through CNL, `compile_to_nir()` can only rebuild placeholder weights. This
store keeps the original upload addressable by an opaque `import_id` so a
later notebook-generation request can recover the real values and transplant
them onto the recompiled graph (see notebook.py's `generate_notebook_v2`).
"""

from __future__ import annotations

import os
import re
import uuid
from pathlib import Path

DATA_DIR = Path(os.environ.get("NEUROCNL_DATA_DIR", Path.home() / ".neurocnl"))
NIR_IMPORT_DIR = DATA_DIR / "nir_imports"

# import_id always comes from uuid.uuid4().hex on the write side; validate
# client-supplied ids against this shape before touching the filesystem so a
# malformed/hostile import_id can't be used for path traversal.
_IMPORT_ID_RE = re.compile(r"^[0-9a-f]{32}$")


def save_nir_import(raw_bytes: bytes) -> str:
    """Persist raw .nir bytes and return a fresh opaque import_id to retrieve them by."""
    NIR_IMPORT_DIR.mkdir(parents=True, exist_ok=True)
    import_id = uuid.uuid4().hex
    (NIR_IMPORT_DIR / f"{import_id}.nir").write_bytes(raw_bytes)
    return import_id


def load_nir_import(import_id: str) -> bytes | None:
    """Return the raw .nir bytes for a prior import_id, or None if unknown/invalid/missing."""
    if not _IMPORT_ID_RE.match(import_id):
        return None
    path = NIR_IMPORT_DIR / f"{import_id}.nir"
    if not path.is_file():
        return None
    return path.read_bytes()
