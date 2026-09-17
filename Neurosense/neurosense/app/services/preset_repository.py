"""Filesystem repository for built-in and user-created acquisition presets."""

from __future__ import annotations

import json
import logging
import os
import tempfile
from pathlib import Path
from typing import Any

from neurosense.app.schemas.presets import AcquisitionPreset

LOGGER = logging.getLogger(__name__)


def default_custom_presets_dir(builtin_presets_dir: Path) -> Path:
    """Resolve custom preset storage with compatibility overrides first."""
    explicit = os.getenv("NEUROSENSE_CUSTOM_PRESETS_DIR", "").strip()
    if explicit:
        return Path(explicit).expanduser()
    data_root = os.getenv("NMTK_DATA_DIR", "").strip()
    if data_root:
        return Path(data_root).expanduser() / "neurosense" / "presets" / "custom"
    return builtin_presets_dir / "custom"


def load_preset(path: Path) -> AcquisitionPreset:
    """Load and validate one preset document."""
    data = json.loads(path.read_text(encoding="utf-8"))
    channel_mapping = data.get("channel_mapping")
    if isinstance(channel_mapping, dict):
        data["channel_mapping"] = {
            int(channel): label for channel, label in channel_mapping.items()
        }
    return AcquisitionPreset.model_validate(data)


def load_all_presets(
    builtin_presets_dir: Path,
    custom_presets_dir: Path,
) -> list[AcquisitionPreset]:
    """Load valid built-in and custom presets in deterministic order."""
    presets: list[AcquisitionPreset] = []
    for directory, kind in (
        (builtin_presets_dir, "built-in"),
        (custom_presets_dir, "custom"),
    ):
        if not directory.is_dir():
            continue
        for path in sorted(directory.glob("*.json")):
            try:
                presets.append(load_preset(path))
            except (OSError, ValueError, TypeError) as exc:
                LOGGER.warning(
                    "preset_load_failed kind=%s path=%s error_type=%s",
                    kind,
                    path.name,
                    type(exc).__name__,
                )
    return presets


def save_custom_preset(
    preset: AcquisitionPreset,
    custom_presets_dir: Path,
) -> None:
    """Persist one validated custom preset atomically."""
    safe_id = "".join(
        character for character in preset.id if character.isalnum() or character in ("_", "-")
    )
    if not safe_id or safe_id != preset.id:
        raise ValueError("Invalid preset ID.")

    custom_presets_dir.mkdir(parents=True, exist_ok=True)
    destination = custom_presets_dir / f"{safe_id}.json"
    data: dict[str, Any] = preset.model_dump()
    data["channel_mapping"] = {
        str(channel): label for channel, label in preset.channel_mapping.items()
    }
    serialized = json.dumps(data, indent=2)

    temporary_path: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            dir=custom_presets_dir,
            prefix=f".{safe_id}.",
            suffix=".tmp",
            delete=False,
        ) as temporary:
            temporary.write(serialized)
            temporary.flush()
            os.fsync(temporary.fileno())
            temporary_path = Path(temporary.name)
        temporary_path.replace(destination)
    finally:
        if temporary_path is not None and temporary_path.exists():
            temporary_path.unlink()
