"""Tests for hardware endpoints: GET /api/prosthetic/hardware/serial, POST connect/disconnect."""

from unittest.mock import patch

from fastapi.testclient import TestClient

from backend.app.main import app

client = TestClient(app)


@patch("backend.app.routers.prosthetic.hardware.list_serial_ports")
def test_list_serial_ports(mock_ports):
    """Happy path: list available serial ports."""
    mock_ports.return_value = ["/dev/ttyUSB0", "/dev/ttyACM0"]
    resp = client.get("/api/prosthetic/hardware/serial")
    assert resp.status_code == 200
    data = resp.json()
    assert data["ports"] == ["/dev/ttyUSB0", "/dev/ttyACM0"]


@patch("backend.app.routers.prosthetic.hardware.list_serial_ports")
def test_list_serial_ports_empty(mock_ports):
    """No serial ports available returns empty list."""
    mock_ports.return_value = []
    resp = client.get("/api/prosthetic/hardware/serial")
    assert resp.status_code == 200
    assert resp.json()["ports"] == []


@patch("backend.app.routers.prosthetic.hardware.connect")
def test_connect_hardware_success(mock_connect):
    """Happy path: successful hardware connection."""
    mock_connect.return_value = True
    resp = client.post(
        "/api/prosthetic/hardware/connect",
        json={"port": "/dev/ttyUSB0", "baud_rate": 115200},
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["status"] == "connected"
    assert data["port"] == "/dev/ttyUSB0"


@patch("backend.app.routers.prosthetic.hardware.connect")
def test_connect_hardware_failure(mock_connect):
    """Failed connection returns 503."""
    mock_connect.return_value = False
    resp = client.post(
        "/api/prosthetic/hardware/connect",
        json={"port": "/dev/ttyUSB0", "baud_rate": 115200},
    )
    assert resp.status_code == 503
    assert "Failed" in resp.json()["detail"]


@patch("backend.app.routers.prosthetic.hardware.disconnect")
def test_disconnect_hardware_success(mock_disconnect):
    """Happy path: successful disconnection."""
    mock_disconnect.return_value = True
    resp = client.post("/api/prosthetic/hardware/disconnect")
    assert resp.status_code == 200
    assert resp.json()["status"] == "disconnected"


@patch("backend.app.routers.prosthetic.hardware.disconnect")
def test_disconnect_no_active_connection(mock_disconnect):
    """Disconnect when not connected returns 400."""
    mock_disconnect.return_value = False
    resp = client.post("/api/prosthetic/hardware/disconnect")
    assert resp.status_code == 400
    assert "No active" in resp.json()["detail"]
