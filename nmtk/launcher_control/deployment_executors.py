"""Compatibility façade for mode-specific deployment executors."""

from __future__ import annotations

import shutil as shutil
import subprocess as subprocess
import urllib.request  # noqa: F401 - one-release monkeypatch compatibility

from .deployment_executor_base import (
    CommandResult,
    CommandRunnerProtocol,
    DeploymentExecutor,
    SubprocessCommandRunner,
    build_ssh_argv,
)
from .deployment_executor_docker import DockerDeploymentExecutor
from .deployment_executor_factory import executor_for_mode
from .deployment_executor_kubernetes import KubernetesDeploymentExecutor
from .deployment_executor_standalone import StandaloneDeploymentExecutor

# The process and HTTP module imports above preserve one-release monkeypatch
# compatibility for downstream tests that patched clients through this façade.

__all__ = [
    "CommandResult",
    "CommandRunnerProtocol",
    "DeploymentExecutor",
    "DockerDeploymentExecutor",
    "KubernetesDeploymentExecutor",
    "StandaloneDeploymentExecutor",
    "SubprocessCommandRunner",
    "build_ssh_argv",
    "executor_for_mode",
]
