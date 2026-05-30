"""Tests for neurocli lifecycle commands."""

from __future__ import annotations

import json
from typing import Any
from unittest.mock import MagicMock, patch

from typer.testing import CliRunner

from neurocli.cli import app

runner = CliRunner()


# ---------------------------------------------------------------------------
# status tests
# ---------------------------------------------------------------------------


def _make_mock_response(status_code: int = 200) -> MagicMock:
    m = MagicMock()
    m.status_code = status_code
    return m


def test_status_json_shape() -> None:
    def fake_get(url: str, timeout: float) -> Any:
        if "9000" in url:
            return _make_mock_response(200)
        raise ConnectionError("unreachable")

    with patch("neurocli.lifecycle.httpx.get", side_effect=fake_get):
        result = runner.invoke(app, ["status", "--json"])

    assert result.exit_code == 0, result.output
    data = json.loads(result.output)
    assert "modules" in data
    modules = data["modules"]
    assert isinstance(modules, list)
    assert len(modules) > 0
    # Each entry has required keys
    for m in modules:
        assert "id" in m
        assert "status" in m
        assert m["status"] in {"healthy", "unreachable", "no-port", "unhealthy"}


def test_status_human_output() -> None:
    with patch("neurocli.lifecycle.httpx.get", side_effect=ConnectionError):
        result = runner.invoke(app, ["status"])
    assert result.exit_code == 0
    assert "Module" in result.output


# ---------------------------------------------------------------------------
# install tests
# ---------------------------------------------------------------------------


def test_install_invokes_subprocess_with_correct_args() -> None:
    with (
        patch("neurocli.lifecycle.subprocess.run") as mock_run,
        patch("neurocli.lifecycle.shutil.which", return_value=None),  # force pip
    ):
            result = runner.invoke(app, ["install", "Neurohub"])

    assert result.exit_code == 0, result.output
    mock_run.assert_called_once()
    cmd = mock_run.call_args[0][0]
    assert isinstance(cmd, list)
    assert "install" in cmd
    assert "-e" in cmd
    # path should reference Neurohub install path
    install_arg = cmd[cmd.index("-e") + 1]
    assert "Neurohub" in install_arg


def test_install_unknown_module_exits_1() -> None:
    result = runner.invoke(app, ["install", "does_not_exist", "--json"])
    assert result.exit_code == 1
    data = json.loads(result.output)
    assert data["error"] == "unknown_module"


# ---------------------------------------------------------------------------
# run tests
# ---------------------------------------------------------------------------


def test_run_no_target_exits_1() -> None:
    # neurocnl has uvicornTarget = "" per modules.json
    result = runner.invoke(app, ["run", "neurocnl", "--json"])
    assert result.exit_code == 1
    data = json.loads(result.output)
    assert data["error"] == "no_uvicorn_target"


def test_run_invokes_uvicorn() -> None:
    # lava_backend has no uvicorn target either per current manifest
    # Use a patched module with a real target
    from neurocli import manifest as manifest_mod

    fake_entry = manifest_mod.ModuleEntry(
        id="test_svc",
        name="Test",
        port=9999,
        install_path=".",
        uvicorn_target="test.app:app",
        has_frontend=False,
        required=False,
        install_extras=[],
        health_path="/health",
    )
    with (
        patch("neurocli.lifecycle.load_manifest", return_value=[fake_entry]),
        patch("neurocli.lifecycle.subprocess.run") as mock_run,
    ):
            runner.invoke(app, ["run", "test_svc"])

    mock_run.assert_called_once()
    cmd = mock_run.call_args[0][0]
    assert "uvicorn" in cmd
    assert "test.app:app" in cmd
    assert "9999" in cmd


def test_run_unknown_module_exits_1() -> None:
    result = runner.invoke(app, ["run", "no_such_module", "--json"])
    assert result.exit_code == 1
    data = json.loads(result.output)
    assert data["error"] == "unknown_module"
