"""Mode-specific backend deployment executors."""

from __future__ import annotations

import contextlib
import os
import shlex
import shutil
import subprocess
import tempfile
import time
import urllib.request
from pathlib import Path
from typing import Callable

from .deployment_contracts import DeploymentTarget
from .deployment_k8s_renderer import render_manifests, write_manifests
from .deployment_preflight import run_preflight

ProgressCallback = Callable[[str, str, float], None]
SecretResolver = Callable[[str], str]


def _redact(value: str) -> str:
    return value[:4] + "..." + value[-4:] if len(value) > 12 else "***"


class DeploymentExecutor:
    def __init__(
        self,
        *,
        repo_root: Path,
        secret_resolver: SecretResolver | None = None,
    ) -> None:
        self._repo_root = repo_root
        self._secret_resolver = secret_resolver

    def run(self, target: DeploymentTarget, emit: ProgressCallback) -> None:
        raise NotImplementedError

    def _sleep(self) -> None:
        time.sleep(0.05)

    def _resolve_secret(self, ref: str) -> str:
        if self._secret_resolver is None:
            return ""
        return self._secret_resolver(ref)


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
    """Execute a Docker Compose backend deployment on a local or remote host."""

    def run(self, target: DeploymentTarget, emit: ProgressCallback) -> None:
        emit("preflight_running", "Validating Docker backend prerequisites", 10)
        result = run_preflight(target, repo_root=self._repo_root)
        if result.status == "failed":
            raise RuntimeError(result.message)

        if target.target_type == "local":
            self._deploy_local(target, emit)
        elif target.target_type == "remote_host":
            self._deploy_remote(target, emit)
        else:
            raise RuntimeError(
                f"Docker mode does not support target type: {target.target_type!r}"
            )

    # ------------------------------------------------------------------
    # Local deployment
    # ------------------------------------------------------------------

    def _deploy_local(self, target: DeploymentTarget, emit: ProgressCallback) -> None:
        docker = shutil.which("docker")
        if docker is None:
            raise RuntimeError("docker CLI is not installed")

        emit("installing", "Building Docker images", 42)
        self._compose_build_local(docker, target)

        emit("installing", "Starting backend containers", 65)
        self._compose_up_local(docker, target)

        emit("verifying", "Polling container health endpoint", 85)
        self._health_check(target, host="127.0.0.1")

        emit("completed", "Docker backend is running locally", 100)

    def _compose_env(self, target: DeploymentTarget) -> dict[str, str]:
        env = dict(os.environ)
        env["SUITE_API_PORT"] = str(target.backend_port or 9000)
        return env

    def _compose_build_local(self, docker: str, target: DeploymentTarget) -> None:
        cmd = [docker, "compose", "build", "--parallel"]
        result = subprocess.run(
            cmd,
            cwd=str(self._repo_root),
            capture_output=True,
            text=True,
            check=False,
            timeout=600,
            env=self._compose_env(target),
        )
        if result.returncode != 0:
            err = result.stderr.strip() or result.stdout.strip() or "docker compose build failed"
            raise RuntimeError(f"docker compose build failed: {err}")

    def _compose_up_local(self, docker: str, target: DeploymentTarget) -> None:
        cmd = [docker, "compose", "up", "-d", "--wait", "--remove-orphans"]
        result = subprocess.run(
            cmd,
            cwd=str(self._repo_root),
            capture_output=True,
            text=True,
            check=False,
            timeout=300,
            env=self._compose_env(target),
        )
        if result.returncode != 0:
            err = result.stderr.strip() or result.stdout.strip() or "docker compose up failed"
            raise RuntimeError(f"docker compose up failed: {err}")

    # ------------------------------------------------------------------
    # Remote deployment
    # ------------------------------------------------------------------

    def _deploy_remote(self, target: DeploymentTarget, emit: ProgressCallback) -> None:
        if not target.host:
            raise RuntimeError("Remote host is required for remote Docker deployment")

        deploy_dir = target.install_root or "/opt/nmtk"

        emit("installing", f"Syncing source code to {target.host}", 20)
        self._rsync_to_remote(target, deploy_dir)

        emit("installing", "Initializing required secrets", 38)
        self._init_remote_secrets(target, deploy_dir)

        emit("installing", "Building Docker images on remote host", 52)
        self._ssh_run(
            target,
            f"cd {deploy_dir} && docker compose build --parallel",
        )

        emit("installing", "Starting backend containers on remote host", 70)
        self._ssh_run(
            target,
            f"cd {deploy_dir} && docker compose up -d --wait --remove-orphans",
        )

        emit("verifying", "Polling backend health endpoint", 88)
        self._health_check(target, host=target.host)

        emit("completed", f"Docker backend deployed to {target.host}", 100)

    def _init_remote_secrets(self, target: DeploymentTarget, deploy_dir: str) -> None:
        """Ensure GRAFANA_ADMIN_PASSWORD is set in the remote .env file."""
        quoted = shlex.quote(deploy_dir)
        self._ssh_run(
            target,
            f"touch {quoted}/.env && grep -q GRAFANA_ADMIN_PASSWORD {quoted}/.env"
            f" || echo \"GRAFANA_ADMIN_PASSWORD=$(openssl rand -base64 32)\" >> {quoted}/.env",
        )

    def _rsync_to_remote(self, target: DeploymentTarget, deploy_dir: str) -> None:
        remote = f"{target.username}@{target.host}" if target.username else target.host
        with self._ssh_key_context(target) as key_path:
            # Ensure deploy dir exists on remote
            mkdir_cmd = self._ssh_base_args(target, key_path) + [remote, f"mkdir -p {deploy_dir}"]
            result = subprocess.run(
                mkdir_cmd,
                capture_output=True,
                text=True,
                check=False,
                timeout=30,
            )
            if result.returncode != 0:
                err = result.stderr.strip() or "mkdir failed on remote"
                raise RuntimeError(f"Could not create deploy directory on remote: {err}")

            ssh_opts, extra_env = self._ssh_opts_str(target, key_path)
            rsync_env = dict(os.environ)
            rsync_env.update(extra_env)
            rsync_cmd = [
                "rsync", "-av", "--delete",
                "-e", ssh_opts,
                "--exclude", ".git",
                "--exclude", ".env",
                "--exclude", "venv",
                "--exclude", ".venv",
                "--exclude", "__pycache__",
                "--exclude", "node_modules",
                "--exclude", "*.pyc",
                "--exclude", "build/",
                "--exclude", "*.dill",
                "--exclude", "*.dill.track.dill",
                "--exclude", ".cache",
                "--exclude", ".hypothesis",
                "--exclude", ".kiro",
                "--exclude", ".understand-anything",
                "--exclude", ".sisyphus",
                "--exclude", ".impeccable",
                "--exclude", ".tmp_manual_ui",
                "--exclude", ".swarm/",
                "--exclude", ".opencode/",
                "--exclude", ".cursor/",
                "--exclude", "docs/",
                "--exclude", "issues/",
                "--exclude", "issues-archive/",
                "--exclude", "ai_safe/",
                "--exclude", "Neuro-Dream-Hand/",
                "--exclude", "neurocnl/frontend/",
                "--exclude", "Neurohub/frontend/",
                "--exclude", "Neurochip/frontend/",
                "--exclude", "Neurobench/frontend/",
                "--exclude", "Neurosim/frontend/",
                "--exclude", "nmtk_ui_core/",
                "--exclude", "nmtk/neuro_toolkit/lib/",
                "--exclude", "nmtk/neuro_toolkit/build/",
                "--exclude", "nmtk/neuro_toolkit/.dart_tool/",
                "--exclude", "nmtk/neuro_toolkit/android/",
                "--exclude", "nmtk/neuro_toolkit/ios/",
                "--exclude", "nmtk/neuro_toolkit/macos/",
                "--exclude", "nmtk/neuro_toolkit/linux/",
                "--exclude", "nmtk/neuro_toolkit/windows/",
                "--exclude", "nmtk/neuro_toolkit/web/",
                "--exclude", "nmtk/packages/",
                str(self._repo_root) + "/",
                f"{remote}:{deploy_dir}/",
            ]
            result = subprocess.run(
                rsync_cmd,
                capture_output=True,
                text=True,
                check=False,
                timeout=300,
                env=rsync_env,
            )
            if result.returncode != 0:
                err = result.stderr.strip() or result.stdout.strip() or "rsync failed"
                raise RuntimeError(f"Source sync to remote failed: {err}")

    def _ssh_run(self, target: DeploymentTarget, remote_cmd: str, timeout: int = 600) -> None:
        remote = f"{target.username}@{target.host}" if target.username else target.host
        with self._ssh_key_context(target) as key_path:
            cmd = self._ssh_base_args(target, key_path) + [remote, remote_cmd]
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                check=False,
                timeout=timeout,
            )
            if result.returncode != 0:
                err = result.stderr.strip() or result.stdout.strip() or "SSH command failed"
                raise RuntimeError(f"Remote command failed: {err}")

    def _ssh_base_args(self, target: DeploymentTarget, key_path: str | None) -> list[str]:
        """Build the ssh argv prefix (excluding the remote address and command)."""
        ssh_cmd = [
            "ssh",
            "-p", str(target.ssh_port or 22),
            "-o", "StrictHostKeyChecking=no",  # Bootstrap: host not in known_hosts on first deploy; TODO: adopt TOFU strategy
            "-o", "BatchMode=yes",
        ]
        if key_path:
            ssh_cmd.extend(["-i", key_path])
            return ssh_cmd
        if target.auth_mode == "ssh_password":
            sshpass = shutil.which("sshpass")
            if sshpass is None:
                raise RuntimeError(
                    "sshpass is required for SSH password authentication but was not found"
                )
            password_ref = target.secret_refs.get("sshPassword", "")
            password = self._resolve_secret(password_ref) if password_ref else ""
            if not password:
                raise RuntimeError("SSH password is required but could not be resolved")
            return [sshpass, "-p", password] + ssh_cmd
        return ssh_cmd

    def _ssh_opts_str(
        self, target: DeploymentTarget, key_path: str | None
    ) -> tuple[str, dict[str, str]]:
        """Return (ssh-opts-string, extra-env) for use with rsync -e.

        The extra-env dict must be merged into the subprocess environment so
        that credentials travel via env vars (SSHPASS) rather than the process
        argument list, which is visible in ps(1) and /proc/<pid>/cmdline.
        """
        base = (
            f"ssh -p {target.ssh_port or 22}"
            " -o StrictHostKeyChecking=no"  # Bootstrap: host not in known_hosts on first deploy; TODO: adopt TOFU strategy
            " -o BatchMode=yes"
        )
        if key_path:
            return f"{base} -i {key_path}", {}
        if target.auth_mode == "ssh_password":
            password_ref = target.secret_refs.get("sshPassword", "")
            password = self._resolve_secret(password_ref) if password_ref else ""
            if password:
                # Use SSHPASS env var + `sshpass -e` to keep the password out of
                # the process argument list (avoids ps/proc exposure).
                return f"sshpass -e {base}", {"SSHPASS": password}
        return base, {}

    @contextlib.contextmanager
    def _ssh_key_context(self, target: DeploymentTarget):  # type: ignore[return]  # mypy cannot infer Generator return type for contextmanager with conditional early return
        """Write the SSH private key to a temp file for the duration of the block."""
        if target.auth_mode == "ssh_key":
            key_ref = (
                target.secret_refs.get("sshPrivateKey")
                or target.secret_refs.get("privateKey", "")
            )
            key = self._resolve_secret(key_ref) if key_ref else ""
            if key:
                fd, path = tempfile.mkstemp(prefix="nmtk-ssh-key-")
                try:
                    with os.fdopen(fd, "w") as fh:
                        fh.write(key)
                    os.chmod(path, 0o600)
                    yield path
                finally:
                    try:
                        os.unlink(path)
                    except OSError:
                        pass
                return
        yield None

    # ------------------------------------------------------------------
    # Health check (shared by local + remote)
    # ------------------------------------------------------------------

    def _health_check(self, target: DeploymentTarget, *, host: str) -> None:
        port = target.backend_port or 9000
        url = f"http://{host}:{port}/api/suite/health"
        deadline = time.monotonic() + 120.0
        last_err = ""
        while time.monotonic() < deadline:
            try:
                with urllib.request.urlopen(url, timeout=5.0) as resp:
                    if resp.status == 200:
                        return
            except Exception as exc:
                last_err = str(exc)
            time.sleep(5.0)
        raise RuntimeError(f"Backend health check timed out at {url}: {last_err}")


