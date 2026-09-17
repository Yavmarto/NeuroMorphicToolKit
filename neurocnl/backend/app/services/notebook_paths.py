from __future__ import annotations

import json
from pathlib import Path

import httpx

from backend.app.routers.notebook import JUPYTER_WORKER_URL, NOTEBOOK_DIR


def resolve_notebook_path(notebook_path: str) -> Path:
    """Resolve a notebook path returned by generate-v2 to a local filesystem path.

    Order:
    1. Absolute path that exists.
    2. NOTEBOOK_DIR / relative path.
    3. When JUPYTER_WORKER_URL is set, fetch via Contents API into NOTEBOOK_DIR mirror.
    """
    raw = notebook_path.strip()
    if not raw:
        raise FileNotFoundError("No notebook path was provided.")

    candidate = Path(raw)
    if candidate.is_absolute() and candidate.exists():
        return candidate

    local = NOTEBOOK_DIR / raw
    if local.exists():
        return local

    if JUPYTER_WORKER_URL:
        fetched = _fetch_from_jupyter_contents(raw)
        if fetched is not None:
            return fetched

    raise FileNotFoundError(
        f"Notebook not found at '{local}'. "
        "Regenerate the notebook in the Notebook step, then retry. "
        "If this persists, ensure the Jupyter server and backend share the same notebook directory."
    )


def _fetch_from_jupyter_contents(relative_path: str) -> Path | None:
    """Download notebook JSON from Jupyter Contents API and mirror under NOTEBOOK_DIR."""
    url = f"{JUPYTER_WORKER_URL}/api/contents/{relative_path}"
    try:
        with httpx.Client(timeout=30.0) as client:
            resp = client.get(url)
    except httpx.HTTPError:
        return None
    if resp.status_code != 200:
        return None

    payload = resp.json()
    content = payload.get("content")
    if not isinstance(content, dict):
        return None

    dest = NOTEBOOK_DIR / relative_path
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(json.dumps(content, indent=2), encoding="utf-8")
    return dest
