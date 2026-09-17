from __future__ import annotations

import json
import tempfile
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

from fastapi.testclient import TestClient

import neurosense.app.routers.presets as presets_module
import neurosense.app.routers.sessions as sessions_module
from neurosense.app.main import app

client = TestClient(app)


def test_read_root() -> None:
    response = client.get("/")
    assert response.status_code == 200
    # The frontend static files might not be built in tests, so it returns JSON {"message": "Neurosense Backend is running"}
    if "application/json" in response.headers["content-type"]:
        assert response.json()["message"] in [
            "Neurosense Backend is running",
            "Welcome to NeuroSense API",
        ]
    else:
        assert "text/html" in response.headers["content-type"]


def test_devices_route() -> None:
    response = client.get("/api/neurosense/devices")
    assert response.status_code == 200
    devices = response.json()
    assert isinstance(devices, list)


def test_connect_device_route_accepts_serial_port_body() -> None:
    with patch("neurosense.app.routers.devices.device_manager.connect") as mock_connect:
        mock_connect.return_value = SimpleNamespace(
            support_level="validated",
            model_dump=lambda: {
                "id": "cyton_primary",
                "name": "OpenBCI Cyton",
                "type": "cyton",
                "serial_port": "/dev/cu.usbserial-test",
                "channels": 8,
                "sampling_rate_hz": 250,
                "connected": True,
                "battery_pct": None,
            },
        )

        response = client.post(
            "/api/neurosense/devices/cyton_primary/connect",
            json={"serial_port": "/dev/cu.usbserial-test"},
            headers={"X-API-Key": "test-secret"},
        )

        assert response.status_code == 200
        mock_connect.assert_called_once_with(
            "cyton_primary",
            serial_port="/dev/cu.usbserial-test",
            allow_experimental=False,
        )


def test_presets_route() -> None:
    response = client.get("/api/neurosense/presets")
    assert response.status_code == 200
    presets = response.json()
    assert isinstance(presets, list)


def test_preset_id_route() -> None:
    with tempfile.TemporaryDirectory() as tmpdir:
        mock_dir = Path(tmpdir)
        mock_file = mock_dir / "mock_preset.json"

        mock_preset = {
            "id": "mock_preset",
            "name": "Mock Preset",
            "signal_type": "emg",
            "description": "desc",
            "electrode_placement": "place",
            "electrode_diagram": "path/img.png",
            "channel_mapping": {"0": "test"},
            "filter_config": {"artifact_rejection": False},
            "encoding_config": {"method": "rate", "rate_max_hz": 500.0},
            "recommended_device": "ganglion",
        }
        with mock_file.open("w", encoding="utf-8") as f:
            json.dump(mock_preset, f)

        with patch.object(presets_module, "_PRESETS_DIR", mock_dir):
            response = client.get("/api/neurosense/presets/mock_preset")
            assert response.status_code == 200
            data = response.json()
            assert data["id"] == "mock_preset"
            assert data["name"] == "Mock Preset"


def test_sessions_id_route(canonical_session_id: str, session_fixture_dir: Path) -> None:
    with patch.object(sessions_module, "_RECORDINGS_DIR", session_fixture_dir):
        response = client.get(f"/api/neurosense/sessions/{canonical_session_id}")
        assert response.status_code == 200
        data = response.json()
        assert data["id"] == canonical_session_id
        assert data["device_type"] == "cyton"
        assert data["artifact_schema_version"] == "1.0"
        assert data["signal_type"] == "emg"
        assert data["support_level"] == "experimental"
        assert data["channel_labels"] == ["flexor", "extensor"]
