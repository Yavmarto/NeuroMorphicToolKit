"""Factory for mode-specific deployment executors."""

from __future__ import annotations

from pathlib import Path

from .deployment_executor_base import (
    CommandRunnerProtocol,
    DeploymentExecutor,
    SecretResolver,
)
from .deployment_executor_docker import DockerDeploymentExecutor
from .deployment_executor_kubernetes import KubernetesDeploymentExecutor
from .deployment_executor_standalone import StandaloneDeploymentExecutor


def executor_for_mode(
    mode: str,
    *,
    repo_root: Path,
    secret_resolver: SecretResolver | None = None,
    command_runner: CommandRunnerProtocol | None = None,
) -> DeploymentExecutor:
    """Return the executor for a supported deployment mode."""
    executor_types: dict[str, type[DeploymentExecutor]] = {
        "standalone": StandaloneDeploymentExecutor,
        "docker": DockerDeploymentExecutor,
        "kubernetes": KubernetesDeploymentExecutor,
    }
    executor_type = executor_types.get(mode)
    if executor_type is None:
        raise ValueError(f"Unsupported deployment mode: {mode}")
    return executor_type(
        repo_root=repo_root,
        secret_resolver=secret_resolver,
        command_runner=command_runner,
    )


__all__ = ["executor_for_mode"]
