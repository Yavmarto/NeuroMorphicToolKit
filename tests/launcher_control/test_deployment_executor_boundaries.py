"""Contracts for the split launcher deployment executors."""

from __future__ import annotations

import ast
import io
import subprocess
from dataclasses import FrozenInstanceError
from pathlib import Path
from unittest import mock

import pytest

from nmtk.launcher_control import deployment_executor_base as executor_base
from nmtk.launcher_control import deployment_executors as compatibility_facade
from nmtk.launcher_control.deployment_contracts import DeploymentTarget
from nmtk.launcher_control.deployment_executor_docker import (
    DockerDeploymentExecutor,
)
from nmtk.launcher_control.deployment_executor_factory import executor_for_mode
from nmtk.launcher_control.deployment_executor_kubernetes import (
    KubernetesDeploymentExecutor,
)
from nmtk.launcher_control.deployment_executor_standalone import (
    StandaloneDeploymentExecutor,
)


def test_compatibility_facade_reexports_owning_executor_classes() -> None:
    assert compatibility_facade.DockerDeploymentExecutor is DockerDeploymentExecutor
    assert (
        compatibility_facade.KubernetesDeploymentExecutor
        is KubernetesDeploymentExecutor
    )
    assert (
        compatibility_facade.StandaloneDeploymentExecutor
        is StandaloneDeploymentExecutor
    )
    assert compatibility_facade.executor_for_mode is executor_for_mode


def test_internal_executor_modules_do_not_import_compatibility_facade() -> None:
    launcher_root = Path(__file__).parents[2] / "nmtk" / "launcher_control"
    offenders: list[str] = []
    for path in sorted(launcher_root.glob("deployment_executor_*.py")):
        tree = ast.parse(path.read_text(encoding="utf-8"))
        if any(
            isinstance(node, ast.ImportFrom) and node.module == "deployment_executors"
            for node in ast.walk(tree)
        ):
            offenders.append(path.name)
    assert offenders == []


def test_factory_injects_one_typed_runner_into_every_mode() -> None:
    runner = mock.create_autospec(executor_base.CommandRunnerProtocol, instance=True)
    expected_types = {
        "standalone": StandaloneDeploymentExecutor,
        "docker": DockerDeploymentExecutor,
        "kubernetes": KubernetesDeploymentExecutor,
    }
    for mode, expected_type in expected_types.items():
        executor = executor_for_mode(
            mode,
            repo_root=Path("/tmp"),
            command_runner=runner,
        )
        assert isinstance(executor, expected_type)
        assert executor._commands is runner


def test_command_result_is_immutable_and_redacts_output() -> None:
    secret = "correct horse battery staple"
    completed = mock.Mock(
        returncode=7,
        stdout=f"stdout contains {secret}",
        stderr=f"stderr contains {secret}",
    )
    runner = executor_base.SubprocessCommandRunner()
    with mock.patch.object(executor_base.subprocess, "run", return_value=completed):
        result = runner.run(["example"], sensitive_values=(secret,))

    assert result.returncode == 7
    assert secret not in result.stdout
    assert secret not in result.stderr
    assert "<redacted>" in result.stdout
    with pytest.raises(FrozenInstanceError):
        result.stdout = "changed"


def test_command_timeout_returns_redacted_structured_result() -> None:
    secret = "timeout-secret"
    timeout = subprocess.TimeoutExpired(
        cmd=["example"],
        timeout=5,
        output=f"partial {secret}",
        stderr=f"failed {secret}",
    )
    runner = executor_base.SubprocessCommandRunner()
    with mock.patch.object(executor_base.subprocess, "run", side_effect=timeout):
        result = runner.run(["example"], timeout=5, sensitive_values=(secret,))

    assert result.timed_out is True
    assert result.returncode == -1
    assert secret not in f"{result.stdout}{result.stderr}"


def test_executor_maps_structured_timeout_to_safe_failure() -> None:
    runner = mock.create_autospec(executor_base.CommandRunnerProtocol, instance=True)
    runner.run.return_value = executor_base.CommandResult(
        returncode=-1,
        stdout="",
        stderr="",
        timed_out=True,
    )
    executor = DockerDeploymentExecutor(
        repo_root=Path("/tmp"),
        command_runner=runner,
    )
    target = DeploymentTarget(
        id="timeout",
        display_name="Timeout",
        target_type="local",
        mode="docker",
    )

    with pytest.raises(RuntimeError, match="docker compose down timed out after 300s"):
        executor._compose_down_local("docker", target)


def test_streaming_runner_redacts_lines_and_bounds_retained_tail() -> None:
    secret = "stream-secret"
    lines = [f"line-{index}" for index in range(44)] + [f"final {secret}"]
    process = mock.Mock()
    process.stdout = io.StringIO("".join(f"{line}\n" for line in lines))
    process.poll.return_value = 0
    process.wait.return_value = 0
    emitted: list[str] = []
    runner = executor_base.SubprocessCommandRunner()

    with mock.patch.object(executor_base.subprocess, "Popen", return_value=process):
        result = runner.stream(
            ["example"],
            timeout=5,
            on_line=emitted.append,
            sensitive_values=(secret,),
        )

    assert result.returncode == 0
    assert len(result.stdout.splitlines()) == 40
    assert secret not in result.stdout
    assert secret not in "\n".join(emitted)
    assert emitted[-1] == "final <redacted>"
