"""Kubernetes launcher deployment executor."""

from __future__ import annotations

import contextlib
import os
import tempfile
import time
from collections.abc import Generator
from pathlib import Path

from .deployment_contracts import DeploymentTarget
from .deployment_executor_base import (
    DeploymentExecutor,
    LogCallback,
    ProgressCallback,
    _bundled_or_path,
)
from .deployment_k8s_renderer import render_manifests, write_manifests
from .deployment_preflight import run_preflight


class KubernetesDeploymentExecutor(DeploymentExecutor):
    """Executor for Kubernetes cluster backend deployments via kubectl."""

    def run(
        self,
        target: DeploymentTarget,
        emit: ProgressCallback,
        log: LogCallback | None = None,
        clean_install: bool = False,
    ) -> None:
        """Render manifests and apply them to a Kubernetes cluster.

        Args:
            target: Deployment target. ``target_type`` must be
                ``"kubernetes_cluster"``.
            emit: Progress callback called with (stage, message, percent).
            log: Optional log-only callback for streaming raw command output.

        Raises:
            RuntimeError: If preflight fails, kubectl is not installed, or any
                kubectl command returns a non-zero exit code.
        """
        self._log = log or (lambda _line: None)
        emit("preflight_running", "Validating Kubernetes cluster access", 10)
        result = run_preflight(target, repo_root=self._repo_root)
        if result.status == "failed":
            raise RuntimeError(result.message)

        kubectl = _bundled_or_path("kubectl")
        if kubectl is None:
            raise RuntimeError("kubectl is not installed")

        emit("installing", "Rendering Kubernetes manifests", 35)
        manifests = render_manifests(
            target,
            app_name="nmtk-suite-api",
            image="ghcr.io/yavmarto/neurocnl",
            health_path="/api/suite/health",
            container_port=9000,
            replicas=1,
        )

        with tempfile.TemporaryDirectory(prefix="nmtk-k8s-") as tmpdir:
            manifest_dir = Path(tmpdir) / "manifests"
            write_manifests(manifests, manifest_dir)

            emit("installing", "Applying namespace-scoped backend resources", 60)
            self._kubectl_apply(kubectl, manifest_dir, target)

            emit("verifying", "Waiting for rollout readiness", 85)
            self._wait_rollout(kubectl, target)

            emit("verifying", "Running backend health verification", 95)
            self._health_check(target)

        emit("completed", "Kubernetes backend target is configured", 100)

    @contextlib.contextmanager
    def _kubectl_env_ctx(
        self, target: DeploymentTarget
    ) -> Generator[dict[str, str], None, None]:
        """Yield an env dict with KUBECONFIG set, cleaning up the temp file on exit.

        Mirrors the _ssh_key_context pattern: write secret to mkstemp,
        chmod 0o600, yield, unlink in finally.
        """
        env = dict(os.environ)
        if target.auth_mode == "kubeconfig":
            kubeconfig_ref = target.secret_refs.get("kubeconfig", "")
            kubeconfig = self._resolve_secret(kubeconfig_ref) if kubeconfig_ref else ""
            if kubeconfig:
                fd, path = tempfile.mkstemp(prefix="kubeconfig-", suffix=".yaml")
                try:
                    with os.fdopen(fd, "w") as fh:
                        fh.write(kubeconfig)
                    os.chmod(path, 0o600)
                    env["KUBECONFIG"] = path
                    yield env
                finally:
                    try:
                        os.unlink(path)
                    except OSError:
                        pass
                return
        yield env

    def _kubectl_base(self, kubectl: str, target: DeploymentTarget) -> list[str]:
        cmd = [kubectl]
        if target.context:
            cmd.extend(["--context", target.context])
        if target.namespace:
            cmd.extend(["--namespace", target.namespace])
        if target.auth_mode == "bearer_token":
            token_ref = target.secret_refs.get("bearerToken", "")
            token = self._resolve_secret(token_ref) if token_ref else ""
            if token:
                cmd.extend(["--token", token])
        return cmd

    def _kubectl_apply(
        self,
        kubectl: str,
        manifest_dir: Path,
        target: DeploymentTarget,
    ) -> None:
        with self._kubectl_env_ctx(target) as env:
            cmd = self._kubectl_base(kubectl, target) + [
                "apply",
                "-f",
                str(manifest_dir),
            ]
            result = self._commands.run(
                cmd,
                capture_output=True,
                text=True,
                check=False,
                timeout=60,
                env=env,
            )
        self._require_not_timed_out(result, operation="kubectl apply", timeout=60)
        if result.returncode != 0:
            err = (
                result.stderr.strip() or result.stdout.strip() or "kubectl apply failed"
            )
            raise RuntimeError(f"kubectl apply failed: {err}")

    def _wait_rollout(self, kubectl: str, target: DeploymentTarget) -> None:
        with self._kubectl_env_ctx(target) as env:
            cmd = self._kubectl_base(kubectl, target) + [
                "rollout",
                "status",
                "deployment/nmtk-suite-api",
                "--timeout",
                "300s",
            ]
            result = self._commands.run(
                cmd,
                capture_output=True,
                text=True,
                check=False,
                timeout=310,
                env=env,
            )
        self._require_not_timed_out(result, operation="Kubernetes rollout", timeout=310)
        if result.returncode != 0:
            err = result.stderr.strip() or result.stdout.strip() or "rollout timed out"
            raise RuntimeError(f"Rollout did not become ready: {err}")

    def _health_check(self, target: DeploymentTarget) -> None:
        host = target.api_server or self._cluster_host(target)
        port = target.backend_port or 9000
        url = f"http://{host}:{port}/api/suite/health"
        deadline = time.monotonic() + 120.0
        last_err = ""
        while time.monotonic() < deadline:
            try:
                with self._open_url(url, timeout=5.0) as response:
                    if response.status == 200:
                        return
            except Exception as exc:  # noqa: BLE001 - capture last error across retries
                last_err = str(exc)
            time.sleep(5.0)
        raise RuntimeError(f"Backend health check failed: {last_err}")

    def _cluster_host(self, target: DeploymentTarget) -> str:
        if target.host:
            return target.host
        kubectl = _bundled_or_path("kubectl")
        if kubectl is None:
            return "localhost"
        cmd = self._kubectl_base(kubectl, target) + [
            "get",
            "service",
            "nmtk-suite-api",
            "-o",
            "jsonpath={.status.loadBalancer.ingress[0].ip}",
        ]
        with self._kubectl_env_ctx(target) as env:
            result = self._commands.run(
                cmd,
                capture_output=True,
                text=True,
                check=False,
                timeout=15,
                env=env,
            )
        self._require_not_timed_out(
            result, operation="Kubernetes service discovery", timeout=15
        )
        ip = result.stdout.strip()
        return ip if ip else "localhost"


__all__ = ["KubernetesDeploymentExecutor"]
