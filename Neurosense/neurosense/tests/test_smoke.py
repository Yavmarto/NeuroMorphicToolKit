from __future__ import annotations

import importlib
import io
import shutil
from collections.abc import Generator
from pathlib import Path
from typing import Any, cast
from unittest.mock import patch

import pytest
from fastapi.testclient import TestClient

from neurosense.app.main import app
from neurosense.app.services.device_manager import device_manager
from neurosense.tests.mock_device import MockBoardShim

h5py = cast(Any, importlib.import_module("h5py"))


@pytest.fixture
def client() -> TestClient:
    return TestClient(app)


@pytest.fixture(autouse=True)
def setup_smoke_env() -> Generator[Path, None, None]:
    # Use a predictable recordings directory within the workspace for CI artifact upload
    rec_dir = Path("recordings_smoke_test")
    if rec_dir.exists():
        shutil.rmtree(rec_dir)
    rec_dir.mkdir(parents=True, exist_ok=True)

    # Patch the recordings directory in both service and router
    with (
        patch("neurosense.app.services.recording_service._RECORDINGS_DIR", rec_dir),
        patch("neurosense.app.routers.export._RECORDINGS_DIR", rec_dir),
    ):
        # Directly set the mock board shim instead of patching the setter
        device_manager.set_mock_board_shim(MockBoardShim)
        yield rec_dir
        device_manager.set_mock_board_shim(None)


def _scan_and_connect(client: TestClient, headers: dict[str, str]) -> str:
    response = client.get("/api/neurosense/devices", headers=headers)
    assert response.status_code == 200
    devices = cast(list[dict[str, Any]], response.json())
    assert len(devices) > 0
    device_id = cast(
        str,
        next((d["id"] for d in devices if d["type"] == "synthetic"), devices[0]["id"]),
    )
    response = client.post(
        f"/api/neurosense/devices/{device_id}/connect?allow_experimental=true",
        headers=headers,
    )
    assert response.status_code == 200
    return device_id


def _start_recording(client: TestClient, headers: dict[str, str]) -> str:
    encoding_config = {
        "method": "rate",
        "rate_max_hz": 500.0,
        "refractory_period": 0.001,
        "temporal_resolution": 0.001,
    }
    start_req = {
        "device_type": "synthetic",
        "preset_id": "smoke_preset",
        "channels": 8,  # Brainflow synthetic board (-1) has 8 EEG channels by default
        "sampling_rate_hz": 250,
        "encoding_config": encoding_config,
    }
    response = client.post("/api/neurosense/recording/start", json=start_req, headers=headers)
    assert response.status_code == 200
    response_json = cast(dict[str, Any], response.json())
    return cast(str, response_json["session_id"])


def _stream_data(client: TestClient, device_id: str, api_key: str) -> None:
    with client.websocket_connect(
        f"/api/neurosense/stream/raw?device_id={device_id}&batch_ms=10&api_key={api_key}"
    ) as websocket:
        for _ in range(5):
            data = websocket.receive_json()
            assert "channels" in data
            assert len(data["channels"]) == 8


def _insert_marker(client: TestClient, headers: dict[str, str]) -> str:
    marker_label = "smoke_test_marker"
    marker_req = {"label": marker_label}
    response = client.post("/api/neurosense/recording/marker", json=marker_req, headers=headers)
    assert response.status_code == 200
    return marker_label


def _stop_recording(client: TestClient, headers: dict[str, str], session_id: str) -> None:
    response = client.post("/api/neurosense/recording/stop", headers=headers)
    assert response.status_code == 200
    session_data = cast(dict[str, Any], response.json())
    assert session_data["id"] == session_id


def _verify_hdf5_file(rec_dir: Path, session_id: str, marker_label: str) -> None:
    session_file = rec_dir / f"{session_id}.hdf5"
    assert session_file.exists()
    with h5py.File(session_file, "r") as f:
        assert f.attrs["session_id"] == session_id
        assert f.attrs["channels"] == 8
        assert "raw" in f
        assert f["raw"].shape[0] == 8
        assert f["raw"].shape[1] > 0
        if "markers" in f:
            labels = [label.decode("utf-8") for label in f["markers/labels"][:]]
            assert marker_label in labels


def _export_and_verify_csv(client: TestClient, headers: dict[str, str], session_id: str) -> None:
    export_req = {"session_id": session_id, "format": "csv"}
    response = client.post("/api/neurosense/export", json=export_req, headers=headers)
    assert response.status_code == 200
    assert response.headers["content-type"] == "text/csv; charset=utf-8"
    csv_content = response.content.decode("utf-8")
    assert "timestamp,channel,spike_time" in csv_content


def _export_and_verify_hdf5(client: TestClient, headers: dict[str, str], session_id: str) -> None:
    export_req = {"session_id": session_id, "format": "hdf5"}
    response = client.post("/api/neurosense/export", json=export_req, headers=headers)
    assert response.status_code == 200
    assert response.headers["content-type"] == "application/x-hdf5"
    with h5py.File(io.BytesIO(response.content), "r") as f:
        assert "raw" in f
        assert f["raw"].shape[0] == 8


def test_smoke_integration(client: TestClient, setup_smoke_env: Path) -> None:
    rec_dir = setup_smoke_env
    api_key = "debug-key"
    headers = {"X-API-Key": api_key}

    device_id = _scan_and_connect(client, headers)

    try:
        session_id = _start_recording(client, headers)
        _stream_data(client, device_id, api_key)
        marker_label = _insert_marker(client, headers)
        _stop_recording(client, headers, session_id)
        _verify_hdf5_file(rec_dir, session_id, marker_label)
        _export_and_verify_csv(client, headers, session_id)
        _export_and_verify_hdf5(client, headers, session_id)
    finally:
        client.post(f"/api/neurosense/devices/{device_id}/disconnect", headers=headers)
