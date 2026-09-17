"""Artifact discovery across Jupyter and standalone notebook workspaces."""

from __future__ import annotations

import base64
import binascii
from collections.abc import Callable
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

import httpx
from fastapi import HTTPException


@dataclass(frozen=True)
class WorkspaceArtifact:
    """One file discovered in a Jupyter workspace, newest-wins."""

    filename: str
    content: bytes
    modified_at: float


def discover_workspace_artifact(
    workspace_folder: str,
    *,
    suffix: str,
    max_bytes: int,
    oversize_hint: str,
    missing_hint: str,
    notebook_dir: Path,
    jupyter_worker_url: str,
    slugify: Callable[[str], str],
    name_prefix: str = "",
) -> WorkspaceArtifact:
    """Return the newest matching artifact from either supported storage backend."""
    workspace_root = workspace_folder.removesuffix("/notebooks")
    relative_dir = f"{slugify(workspace_root)}/notebooks"
    candidates: list[WorkspaceArtifact] = []
    skipped: list[str] = []

    def too_big(name: str, size: int) -> str:
        return (
            f"{name}: {size // (1024 * 1024)} MB exceeds the "
            f"{max_bytes // (1024 * 1024)} MB limit; {oversize_hint}"
        )

    if jupyter_worker_url:
        try:
            with httpx.Client(timeout=15.0) as client:
                listing = client.get(f"{jupyter_worker_url}/api/contents/{relative_dir}")
                if listing.status_code != 200:
                    skipped.append(
                        f"Jupyter returned HTTP {listing.status_code} for "
                        f"{relative_dir!r}; the workspace folder may not exist yet."
                    )
                else:
                    for entry in listing.json().get("content", []):
                        name = str(entry.get("name") or "")
                        if not name.endswith(suffix) or not name.startswith(name_prefix):
                            continue
                        modified_text = str(entry.get("last_modified") or "")
                        try:
                            modified = datetime.fromisoformat(
                                modified_text.replace("Z", "+00:00")
                            ).timestamp()
                        except ValueError:
                            modified = 0.0
                        response = client.get(
                            f"{jupyter_worker_url}/api/contents/{relative_dir}/{name}"
                        )
                        if response.status_code != 200:
                            skipped.append(f"{name}: Jupyter returned HTTP {response.status_code}")
                            continue
                        payload = response.json()
                        content = str(payload.get("content") or "")
                        if payload.get("format") != "base64":
                            skipped.append(
                                f"{name}: Jupyter served it as "
                                f"{payload.get('format')!r}, not base64"
                            )
                            continue
                        try:
                            decoded = base64.b64decode("".join(content.split()), validate=True)
                        except (binascii.Error, ValueError) as exc:
                            skipped.append(f"{name}: content is not valid base64 ({exc})")
                            continue
                        if len(decoded) > max_bytes:
                            skipped.append(too_big(name, len(decoded)))
                            continue
                        candidates.append(WorkspaceArtifact(name, decoded, modified))
        except httpx.HTTPError as exc:
            raise HTTPException(
                status_code=503,
                detail="Jupyter is unavailable; choose a file manually or retry.",
            ) from exc
    else:
        local_dir = notebook_dir / relative_dir
        if not local_dir.is_dir():
            skipped.append(f"{local_dir} does not exist.")
        paths = local_dir.glob(f"{name_prefix}*{suffix}") if local_dir.is_dir() else []
        for path in paths:
            size = path.stat().st_size
            if size > max_bytes:
                skipped.append(too_big(path.name, size))
                continue
            candidates.append(WorkspaceArtifact(path.name, path.read_bytes(), path.stat().st_mtime))

    if not candidates:
        detail = f"No {name_prefix}*{suffix} file was found in {relative_dir!r}. {missing_hint}"
        if skipped:
            detail += " Skipped: " + "; ".join(skipped)
        raise HTTPException(status_code=404, detail=detail)
    return max(candidates, key=lambda candidate: candidate.modified_at)
