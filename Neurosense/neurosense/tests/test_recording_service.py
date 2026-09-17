from __future__ import annotations

import importlib
from pathlib import Path
from typing import Any, cast
from unittest.mock import patch

import numpy as np
import pytest

from neurosense.app.schemas.encoding import EncodingConfig
from neurosense.app.services.recording_service import RecordingService

h5py = cast(Any, importlib.import_module("h5py"))


@pytest.mark.anyio
async def test_recording_lifecycle_writes_canonical_artifact(
    tmp_path: Path, rate_encoding_config: EncodingConfig
) -> None:
    service = RecordingService()
    recordings_dir = tmp_path / "recordings"
    rng = np.random.default_rng(7)

    with patch("neurosense.app.services.recording_service._RECORDINGS_DIR", recordings_dir):
        result = await service.start(
            device_type="synthetic",
            preset_id="emg_prosthetic",
            channels=2,
            sampling_rate_hz=200,
            encoding_config=rate_encoding_config,
            signal_type="emg",
            channel_labels=["flexor", "extensor"],
            hardware_provenance={"board_family": "BrainFlow Synthetic Board"},
        )

        service.append_raw(rng.random((2, 100)))
        service.append_filtered(rng.random((2, 100)))
        service.append_spikes(
            {
                "method": "rate",
                "spike_trains": [[0.01, 0.03], [0.02]],
                "spike_counts": [2, 1],
            }
        )
        marker = await service.insert_marker("wrist_flexion")
        session = await service.stop()

    artifact_path = recordings_dir / f"{result['session_id']}.hdf5"

    assert session.id == result["session_id"]
    assert session.signal_type == "emg"
    assert session.capture_mode == "synthetic"
    assert session.support_level == "validated"
    assert session.channel_labels == ["flexor", "extensor"]
    assert marker.label == "wrist_flexion"

    with h5py.File(artifact_path, "r") as artifact:
        assert artifact.attrs["artifact_schema_version"] == "1.0"
        assert artifact.attrs["workflow_id"] == "forearm_emg_record_replay"
        assert artifact.attrs["signal_type"] == "emg"
        assert artifact.attrs["capture_mode"] == "synthetic"
        assert artifact.attrs["support_level"] == "validated"
        assert "raw" in artifact
        assert "filtered" in artifact
        assert "timestamps" in artifact
        assert "markers" in artifact
        assert "spikes" in artifact
        assert artifact["raw"].shape == (2, 100)
        assert artifact["filtered"].shape == (2, 100)
        assert artifact["timestamps"].shape == (100,)
        assert artifact["markers"]["timestamps"].shape == (1,)
        assert artifact["markers"]["labels"][0].decode("utf-8") == "wrist_flexion"
        assert artifact["spikes"]["batch_0"].attrs["method"] == "rate"


@pytest.mark.anyio
async def test_recording_already_active(rate_encoding_config: EncodingConfig) -> None:
    service = RecordingService()
    await service.start("ganglion", "test", 4, 200, rate_encoding_config)

    with pytest.raises(RuntimeError, match="A recording is already active"):
        await service.start("ganglion", "test", 4, 200, rate_encoding_config)


@pytest.mark.anyio
async def test_stop_no_active_recording() -> None:
    service = RecordingService()
    with pytest.raises(RuntimeError, match="No active recording to stop"):
        await service.stop()


@pytest.mark.anyio
async def test_insert_marker_no_active_recording() -> None:
    service = RecordingService()
    with pytest.raises(RuntimeError, match="No active recording"):
        await service.insert_marker("test")


def test_append_data(rate_encoding_config: EncodingConfig) -> None:
    service = RecordingService()
    rng = np.random.default_rng()
    service.append_raw(rng.random((4, 100)))
    assert len(service._raw_buffer) == 0

    service._active = True
    service.append_raw(rng.random((4, 100)))
    assert len(service._raw_buffer) == 1
