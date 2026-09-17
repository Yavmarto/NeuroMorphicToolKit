"""Presets router -- list, get, and save acquisition presets."""

import asyncio
from pathlib import Path

from fastapi import APIRouter, HTTPException, Request, Response

from ..schemas.presets import AcquisitionPreset
from ..services.preset_repository import (
    default_custom_presets_dir,
    load_all_presets,
    load_preset,
    save_custom_preset,
)

router = APIRouter()

# Directory containing built-in preset JSON files
_PRESETS_DIR = Path(__file__).resolve().parent.parent.parent / "presets"

# In-memory store for custom presets (persisted as JSON alongside built-ins)
_CUSTOM_PRESETS_DIR = default_custom_presets_dir(_PRESETS_DIR)


def _load_preset_from_file(path: Path) -> AcquisitionPreset:
    """Compatibility facade for loading one preset JSON file."""
    return load_preset(path)


def _load_all_presets() -> list[AcquisitionPreset]:
    """Compatibility facade for loading all presets from disk."""
    return load_all_presets(_PRESETS_DIR, _CUSTOM_PRESETS_DIR)


@router.get("", response_model=list[AcquisitionPreset])
async def get_presets(request: Request, response: Response) -> list[AcquisitionPreset]:
    """List all available acquisition presets.

    Returns both built-in presets (loaded from neurosense/presets/*.json)
    and any user-created custom presets.
    """
    return await asyncio.to_thread(_load_all_presets)


@router.get("/{preset_id}", response_model=AcquisitionPreset)
async def get_preset(request: Request, response: Response, preset_id: str) -> AcquisitionPreset:
    """Get a specific preset by ID.

    Searches built-in presets first, then custom presets.
    """
    all_presets = await asyncio.to_thread(_load_all_presets)
    for preset in all_presets:
        if preset.id == preset_id:
            return preset
    raise HTTPException(status_code=404, detail=f"Preset '{preset_id}' not found.")


@router.post("", response_model=AcquisitionPreset, status_code=201)
async def save_preset(
    request: Request, response: Response, preset: AcquisitionPreset
) -> AcquisitionPreset:
    """Save a custom preset.

    The preset is written to the custom presets directory as a JSON file.
    If a preset with the same ID already exists, it is overwritten.
    """
    try:
        await asyncio.to_thread(save_custom_preset, preset, _CUSTOM_PRESETS_DIR)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail="Invalid preset ID.")
    except OSError as exc:
        raise HTTPException(
            status_code=503,
            detail="Preset storage is temporarily unavailable.",
        ) from exc

    return preset
