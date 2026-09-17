from __future__ import annotations

from unittest.mock import MagicMock, patch

import numpy as np
import pytest

from neurosense.app.schemas.presets import FilterConfig
from neurosense.app.services.device_manager import DeviceManager
from neurosense.app.services.filter_pipeline import FilterPipeline


@pytest.mark.anyio
async def test_concurrent_pipelines() -> None:
    mock_board = MagicMock()
    mock_board_shim = MagicMock(return_value=mock_board)

    device_manager = DeviceManager()
    device_manager.set_mock_board_shim(mock_board_shim)

    # 1. Connect two devices (AC: 2+ simultaneous streams)
    ganglion = await device_manager.connect("ganglion", allow_experimental=True)
    cyton = await device_manager.connect("cyton", allow_experimental=True)

    assert len(device_manager.active_connections) == 2

    # Verify both are in the boards dict
    assert ganglion.id in device_manager._boards
    assert cyton.id in device_manager._boards

    # 2. Disconnect
    await device_manager.disconnect(ganglion.id)
    await device_manager.disconnect(cyton.id)

    assert len(device_manager.active_connections) == 0


@pytest.mark.anyio
async def test_filter_combinations_valid_output() -> None:
    # AC: Test all filter combinations produce valid output
    pipeline = FilterPipeline()
    sampling_rate = 250.0
    rng = np.random.default_rng()
    # Create some dummy data: 8 channels, 1000 samples (4 seconds)
    # Include some high-frequency noise and a 60Hz hum
    t = np.linspace(0, 4, 1000)
    raw_data = (
        np.sin(2 * np.pi * 10 * t)
        + 0.5 * np.sin(2 * np.pi * 60 * t)
        + 0.1 * rng.standard_normal(1000)
    )
    data = np.tile(raw_data, (8, 1))

    # Test cases for filter combinations
    test_configs = [
        FilterConfig(
            bandpass_low_hz=1.0, bandpass_high_hz=50.0, notch_hz=None, artifact_rejection=False
        ),
        FilterConfig(
            bandpass_low_hz=None, bandpass_high_hz=100.0, notch_hz=60.0, artifact_rejection=False
        ),
        FilterConfig(
            bandpass_low_hz=2.0, bandpass_high_hz=None, notch_hz=50.0, artifact_rejection=True
        ),
        FilterConfig(
            bandpass_low_hz=1.0, bandpass_high_hz=100.0, notch_hz=60.0, artifact_rejection=True
        ),
    ]

    for config in test_configs:
        pipeline.configure(config, sampling_rate)
        filtered = pipeline.apply(data)

        assert filtered.shape == data.shape
        assert not np.any(np.isnan(filtered))
        assert not np.any(np.isinf(filtered))

        # Basic check: filtering should change the data
        assert not np.array_equal(filtered, data)


@pytest.mark.anyio
async def test_full_pipeline_flow() -> None:
    # AC: connect device -> acquire signal -> filter -> display (simulated)
    rng = np.random.default_rng()
    with patch("brainflow.board_shim.BoardShim") as mock_board_shim:
        mock_board = MagicMock()
        # Mock 8 channels of data
        mock_board.get_current_board_data.return_value = rng.random((32, 250))
        mock_board_shim.return_value = mock_board
        mock_board_shim.get_eeg_channels.return_value = list(range(8))

        device_manager = DeviceManager()
        dev = await device_manager.connect("synthetic", allow_experimental=True)

        # 1. Acquire signal
        raw_data_list = await device_manager.get_current_data(dev.id, num_samples=250)
        raw_data = np.array(raw_data_list)
        assert raw_data.shape == (8, 250)

        # 2. Filter
        pipeline = FilterPipeline()
        config = FilterConfig(
            bandpass_low_hz=1.0, bandpass_high_hz=40.0, notch_hz=60.0, artifact_rejection=False
        )
        pipeline.configure(config, 250.0)
        filtered_data = pipeline.apply(raw_data)

        assert filtered_data.shape == (8, 250)

        # 3. "Display" (verify data is ready for serialization/frontend)
        # In the real app, this goes through WebSockets as JSON
        display_data = filtered_data.tolist()
        assert len(display_data) == 8
        assert len(display_data[0]) == 250

        await device_manager.disconnect(dev.id)