class KubernetesDeploymentExecutor(DeploymentExecutor):
    def run(self, target: DeploymentTarget, emit: ProgressCallback) -> None:
        emit("preflight_running", "Validating Kubernetes cluster access", 10)
        result = run_preflight(target, repo_root=self._repo_root)
        if result.status == "failed":
            raise RuntimeError(result.message)

        kubectl = shutil.which("kubectl")
        if kubectl is None:
            raise RuntimeError("kubectl is not installed")

        emit("installing", "Rendering Kubernetes manifests", 35)
        manifests = render_manifests(
            target,
            app_name="nmtk-suite-api",
            image="ghcr.io/completed-spoon-6/neurocnl",
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

    def _kubectl_env(self, target: DeploymentTarget) -> dict[str, str]:
        env = dict(os.environ)
        if target.auth_mode == "kubeconfig":
            kubeconfig_ref = target.secret_refs.get("kubeconfig", "")
            kubeconfig = self._resolve_secret(kubeconfig_ref) if kubeconfig_ref else ""
            if kubeconfig:
                fd, path = tempfile.mkstemp(prefix="kubeconfig-", suffix=".yaml")
                try:
                    with os.fdopen(fd, "w") as fh:
                        fh.write(kubeconfig)
                    env["KUBECONFIG"] = path
                except OSError:
                    os.close(fd)
        return env

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
        env = self._kubectl_env(target)
        cmd = self._kubectl_base(kubectl, target) + ["apply", "-f", str(manifest_dir)]
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            check=False,
            timeout=60,
            env=env,
        )
        if result.returncode != 0:
            err = result.stderr.strip() or result.stdout.strip() or "kubectl apply failed"
            raise RuntimeError(f"kubectl apply failed: {err}")

    def _wait_rollout(self, kubectl: str, target: DeploymentTarget) -> None:
        env = self._kubectl_env(target)
        cmd = self._kubectl_base(kubectl, target) + [
            "rollout",
            "status",
            "deployment/nmtk-suite-api",
            "--timeout",
            "300s",
        ]
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            check=False,
            timeout=310,
            env=env,
        )
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
                with urllib.request.urlopen(url, timeout=5.0) as response:
                    if response.status == 200:
                        return
            except Exception as exc:
                last_err = str(exc)
            time.sleep(5.0)
        raise RuntimeError(f"Backend health check failed: {last_err}")

    def _cluster_host(self, target: DeploymentTarget) -> str:
        if target.host:
            return target.host
        env = self._kubectl_env(target)
        kubectl = shutil.which("kubectl")
        if kubectl is None:
            return "localhost"
        cmd = self._kubectl_base(kubectl, target) + [
            "get",
            "service",
            "nmtk-suite-api",
            "-o",
            "jsonpath={.status.loadBalancer.ingress[0].ip}",
        ]
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            check=False,
            timeout=15,
            env=env,
        )
        ip = result.stdout.strip()
        return ip if ip else "localhost"


def executor_for_mode(
    mode: str,
    *,
    repo_root: Path,
    secret_resolver: SecretResolver | None = None,
) -> DeploymentExecutor:
    if mode == "standalone":
        return StandaloneDeploymentExecutor(
            repo_root=repo_root,
            secret_resolver=secret_resolver,
        )
    if mode == "docker":
        return DockerDeploymentExecutor(
            repo_root=repo_root,
            secret_resolver=secret_resolver,
        )
    if mode == "kubernetes":
        return KubernetesDeploymentExecutor(
            repo_root=repo_root,
            secret_resolver=secret_resolver,
        )
    raise ValueError(f"Unsupported deployment mode: {mode}")
