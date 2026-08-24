"""Tests for the consolidated Compose lifecycle commands."""

from __future__ import annotations

import json
from unittest.mock import MagicMock, patch

import httpx
from typer.testing import CliRunner

from neurocli.cli import app

runner = CliRunner()


def _response(payload: dict, status_code: int = 200) -> MagicMock:
    response = MagicMock()
    response.status_code = status_code
    response.json.return_value = payload
    response.raise_for_status.return_value = None
    return response


def test_status_reads_aggregated_suite_health() -> None:
    suite = _response({"status": "ok", "service": "suite_api", "version": "dev"})
    modules = _response({"modules": {"neurocnl": {"status": "online", "response_time_ms": 2.5, "error": None}}})
    with patch("neurocli.lifecycle.httpx.get", side_effect=[suite, modules]) as get:
        result = runner.invoke(app, ["status", "--api-url", "http://suite.test", "--json"])
    assert result.exit_code == 0, result.output
    payload = json.loads(result.output)
    assert payload["modules"][0]["id"] == "neurocnl"
    assert get.call_args_list[1].args[0] == "http://suite.test/api/suite/health/modules"


def test_status_degraded_module_exits_1() -> None:
    suite = _response({"status": "ok", "service": "suite_api", "version": "dev"})
    modules = _response({"modules": {"neurochip": {"status": "degraded", "error": "worker absent"}}})
    with patch("neurocli.lifecycle.httpx.get", side_effect=[suite, modules]):
        result = runner.invoke(app, ["status", "--json"])
    assert result.exit_code == 1
    assert json.loads(result.output)["modules"][0]["status"] == "degraded"


def test_status_unreachable_exits_2() -> None:
    with patch("neurocli.lifecycle.httpx.get", side_effect=httpx.ConnectError("refused")):
        result = runner.invoke(app, ["status", "--json"])
    assert result.exit_code == 2
    assert json.loads(result.output)["error"] == "suite_unreachable"


def test_install_builds_core_services() -> None:
    with (
        patch("neurocli.lifecycle.shutil.which", return_value="/usr/bin/docker"),
        patch("neurocli.lifecycle.subprocess.run") as run,
    ):
        result = runner.invoke(app, ["install", "--json"])
    assert result.exit_code == 0, result.output
    assert run.call_args_list[0].args[0] == ["docker", "compose", "version"]
    assert run.call_args_list[1].args[0] == [
        "docker",
        "compose",
        "build",
        "suite_api",
        "launcher-control",
        "jupyter-server",
    ]


def test_install_without_docker_exits_2() -> None:
    with patch("neurocli.lifecycle.shutil.which", return_value=None):
        result = runner.invoke(app, ["install", "--json"])
    assert result.exit_code == 2
    assert json.loads(result.output)["error"] == "docker_not_found"


def test_run_starts_core_services_and_verifies_health() -> None:
    health = _response({"status": "ok", "service": "suite_api", "version": "dev"})
    with (
        patch("neurocli.lifecycle.shutil.which", return_value="/usr/bin/docker"),
        patch("neurocli.lifecycle.subprocess.run") as run,
        patch("neurocli.lifecycle.httpx.get", return_value=health),
    ):
        result = runner.invoke(app, ["run", "--wait-timeout", "12", "--json"])
    assert result.exit_code == 0, result.output
    assert run.call_args_list[1].args[0] == [
        "docker",
        "compose",
        "up",
        "-d",
        "--wait",
        "--wait-timeout",
        "12",
        "suite_api",
        "launcher-control",
        "jupyter-server",
    ]
    assert json.loads(result.output)["status"] == "running"


def test_run_compose_failure_exits_2() -> None:
    with (
        patch("neurocli.lifecycle.shutil.which", return_value="/usr/bin/docker"),
        patch(
            "neurocli.lifecycle.subprocess.run",
            side_effect=[MagicMock(), __import__("subprocess").CalledProcessError(1, ["docker"])],
        ),
    ):
        result = runner.invoke(app, ["run", "--json"])
    assert result.exit_code == 2
    assert json.loads(result.output)["error"] == "compose_start_failed"
