"""Tests for NeuroSense durable storage resolution."""

from pathlib import Path

from neurosense.app.storage import default_recordings_dir


def test_recordings_use_owner_directory(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.delenv("NEUROSENSE_RECORDINGS_DIR", raising=False)
    monkeypatch.setenv("NMTK_DATA_DIR", str(tmp_path))

    assert default_recordings_dir() == tmp_path / "neurosense" / "recordings"


def test_recordings_module_override_has_priority(tmp_path: Path, monkeypatch) -> None:
    explicit = tmp_path / "existing-recordings"
    monkeypatch.setenv("NMTK_DATA_DIR", str(tmp_path / "shared"))
    monkeypatch.setenv("NEUROSENSE_RECORDINGS_DIR", str(explicit))

    assert default_recordings_dir() == explicit


def test_recordings_keep_legacy_relative_fallback(monkeypatch) -> None:
    monkeypatch.delenv("NMTK_DATA_DIR", raising=False)
    monkeypatch.delenv("NEUROSENSE_RECORDINGS_DIR", raising=False)

    assert default_recordings_dir() == Path("recordings")
