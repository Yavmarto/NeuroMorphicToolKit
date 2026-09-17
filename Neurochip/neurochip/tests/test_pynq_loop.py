"""Tests for POST /hardware/pynq/loop/start and /loop/stop.

All tests run without hardware — subprocesses and SSH are mocked.
"""

from __future__ import annotations

from unittest.mock import MagicMock, patch

from fastapi.testclient import TestClient

from neurochip.app.main import app
from neurochip.app.routers import pynq as pynq_router
from neurochip.app.services.pynq_loop_manager import LoopState

client = TestClient(app)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _clear_loop_state() -> None:
    pynq_router._loop_state = None  # noqa: SLF001


# ---------------------------------------------------------------------------
# loop/start — local path
# ---------------------------------------------------------------------------


def test_loop_start_local_returns_pid_and_port() -> None:
    _clear_loop_state()
    mock_proc = MagicMock()
    mock_proc.pid = 12345

    with patch(
        "neurochip.app.services.pynq_loop_manager.subprocess.Popen",
        return_value=mock_proc,
    ):
        resp = client.post("/hardware/pynq/loop/start", json={"zmq_port": 5555})

    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "running"
    assert body["pid"] == 12345
    assert body["zmq_port"] == 5555


def test_loop_start_local_stores_state() -> None:
    _clear_loop_state()
    mock_proc = MagicMock()
    mock_proc.pid = 99

    with patch(
        "neurochip.app.services.pynq_loop_manager.subprocess.Popen",
        return_value=mock_proc,
    ):
        client.post("/hardware/pynq/loop/start", json={"zmq_port": 5600})

    assert pynq_router._loop_state is not None  # noqa: SLF001
    assert pynq_router._loop_state.pid == 99  # noqa: SLF001
    assert pynq_router._loop_state.zmq_port == 5600  # noqa: SLF001


def test_loop_start_module_not_found_returns_502() -> None:
    _clear_loop_state()
    with patch(
        "neurochip.app.services.pynq_loop_manager.subprocess.Popen",
        side_effect=FileNotFoundError("no such file"),
    ):
        resp = client.post("/hardware/pynq/loop/start", json={})

    assert resp.status_code == 502
    assert resp.json()["detail"]["error_code"] == "LOOP_MODULE_NOT_FOUND"


# ---------------------------------------------------------------------------
# loop/start — SSH path
# ---------------------------------------------------------------------------


def test_loop_start_ssh_executes_remote_command() -> None:
    _clear_loop_state()
    mock_result = MagicMock()
    mock_result.returncode = 0
    mock_result.stdout = "54321\n"
    mock_result.stderr = ""

    with patch(
        "neurochip.app.services.pynq_loop_manager.subprocess.run",
        return_value=mock_result,
    ) as mock_run:
        resp = client.post(
            "/hardware/pynq/loop/start",
            json={"ssh_host": "198.51.100.50", "ssh_user": "xilinx", "zmq_port": 5555},
        )

    assert resp.status_code == 200
    body = resp.json()
    assert body["pid"] == 54321
    assert body["status"] == "running"

    # Verify SSH was called with the right host
    call_args = mock_run.call_args[0][0]
    assert "198.51.100.50" in " ".join(call_args)


def test_loop_start_ssh_failure_returns_502() -> None:
    _clear_loop_state()
    mock_result = MagicMock()
    mock_result.returncode = 1
    mock_result.stdout = ""
    mock_result.stderr = "connection refused"

    with patch(
        "neurochip.app.services.pynq_loop_manager.subprocess.run",
        return_value=mock_result,
    ):
        resp = client.post(
            "/hardware/pynq/loop/start",
            json={"ssh_host": "198.51.100.50"},
        )

    assert resp.status_code == 502
    assert resp.json()["detail"]["error_code"] == "LOOP_SSH_FAILED"


# ---------------------------------------------------------------------------
# loop/stop
# ---------------------------------------------------------------------------


def test_loop_stop_when_running_kills_process() -> None:
    pynq_router._loop_state = LoopState(pid=5000, zmq_port=5555)  # noqa: SLF001

    with patch("neurochip.app.services.pynq_loop_manager.os.kill") as mock_kill:
        resp = client.post("/hardware/pynq/loop/stop")

    assert resp.status_code == 200
    assert resp.json()["status"] == "stopped"
    mock_kill.assert_called_once()
    assert pynq_router._loop_state is None  # noqa: SLF001


def test_loop_stop_when_not_running_is_idempotent() -> None:
    _clear_loop_state()
    resp = client.post("/hardware/pynq/loop/stop")
    assert resp.status_code == 200
    assert resp.json()["status"] == "not_running"


def test_loop_stop_ssh_sends_kill_command() -> None:
    pynq_router._loop_state = LoopState(  # noqa: SLF001
        pid=7777,
        zmq_port=5555,
        ssh_host="198.51.100.50",
        ssh_user="xilinx",
    )
    mock_result = MagicMock()
    mock_result.returncode = 0
    mock_result.stdout = ""
    mock_result.stderr = ""

    with patch(
        "neurochip.app.services.pynq_loop_manager.subprocess.run",
        return_value=mock_result,
    ) as mock_run:
        resp = client.post("/hardware/pynq/loop/stop")

    assert resp.status_code == 200
    assert resp.json()["status"] == "stopped"
    call_args = mock_run.call_args[0][0]
    joined = " ".join(call_args)
    assert "198.51.100.50" in joined
    assert "kill 7777" in joined


# ---------------------------------------------------------------------------
# /status includes loop_running
# ---------------------------------------------------------------------------


def test_status_loop_running_false_when_no_loop() -> None:
    _clear_loop_state()
    resp = client.get("/hardware/pynq/status")
    assert resp.status_code == 200
    assert resp.json()["loop_running"] is False


def test_status_loop_running_true_when_loop_alive() -> None:
    pynq_router._loop_state = LoopState(pid=9999, zmq_port=5555)  # noqa: SLF001

    with patch("neurochip.app.routers.pynq.is_loop_alive", return_value=True):
        resp = client.get("/hardware/pynq/status")

    assert resp.status_code == 200
    assert resp.json()["loop_running"] is True

    _clear_loop_state()
