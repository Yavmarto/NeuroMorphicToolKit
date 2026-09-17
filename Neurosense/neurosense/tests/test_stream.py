from __future__ import annotations

import asyncio
from collections.abc import Generator

import pytest
from fastapi.testclient import TestClient

from neurosense.app.main import app
from neurosense.app.schemas.encoding import build_encoding_config
from neurosense.app.schemas.presets import FilterConfig
from neurosense.app.services.device_manager import device_manager
from neurosense.tests.mock_device import MockBoardShim

client = TestClient(app)


@pytest.fixture(autouse=True)
def setup_mock_device() -> Generator[None, None, None]:
    device_manager.set_mock_board_shim(MockBoardShim)
    yield
    device_manager.set_mock_board_shim(None)


@pytest.fixture
def api_key_headers() -> dict[str, str]:
    return {"X-API-Key": "test-secret"}


def test_stream_raw_no_device(api_key_headers: dict[str, str]) -> None:
    # Ensure no device is connected
    from starlette.websockets import WebSocketDisconnect

    # make sure no device is connected
    for dev in device_manager.active_connections:
        asyncio.run(device_manager.disconnect(dev.id))

    try:
        with client.websocket_connect(
            "/api/neurosense/stream/raw?api_key=test-secret"
        ) as websocket:
            _ = websocket.receive_json()
        raise AssertionError("WebSocket connection should have been disconnected.")
    except WebSocketDisconnect as e:
        assert e.code == 4001


def test_stream_raw_with_device() -> None:
    # Setup connection
    devices = asyncio.run(device_manager.scan_devices())
    device_id = devices[0].id
    asyncio.run(device_manager.connect(device_id, allow_experimental=True))

    try:
        with client.websocket_connect(
            f"/api/neurosense/stream/raw?device_id={device_id}&batch_ms=10&api_key=test-secret"
        ) as websocket:
            # Receive a couple of messages
            msg1 = websocket.receive_json()
            assert "timestamp" in msg1
            assert "channels" in msg1
            assert "sampling_rate_hz" in msg1

            msg2 = websocket.receive_json()
            assert "timestamp" in msg2
            assert "channels" in msg2
    finally:
        asyncio.run(device_manager.disconnect(device_id))


def test_stream_spikes_with_device() -> None:
    from neurosense.app.services.filter_pipeline import filter_pipeline
    from neurosense.app.services.spike_encoder import spike_encoder

    devices = asyncio.run(device_manager.scan_devices())
    device_id = devices[0].id
    asyncio.run(device_manager.connect(device_id, allow_experimental=True))

    # Configure filter and encoder
    f_config = FilterConfig(
        bandpass_low_hz=1.0, bandpass_high_hz=40.0, notch_hz=None, artifact_rejection=False
    )
    filter_pipeline.configure(f_config, 250.0)

    e_config = build_encoding_config("delta", delta_threshold=1.0)
    spike_encoder.configure(e_config, 250.0)

    try:
        with client.websocket_connect(
            f"/api/neurosense/stream/spikes?device_id={device_id}&batch_ms=10&api_key=test-secret"
        ) as websocket:
            # Receive a couple of messages
            msg1 = websocket.receive_json()
            assert "timestamp" in msg1
            assert "spike_trains" in msg1

            msg2 = websocket.receive_json()
            assert "timestamp" in msg2
    finally:
        asyncio.run(device_manager.disconnect(device_id))
