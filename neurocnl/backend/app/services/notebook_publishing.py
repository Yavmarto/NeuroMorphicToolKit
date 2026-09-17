"""Jupyter workspace publishing and notebook metadata access."""

from __future__ import annotations

import base64
import json
import logging
from datetime import datetime
from pathlib import Path

import httpx
from fastapi import HTTPException


def mirror_generated_files(
    notebook_dir: Path,
    workspace_folder: str,
    notebooks: list[tuple[str, dict]],
    artifacts: dict[str, bytes],
    *,
    logger: logging.Logger,
) -> None:
    """Best-effort local mirror used by the kernel-runner fast path."""
    try:
        mirror_dir = notebook_dir / workspace_folder / "notebooks"
        mirror_dir.mkdir(parents=True, exist_ok=True)
        for filename, notebook in notebooks:
            (mirror_dir / filename).write_text(json.dumps(notebook, indent=2), encoding="utf-8")
        for artifact_name, artifact_bytes in artifacts.items():
            (mirror_dir / artifact_name).write_bytes(artifact_bytes)
    except OSError as exc:
        logger.warning(
            "notebook_execution_mirror_unavailable; notebook remains available "
            "through the Jupyter server: %s",
            exc,
        )


def jupyter_tree_url(public_url: str, workspace_folder: str) -> str:
    """Return an absolute JupyterLab tree URL, or empty for standalone dev."""
    if not public_url:
        return ""
    return f"{public_url}/tree/{workspace_folder}/"


def publish_via_contents_api(
    worker_url: str,
    workspace_folder: str,
    files: list[tuple[str, dict]],
    artifacts: dict[str, bytes] | None = None,
) -> None:
    """Write notebooks and artifacts through the Jupyter Contents API."""
    try:
        with httpx.Client(timeout=30.0) as client:

            def put(path: str, payload: dict) -> httpx.Response:
                return client.put(f"{worker_url}/api/contents/{path}", json=payload)

            for directory in (workspace_folder, f"{workspace_folder}/notebooks"):
                response = put(directory, {"type": "directory"})
                if response.status_code not in (200, 201):
                    raise HTTPException(
                        status_code=502,
                        detail=(
                            f"Jupyter rejected creating folder '{directory}' "
                            f"(HTTP {response.status_code}). Check the jupyter-server logs."
                        ),
                    )
            for filename, notebook in files:
                path = f"{workspace_folder}/notebooks/{filename}"
                response = put(
                    path,
                    {"type": "notebook", "format": "json", "content": notebook},
                )
                if response.status_code not in (200, 201):
                    raise HTTPException(
                        status_code=502,
                        detail=(
                            f"Jupyter rejected writing notebook '{filename}' "
                            f"(HTTP {response.status_code}). Check the jupyter-server logs."
                        ),
                    )
            for artifact_name, artifact_bytes in (artifacts or {}).items():
                path = f"{workspace_folder}/notebooks/{artifact_name}"
                response = put(
                    path,
                    {
                        "type": "file",
                        "format": "base64",
                        "content": base64.b64encode(artifact_bytes).decode(),
                    },
                )
                if response.status_code not in (200, 201):
                    raise HTTPException(
                        status_code=502,
                        detail=(
                            f"Jupyter rejected writing artifact '{artifact_name}' "
                            f"(HTTP {response.status_code}). Check the jupyter-server logs."
                        ),
                    )
    except (httpx.ReadTimeout, httpx.WriteTimeout, httpx.PoolTimeout) as exc:
        raise HTTPException(
            status_code=503,
            detail=(
                "Jupyter did not respond within 30s while saving notebooks. "
                "The server is reachable but overloaded — retry, or check the "
                "jupyter-server logs."
            ),
        ) from exc
    except httpx.HTTPError as exc:
        raise HTTPException(
            status_code=503,
            detail=(
                "Could not reach the Jupyter server to save notebooks. "
                "Make sure the jupyter-server service is running, then retry."
            ),
        ) from exc


def fetch_notebook_last_modified(worker_url: str, relative_path: str) -> float | None:
    """Read one notebook's last-modified epoch from Jupyter, if available."""
    try:
        with httpx.Client(timeout=10.0) as client:
            response = client.get(f"{worker_url}/api/contents/{relative_path}")
    except httpx.HTTPError:
        return None
    if response.status_code != 200:
        return None
    last_modified = response.json().get("last_modified")
    if not isinstance(last_modified, str):
        return None
    try:
        return datetime.fromisoformat(last_modified.replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None
