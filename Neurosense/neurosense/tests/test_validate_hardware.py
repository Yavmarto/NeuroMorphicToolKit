from __future__ import annotations

import importlib
from pathlib import Path
from typing import Any, cast
from unittest.mock import patch

import pytest

import neurosense.app.services.replay_service as replay_module
from neurosense.tests.validate_hardware import run_validation

h5py = cast(Any, importlib.import_module("h5py"))


@pytest.mark.anyio
async def test_mock_validation_flow_creates_replayable_artifact(tmp_path: Path) -> None:
    recordings_dir = tmp_path / "recordings"

    report = await run_validation(
        mock=True,
        recordings_dir=recordings_dir,
    )

    assert report.passed is True
    assert report.artifact_path is not None
    assert [check.name for check in report.checks] == [
        "discover target",
        "connect",
        "capture samples",
        "record artifact",
        "replay artifact",
        "disconnect",
    ]

    artifact_path = Path(report.artifact_path)
    assert artifact_path.exists()

    with h5py.File(artifact_path, "r") as artifact:
        assert artifact.attrs["device_type"] == "cyton"
        assert artifact.attrs["signal_type"] == "emg"
        assert artifact.attrs["preset_id"] == "emg_prosthetic"
        assert artifact.attrs["support_level"] == "experimental"
        assert "raw" in artifact
        assert "filtered" in artifact
        assert "timestamps" in artifact


@pytest.mark.anyio
async def test_mock_validation_replay_consumes_recorded_session(tmp_path: Path) -> None:
    recordings_dir = tmp_path / "recordings"

    report = await run_validation(
        mock=True,
        recordings_dir=recordings_dir,
    )

    assert report.artifact_path is not None
    session_id = Path(report.artifact_path).stem

    with patch("neurosense.app.services.replay_service._RECORDINGS_DIR", recordings_dir):
        result = await replay_module.replay_service.start(session_id)
        chunk = None
        async for replay_chunk in replay_module.replay_service.stream_chunks(chunk_samples=25):
            chunk = replay_chunk
            break

    assert result["status"] == "replaying"
    assert chunk is not None
    assert chunk.shape[0] == 2
    assert chunk.shape[1] > 0
