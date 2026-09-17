"""Tests for owner-scoped, atomic preset persistence."""

from __future__ import annotations

import json
from pathlib import Path

from neurosense.app.schemas.presets import AcquisitionPreset
from neurosense.app.services.preset_repository import (
    default_custom_presets_dir,
    load_all_presets,
    save_custom_preset,
)


def _preset(identifier: str = "custom_emg") -> AcquisitionPreset:
    return AcquisitionPreset.model_validate(
        {
            "id": identifier,
            "name": "Custom EMG",
            "signal_type": "emg",
            "description": "Custom preset",
            "electrode_placement": "forearm",
            "electrode_diagram": "forearm.png",
            "channel_mapping": {0: "flexor"},
            "filter_config": {"artifact_rejection": False},
            "encoding_config": {"method": "rate", "rate_max_hz": 500.0},
            "recommended_device": "ganglion",
        }
    )


def test_data_root_owns_custom_presets(
    tmp_path: Path,
    monkeypatch,
) -> None:
    monkeypatch.delenv("NEUROSENSE_CUSTOM_PRESETS_DIR", raising=False)
    monkeypatch.setenv("NMTK_DATA_DIR", str(tmp_path))

    assert default_custom_presets_dir(Path("builtins")) == (
        tmp_path / "neurosense" / "presets" / "custom"
    )


def test_module_override_has_priority(tmp_path: Path, monkeypatch) -> None:
    explicit = tmp_path / "explicit"
    monkeypatch.setenv("NMTK_DATA_DIR", str(tmp_path / "shared"))
    monkeypatch.setenv("NEUROSENSE_CUSTOM_PRESETS_DIR", str(explicit))

    assert default_custom_presets_dir(Path("builtins")) == explicit


def test_save_is_restart_persistent_and_uses_string_channel_keys(
    tmp_path: Path,
) -> None:
    custom_dir = tmp_path / "custom"
    preset = _preset()

    save_custom_preset(preset, custom_dir)

    stored = json.loads((custom_dir / "custom_emg.json").read_text(encoding="utf-8"))
    assert stored["channel_mapping"] == {"0": "flexor"}
    assert load_all_presets(tmp_path / "builtins", custom_dir) == [preset]
    assert not list(custom_dir.glob("*.tmp"))


def test_invalid_identifier_cannot_escape_storage(tmp_path: Path) -> None:
    preset = _preset("../escape")

    try:
        save_custom_preset(preset, tmp_path / "custom")
    except ValueError as exc:
        assert str(exc) == "Invalid preset ID."
    else:
        raise AssertionError("unsafe preset identifier was accepted")

    assert not (tmp_path / "escape.json").exists()
