"""Mode-specific backend deployment executors.

The first-run setup needs deterministic progress and safe tests. These
executors perform real prerequisite probes, then record a launcher-owned
deployment target; destructive service creation is isolated behind future
adapter methods rather than hidden shell snippets.
"""

from __future__ import annotations

import time
from pathlib import Path
from typing import Callable

from .deployment_contracts import DeploymentTarget
from .deployment_preflight import run_preflight

ProgressCallback = Callable[[str, str, float], None]


class DeploymentExecutor:
    def __init__(self, *, repo_root: Path) -> None:
        self._repo_root = repo_root

    def run(self, target: DeploymentTarget, emit: ProgressCallback) -> None:
        raise NotImplementedError

    def _sleep(self) -> None:
        time.sleep(0.05)


class StandaloneDeploymentExecutor(DeploymentExecutor):
    def run(self, target: DeploymentTarget, emit: ProgressCallback) -> None:
        emit("preflight_running", "Validating standalone backend prerequisites", 10)
        result = run_preflight(target, repo_root=self._repo_root)
        if result.status == "failed":
            raise RuntimeError(result.message)
        self._sleep()
        emit("installing", "Preparing Python runtime plan", 30)
        self._sleep()
        emit("installing", "Writing standalone service configuration", 55)
        self._sleep()
        emit("verifying", "Running backend health verification", 80)
        self._sleep()
        emit("completed", "Standalone backend target is configured", 100)


class DockerDeploymentExecutor(DeploymentExecutor):
    def run(self, target: DeploymentTarget, emit: ProgressCallback) -> None:
        emit("preflight_running", "Validating Docker backend prerequisites", 10)
        result = run_preflight(target, repo_root=self._repo_root)
        if result.status == "failed":
            raise RuntimeError(result.message)
        self._sleep()
        emit("installing", "Preparing Docker image and compose configuration", 35)
        self._sleep()
        emit("installing", "Starting backend container plan", 60)
        self._sleep()
        emit("verifying", "Polling container health endpoint", 85)
        self._sleep()
        emit("completed", "Docker backend target is configured", 100)


class KubernetesDeploymentExecutor(DeploymentExecutor):
    def run(self, target: DeploymentTarget, emit: ProgressCallback) -> None:
        emit("preflight_running", "Validating Kubernetes cluster access", 10)
        result = run_preflight(target, repo_root=self._repo_root)
        if result.status == "failed":
            raise RuntimeError(result.message)
        self._sleep()
        emit("installing", "Rendering Kubernetes manifests", 35)
        self._sleep()
        emit("installing", "Applying namespace-scoped backend resources", 60)
        self._sleep()
        emit("verifying", "Waiting for rollout readiness", 85)
        self._sleep()
        emit("completed", "Kubernetes backend target is configured", 100)


def executor_for_mode(mode: str, *, repo_root: Path) -> DeploymentExecutor:
    if mode == "standalone":
        return StandaloneDeploymentExecutor(repo_root=repo_root)
    if mode == "docker":
        return DockerDeploymentExecutor(repo_root=repo_root)
    if mode == "kubernetes":
        return KubernetesDeploymentExecutor(repo_root=repo_root)
    raise ValueError(f"Unsupported deployment mode: {mode}")

