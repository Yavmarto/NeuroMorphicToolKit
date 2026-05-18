"""Preflight checks for launcher backend deployment targets."""

from __future__ import annotations

import os
import shutil
import socket
import subprocess
import sys
from pathlib import Path

from .deployment_contracts import DeploymentPreflightResult, DeploymentTarget


def port_is_open(host: str, port: int, timeout: float = 0.5) -> bool:
    try:
        with socket.create_connection((host, port), timeout=timeout):
            return True
    except OSError:
        return False


def run_preflight(target: DeploymentTarget, *, repo_root: Path) -> DeploymentPreflightResult:
    blocking: list[str] = []
    degraded: list[str] = []

    if target.target_type == "remote_host" and not target.host:
        blocking.append("preflight failed: remote host is required")
    if target.target_type == "kubernetes_cluster" and target.mode != "kubernetes":
        blocking.append("preflight failed: Kubernetes targets must use Kubernetes mode")
    if target.mode == "kubernetes" and target.target_type != "kubernetes_cluster":
        blocking.append("preflight failed: Kubernetes mode requires a cluster target")

    if target.mode == "standalone":
        _standalone_preflight(target, blocking, degraded)
    elif target.mode == "docker":
        _docker_preflight(target, blocking, degraded)
    elif target.mode == "kubernetes":
        _kubernetes_preflight(target, blocking, degraded)

    if not (repo_root / "nmtk" / "neuro_toolkit" / "assets" / "modules.json").exists():
        blocking.append("preflight failed: launcher module manifest is missing")

    if blocking:
        return DeploymentPreflightResult(
            status="failed",
            message=blocking[0],
            blocking_findings=blocking,
            degraded_findings=degraded,
            suggested_recovery="Fix the blocking preflight findings and retry deployment.",
        )
    if degraded:
        return DeploymentPreflightResult(
            status="degraded",
            message="degraded optional capability: deployment can continue with warnings",
            degraded_findings=degraded,
            suggested_recovery="Review the degraded capability warnings before continuing.",
        )
    return DeploymentPreflightResult(
        status="ok",
        message="preflight ready",
        suggested_recovery="No recovery action needed.",
    )


def _standalone_preflight(
    target: DeploymentTarget,
    blocking: list[str],
    degraded: list[str],
) -> None:
    if target.target_type == "local":
        if not sys.executable:
            blocking.append("preflight failed: Python runtime was not found")
        if target.backend_port and port_is_open("127.0.0.1", target.backend_port):
            degraded.append(
                f"degraded optional capability: port {target.backend_port} is already open"
            )
        return
    if target.target_type == "remote_host":
        if not target.username:
            blocking.append("preflight failed: SSH username is required")
        if shutil.which("ssh") is None:
            blocking.append("preflight failed: ssh client is not installed")
        if target.ssh_port <= 0:
            blocking.append("preflight failed: SSH port must be positive")


def _docker_preflight(
    target: DeploymentTarget,
    blocking: list[str],
    degraded: list[str],
) -> None:
    if target.target_type == "local":
        docker = shutil.which("docker")
        if docker is None:
            blocking.append("preflight failed: Docker CLI is not installed")
            return
        result = subprocess.run(
            [docker, "compose", "version"],
            capture_output=True,
            text=True,
            check=False,
            timeout=10,
        )
        if result.returncode != 0:
            degraded.append(
                "degraded optional capability: Docker Compose plugin was not confirmed"
            )
        return
    _standalone_preflight(target, blocking, degraded)
    if target.target_type == "remote_host":
        degraded.append("degraded optional capability: remote Docker daemon is validated during install")


def _kubernetes_preflight(
    target: DeploymentTarget,
    blocking: list[str],
    degraded: list[str],
) -> None:
    kubectl = shutil.which("kubectl")
    if kubectl is None:
        blocking.append("preflight failed: kubectl is not installed")
        return
    if not target.namespace:
        degraded.append("degraded optional capability: namespace defaults to current context")

    env = dict(os.environ)
    base_cmd = [kubectl]
    if target.context:
        base_cmd.extend(["--context", target.context])

    result = subprocess.run(
        base_cmd + ["config", "current-context"],
        capture_output=True,
        text=True,
        check=False,
        timeout=10,
        env=env,
    )
    if result.returncode != 0 and not target.context:
        blocking.append("preflight failed: kubeconfig current context could not be resolved")
        return

    cluster_result = subprocess.run(
        base_cmd + ["cluster-info"],
        capture_output=True,
        text=True,
        check=False,
        timeout=15,
        env=env,
    )
    if cluster_result.returncode != 0:
        blocking.append("preflight failed: kubectl cannot reach the cluster")
        return

    if target.namespace:
        ns_result = subprocess.run(
            base_cmd + ["get", "namespace", target.namespace],
            capture_output=True,
            text=True,
            check=False,
            timeout=10,
            env=env,
        )
        if ns_result.returncode != 0:
            degraded.append(
                f"degraded optional capability: namespace '{target.namespace}' does not exist; it will be created during deployment"
            )

        auth_result = subprocess.run(
            base_cmd
            + [
                "--namespace",
                target.namespace,
                "auth",
                "can-i",
                "create",
                "deployments",
            ],
            capture_output=True,
            text=True,
            check=False,
            timeout=10,
            env=env,
        )
        if auth_result.returncode != 0 or "yes" not in auth_result.stdout.lower():
            degraded.append(
                f"degraded optional capability: cannot confirm create permission in namespace '{target.namespace}'"
            )
