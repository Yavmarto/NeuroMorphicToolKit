"""Tests for /api/targets/{target_id}/reachability endpoint."""

from unittest.mock import AsyncMock, MagicMock, patch

from fastapi.testclient import TestClient

from backend.app.main import app

client = TestClient(app)


def test_simulator_reachable_when_sdk_installed():
    with patch("importlib.util.find_spec", return_value=MagicMock()):
        resp = client.get("/api/targets/snntorch_sim/reachability")
    assert resp.status_code == 200
    assert resp.json()["reachable"] is True


def test_simulator_unreachable_when_sdk_missing():
    with patch("importlib.util.find_spec", return_value=None):
        resp = client.get("/api/targets/snntorch_sim/reachability")
    assert resp.status_code == 200
    data = resp.json()
    assert data["reachable"] is False
    assert "not installed" in data["detail"]


def test_akida_reachable_when_devices_present():
    with (
        patch("importlib.util.find_spec", return_value=MagicMock()),
        patch.dict("sys.modules", {"akida": MagicMock(devices=lambda: [MagicMock()])}),
    ):
        resp = client.get("/api/targets/akida/reachability")
    assert resp.status_code == 200
    assert resp.json()["reachable"] is True


def test_akida_unreachable_when_no_devices():
    with (
        patch("importlib.util.find_spec", return_value=MagicMock()),
        patch.dict("sys.modules", {"akida": MagicMock(devices=lambda: [])}),
    ):
        resp = client.get("/api/targets/akida/reachability")
    assert resp.status_code == 200
    assert resp.json()["reachable"] is False


def test_unknown_target_returns_false():
    resp = client.get("/api/targets/unknown_target/reachability")
    assert resp.status_code == 200
    assert resp.json()["reachable"] is False
    assert "unknown target" in resp.json()["detail"]


def _make_serial_mock(ports: list) -> MagicMock:
    mock_list_ports = MagicMock(comports=lambda: ports)
    mock_tools = MagicMock(list_ports=mock_list_ports)
    mock_serial = MagicMock(tools=mock_tools)
    return mock_serial, mock_tools, mock_list_ports


def test_neurochip_reachable_when_port_found():
    mock_port = MagicMock()
    mock_port.device = "/dev/ttyACM0"
    mock_port.description = "neurochip usb"
    mock_serial, mock_tools, mock_list_ports = _make_serial_mock([mock_port])
    with (
        patch("importlib.util.find_spec", return_value=MagicMock()),
        patch.dict(
            "sys.modules",
            {
                "serial": mock_serial,
                "serial.tools": mock_tools,
                "serial.tools.list_ports": mock_list_ports,
            },
        ),
    ):
        resp = client.get("/api/targets/neurochip/reachability")
    assert resp.status_code == 200
    assert resp.json()["reachable"] is True


def test_neurochip_unreachable_when_no_ports():
    mock_serial, mock_tools, mock_list_ports = _make_serial_mock([])
    with (
        patch("importlib.util.find_spec", return_value=MagicMock()),
        patch.dict(
            "sys.modules",
            {
                "serial": mock_serial,
                "serial.tools": mock_tools,
                "serial.tools.list_ports": mock_list_ports,
            },
        ),
    ):
        resp = client.get("/api/targets/neurochip/reachability")
    assert resp.status_code == 200
    assert resp.json()["reachable"] is False


def test_sc_neurocore_fpga_reachable_when_host_configured(monkeypatch):
    monkeypatch.setenv("SC_NEUROCORE_FPGA_HOST", "198.51.100.10")
    monkeypatch.setenv("SC_NEUROCORE_FPGA_PORT", "22")

    mock_writer = MagicMock()
    mock_writer.wait_closed = AsyncMock()

    async def mock_open_connection(host, port):
        return MagicMock(), mock_writer

    with patch("asyncio.open_connection", side_effect=mock_open_connection):
        resp = client.get("/api/targets/sc_neurocore_fpga/reachability")
    assert resp.status_code == 200
    assert resp.json()["reachable"] is True


def test_sc_neurocore_fpga_unreachable_when_host_not_configured(monkeypatch):
    monkeypatch.delenv("SC_NEUROCORE_FPGA_HOST", raising=False)
    resp = client.get("/api/targets/sc_neurocore_fpga/reachability")
    assert resp.status_code == 200
    assert resp.json()["reachable"] is False
    assert "not configured" in resp.json()["detail"]


def test_lava_hw_unreachable_when_loihi_host_not_configured(monkeypatch):
    monkeypatch.delenv("LOIHI_HOST", raising=False)
    with patch("importlib.util.find_spec", return_value=MagicMock()):
        resp = client.get("/api/targets/lava_loihi2/reachability")
    assert resp.status_code == 200
    assert resp.json()["reachable"] is False
    assert "LOIHI_HOST not configured" in resp.json()["detail"]


def test_lava_hw_unreachable_when_sdk_missing():
    with patch("importlib.util.find_spec", return_value=None):
        resp = client.get("/api/targets/lava_loihi2/reachability")
    assert resp.status_code == 200
    assert resp.json()["reachable"] is False
    assert "not installed" in resp.json()["detail"]
