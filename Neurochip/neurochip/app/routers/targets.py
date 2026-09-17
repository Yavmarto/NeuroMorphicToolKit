import json
import logging
import os
import re
from pathlib import Path

from fastapi import APIRouter, HTTPException, Request, Response

from neurochip.contracts.hardware_contracts import HardwareProfile

router = APIRouter(prefix="/api/neurochip/targets", tags=["targets"])
logger = logging.getLogger("neurochip.targets")

# Only alphanumerics, hyphens, and underscores are valid target IDs.
_VALID_ID_RE = re.compile(r"^[A-Za-z0-9_\-]+$")


def _get_targets_dir() -> Path:
    current_dir = Path(__file__).resolve().parent
    return (current_dir / ".." / ".." / "targets").resolve()


@router.get("", response_model=list[HardwareProfile])
def list_targets(request: Request, response: Response) -> list[HardwareProfile]:
    targets_dir = _get_targets_dir()
    profiles = []

    if targets_dir.exists():
        for filename in os.listdir(targets_dir):
            if filename.endswith(".json"):
                filepath = targets_dir / filename
                try:
                    with open(filepath) as f:
                        data = json.load(f)
                        profiles.append(HardwareProfile(**data))
                except Exception:
                    logger.warning("Failed to load hardware profile %s", filepath, exc_info=True)

    return profiles


@router.get("/{id}", response_model=HardwareProfile)
def get_target(request: Request, response: Response, id: str) -> HardwareProfile:
    # Reject IDs that contain path separators or other traversal characters.
    if not _VALID_ID_RE.match(id):
        raise HTTPException(status_code=400, detail="Invalid target ID format")

    targets_dir = _get_targets_dir()
    filepath = targets_dir / f"{id}.json"

    # Extra guard: ensure the resolved path stays inside the targets directory.
    if not filepath.resolve().is_relative_to(targets_dir):
        raise HTTPException(status_code=400, detail="Invalid target ID format")

    if not filepath.exists():
        raise HTTPException(status_code=404, detail="Hardware target not found")

    try:
        with open(filepath) as f:
            data = json.load(f)
            return HardwareProfile(**data)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error reading profile: {str(e)}")
