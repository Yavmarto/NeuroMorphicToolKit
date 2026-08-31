"""Typed PYNQ service boundary and security characterizations."""

from __future__ import annotations

import subprocess
import threading
from pathlib import Path
from unittest import mock

import pytest

from nmtk.launcher_control.pynq_board_repository import PynqBoardRepository
from nmtk.launcher_control.pynq_preflight import evaluate_pynq_preflight
from nmtk.launcher_control.pynq_remote_client import PynqRemoteClient
from nmtk.launcher_control.pynq_status import (
    preflight_board_fields,
    runtime_status_board_fields,
    serialize_pynq_board,
)
from nmtk.launcher_control.state_contracts import LauncherSettingsRecord


def launcher_settings() -> LauncherSettingsRecord:
    """Return the smallest complete persisted settings document."""
    return {
        "logLevel": "info",
        "mujocoAvailable": False,
        "pythonAvailable": True,
        "akidaHosts": [],
        "akidaRuntimeUpdateJobs": [],
        "pynqBoards": [],
        "selectedAkidaHostId": None,
        "selectedPynqBoardId": None,
    }


def test_repository_preserves_password_but_never_serializes_it() -> None:
    settings = launcher_settings()
    persisted: list[bool] = []
    repository = PynqBoardRepository(
        settings=settings,
        lock=threading.RLock(),
        persist=lambda: persisted.append(True),
    )

    created = repository.create(
        {"id": "desk", "host": "192.0.2.10", "password": "board-secret"}
    )

    assert created["hasPassword"] is True
    assert "password" not in created
    assert repository.get("desk")["password"] == "board-secret"
    assert settings["selectedPynqBoardId"] == "desk"
    assert persisted == [True]


@pytest.mark.parametrize(
    ("payload", "expected_state"),
    [
        ({"preflight_status": "ok"}, "ready"),
        ({"preflight_status": "degraded"}, "degraded_optional_capability"),
        ({"preflight_status": "failed"}, "preflight_failed"),
        (
            {
                "preflight_status": "ok",
                "overlay_assets": {"ready_for_hardware": False},
            },
            "overlay_missing",
        ),
    ],
)
def test_preflight_evaluator_preserves_readiness_semantics(
    payload: dict[str, object], expected_state: str
) -> None:
    assert evaluate_pynq_preflight(payload).state == expected_state


def test_status_serializer_preserves_wire_keys_and_redacts_password() -> None:
    board = {
        "id": "desk",
        "host": "192.0.2.10",
        "runtimeApiUrl": "http://stale.invalid:9999",
        "runtimeApiUrlOverride": "",
        "password": "board-secret",
        "state": "ready",
        "lastStatus": {"runtime_mode": "hardware"},
    }

    serialized = serialize_pynq_board(board)

    assert serialized == {
        "id": "desk",
        "host": "192.0.2.10",
        "runtimeApiUrl": "http://192.0.2.10:8002",
        "runtimeApiUrlOverride": "",
        "state": "ready",
        "lastStatus": {"runtime_mode": "hardware"},
        "hasPassword": True,
    }
    assert board["password"] == "board-secret"


def test_preflight_status_fields_have_stable_persisted_casing() -> None:
    fields = preflight_board_fields(
        {
            "preflight_status": "degraded",
            "preflight_message": "Simulator fallback active.",
            "runtime_mode": "simulator",
            "overlay_assets": {
                "ready_for_hardware": False,
                "overlay_version": "2.0.0",
            },
        }
    )

    assert fields == {
        "state": "overlay_missing",
        "lastPreflightStatus": "degraded",
        "lastPreflightMessage": "Simulator fallback active.",
        "lastRuntimeMode": "simulator",
        "overlayVersion": "2.0.0",
    }


def test_runtime_status_fields_preserve_raw_snapshot() -> None:
    status = {"runtime_mode": " hardware ", "loaded_overlay": "snn_overlay_v2"}

    assert runtime_status_board_fields(status) == {
        "lastStatus": status,
        "lastRuntimeMode": "hardware",
    }


def test_sshpass_password_is_environment_only() -> None:
    client = PynqRemoteClient()
    board = {
        "authMode": "password",
        "password": "board-secret",
        "sshPort": 22,
    }
    with mock.patch(
        "nmtk.launcher_control.pynq_remote_client.shutil.which",
        return_value="/usr/bin/sshpass",
    ):
        command, env, cleanup = client.prepare_ssh_invocation(board)

    assert "board-secret" not in command
    assert command[:2] == ["/usr/bin/sshpass", "-e"]
    assert env is not None and env["SSHPASS"] == "board-secret"
    assert cleanup is None


def test_ssh_timeout_kills_process_and_redacts_password() -> None:
    client = PynqRemoteClient()
    board = {
        "id": "desk",
        "displayName": "Desk PYNQ",
        "host": "192.0.2.10",
        "username": "xilinx",
        "authMode": "ssh_key",
        "sshKeyPath": "/tmp/key",
        "password": "board-secret",
    }

    class EmptyStream:
        def readline(self) -> str:
            return ""

        def close(self) -> None:
            return None

    class TimedOutProcess:
        def __init__(self) -> None:
            self.stdout = EmptyStream()
            self.stderr = EmptyStream()
            self.killed = False
            self.wait_count = 0

        def wait(self, timeout: float | None = None) -> int:
            self.wait_count += 1
            if timeout is not None:
                raise subprocess.TimeoutExpired("ssh", timeout)
            return -9

        def kill(self) -> None:
            self.killed = True

    process = TimedOutProcess()
    with mock.patch(
        "nmtk.launcher_control.pynq_remote_client.subprocess.Popen",
        return_value=process,
    ), pytest.raises(RuntimeError, match="timed out") as raised:
        client.run_ssh(board, "echo board-secret", timeout=0.01)

    assert process.killed is True
    assert "board-secret" not in str(raised.value)


def test_internal_components_do_not_import_server() -> None:
    root = Path(__file__).parents[2] / "nmtk" / "launcher_control"
    for filename in (
        "pynq_board_repository.py",
        "pynq_preflight.py",
        "pynq_provisioning.py",
        "pynq_remote_client.py",
        "pynq_runtime_proxy.py",
        "pynq_status.py",
    ):
        source = (root / filename).read_text(encoding="utf-8")
        assert "from .server" not in source
        assert "import server" not in source
