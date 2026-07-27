"""Mode-specific backend deployment executors."""

from __future__ import annotations

import contextlib
import os
import queue
import re
import shlex
import shutil
import subprocess
import tempfile
import threading
import time
import urllib.request
from pathlib import Path
from typing import Callable

from .config import REPO_ROOT
from .deployment_contracts import (
    DeploymentTarget,
    container_engine_install_commands,
    encode_remote_script,
    podman_runtime_setup_script,
    sudo_elevation_preamble,
)
from .deployment_k8s_renderer import render_manifests, write_manifests
from .deployment_preflight import run_preflight

ProgressCallback = Callable[[str, str, float], None]
# Log-only channel: appends a raw remote-command output line to the job's
# rolling log tail WITHOUT changing stage/percent/headline. Distinct from
# ProgressCallback so live terminal output can stream under a stable phase.
LogCallback = Callable[[str], None]
SecretResolver = Callable[[str], str]

__all__ = ["DeploymentExecutor", "executor_for_mode"]


def _redact(value: str) -> str:
    return value[:4] + "..." + value[-4:] if len(value) > 12 else "***"


def _bundled_or_path(name: str) -> str | None:
    """Resolve an external CLI, preferring a binary bundled with the app.

    In a shipped macOS app REPO_ROOT is Contents/Resources; build-standalone.sh
    vendors tools the end user's machine may lack (notably `sshpass`) under
    Contents/Resources/bin so server setup works out of the box. Falls back to
    PATH for dev machines. Returns None only if the tool is nowhere to be found.
    """
    bundled = REPO_ROOT / "bin" / name
    if bundled.is_file() and os.access(bundled, os.X_OK):
        return str(bundled)
    return shutil.which(name)


def build_ssh_argv(
    port: int, *, key_path: str | None, password: str | None
) -> tuple[list[str], dict[str, str]]:
    """Build the ssh argv prefix (excluding the remote address and command).

    Target-agnostic so it can be used both for target-backed SSH calls
    (via `DeploymentExecutor._ssh_base_args`) and one-off sessions that
    don't have a `DeploymentTarget` at all, e.g. a root-credential bootstrap
    session.

    Returns (argv, extra_env). Password auth must travel via the SSHPASS
    env var (sshpass -e), never as a -p argv item — argv is visible to
    every local user via ps(1)/proc, and gets echoed verbatim into any
    subprocess exception message (e.g. TimeoutExpired), which then flows
    straight into job logs and the UI. Mirrors _ssh_opts_str below.
    """
    ssh_cmd = [
        "ssh",
        "-p",
        str(port or 22),
        "-o",
        "StrictHostKeyChecking=no",  # Bootstrap: host not in known_hosts on first deploy; TODO: adopt TOFU strategy
    ]
    if key_path:
        # BatchMode=yes here just means "never hang waiting on a
        # passphrase prompt this key can't answer anyway" — safe and
        # desired for key auth.
        ssh_cmd.extend(["-o", "BatchMode=yes", "-i", key_path])
        return ssh_cmd, {}
    if password:
        sshpass = _bundled_or_path("sshpass")
        if sshpass is None:
            raise RuntimeError(
                "sshpass is required for SSH password authentication but was not found"
            )
        # BatchMode=yes disables every interactive prompt — including
        # the password prompt sshpass depends on intercepting. Setting
        # it here means password auth can never succeed, no matter how
        # correct the password is. Must be omitted for this path.
        return [sshpass, "-e"] + ssh_cmd, {"SSHPASS": password}
    ssh_cmd.extend(["-o", "BatchMode=yes"])
    return ssh_cmd, {}


class DeploymentExecutor:
    """Abstract base class for mode-specific backend deployment executors.

    Subclasses implement ``run()`` for a specific deployment mode
    (standalone, Docker Compose, Kubernetes). Progress is reported via
    the ``emit`` callback with stage, message, and percent-complete.
    """

    # Minimum gap between raw output lines forwarded to the log channel.
    # Bounds job-store writes when a remote command (e.g. docker build)
    # emits output faster than a human can read it.
    _LOG_THROTTLE_SECONDS = 1.5

    def __init__(
        self,
        *,
        repo_root: Path,
        secret_resolver: SecretResolver | None = None,
    ) -> None:
        self._repo_root = repo_root
        self._secret_resolver = secret_resolver
        # No-op default so internal helpers can always call self._log(...)
        # even if a run() override is invoked without a log callback.
        self._log: LogCallback = lambda _line: None

    def run(
        self,
        target: DeploymentTarget,
        emit: ProgressCallback,
        log: LogCallback | None = None,
        clean_install: bool = False,
    ) -> None:
        raise NotImplementedError

    def _resolve_secret(self, ref: str) -> str:
        if self._secret_resolver is None:
            return ""
        return self._secret_resolver(ref)

    @staticmethod
    def _resolve_tool(name: str) -> str:
        """Bundled-first tool path, falling back to the bare name.

        Use for tools that are expected to exist (ssh/rsync ship with macOS);
        for tools that may be genuinely absent, call `_bundled_or_path` and
        handle None explicitly (see `build_ssh_argv`).
        """
        return _bundled_or_path(name) or name


class StandaloneDeploymentExecutor(DeploymentExecutor):
    """Executor for standalone (no container runtime) backend deployments."""

    def run(
        self,
        target: DeploymentTarget,
        emit: ProgressCallback,
        log: LogCallback | None = None,
        clean_install: bool = False,
    ) -> None:
        """Configure a standalone Python-runtime backend target.

        Args:
            target: Deployment target describing host, auth, and port settings.
            emit: Progress callback called with (stage, message, percent).
            log: Optional log-only callback for streaming raw command output.

        Raises:
            RuntimeError: If preflight validation fails.
        """
        self._log = log or (lambda _line: None)
        emit("preflight_running", "Validating standalone backend prerequisites", 10)
        result = run_preflight(target, repo_root=self._repo_root)
        if result.status == "failed":
            raise RuntimeError(result.message)
        time.sleep(0.05)
        emit("installing", "Preparing Python runtime plan", 30)
        time.sleep(0.05)
        emit("installing", "Writing standalone service configuration", 55)
        time.sleep(0.05)
        emit("verifying", "Running backend health verification", 80)
        time.sleep(0.05)
        emit("completed", "Standalone backend target is configured", 100)


class DockerDeploymentExecutor(DeploymentExecutor):
    """Execute a Docker Compose backend deployment on a local or remote host."""

    _REMOTE_CLIENT_PORTS: tuple[int, ...] = (9000, 8090, 8008)
    _REMOTE_COMPOSE_PROJECT = "nmtk"

    def run(
        self,
        target: DeploymentTarget,
        emit: ProgressCallback,
        log: LogCallback | None = None,
        clean_install: bool = False,
    ) -> None:
        """Run a Docker Compose deployment to a local host or remote SSH target.

        Args:
            target: Deployment target. ``target_type`` must be ``"local"`` or
                ``"remote_host"``.
            emit: Progress callback called with (stage, message, percent).
            log: Optional log-only callback for streaming raw command output.

        Raises:
            RuntimeError: If preflight fails, Docker is not installed, or any
                subprocess step returns a non-zero exit code.
        """
        self._log = log or (lambda _line: None)
        emit("preflight_running", "Validating Docker backend prerequisites", 10)
        result = run_preflight(target, repo_root=self._repo_root)
        if result.status == "failed":
            raise RuntimeError(result.message)

        if target.target_type == "local":
            self._deploy_local(target, emit)
        elif target.target_type == "remote_host":
            self._deploy_remote(target, emit, clean_install=clean_install)
        else:
            raise RuntimeError(
                f"Docker mode does not support target type: {target.target_type!r}"
            )

    # ------------------------------------------------------------------
    # Local deployment
    # ------------------------------------------------------------------

    def _deploy_local(self, target: DeploymentTarget, emit: ProgressCallback, clean_install: bool = False) -> None:
        engine = target.container_engine or "docker"
        docker = shutil.which(engine)
        if docker is None:
            raise RuntimeError(f"{engine} CLI is not installed")

        if clean_install:
            emit("installing", "Cleaning existing volumes", 10)
            self._compose_down_local(docker, target, volumes=True)

        emit("installing", f"Building {engine} images", 42)
        self._compose_build_local(docker, target)

        emit("installing", "Starting backend containers", 65)
        self._compose_up_local(docker, target)

        emit("verifying", "Polling container health endpoint", 85)
        self._health_check(target, host="127.0.0.1")

        emit("completed", f"{engine.capitalize()} backend is running locally", 100)

    def _compose_env(self, target: DeploymentTarget) -> dict[str, str]:
        env = dict(os.environ)
        env["SUITE_API_PORT"] = str(target.backend_port or 9000)
        env["NMTK_IMAGE_TAG"] = self._image_tag(target)
        if target.target_type == "remote_host" and target.host:
            env["JUPYTER_PUBLIC_URL"] = f"http://{target.host}:8008/lab"
        return env

    @staticmethod
    def _image_tag(target: DeploymentTarget) -> str:
        """Return a shell/Compose-safe image tag, defaulting to ``latest``."""
        tag = (target.image_tag or "latest").strip()
        return tag if re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", tag) else "latest"

    def _compose_down_local(self, docker: str, target: DeploymentTarget, volumes: bool = False) -> None:
        cmd = [docker, "compose", "down", "--remove-orphans"]
        if volumes:
            cmd.append("-v")
        subprocess.run(
            cmd,
            cwd=str(self._repo_root),
            capture_output=True,
            text=True,
            check=False,
            timeout=300,
            env=self._compose_env(target),
        )

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
            err = (
                result.stderr.strip()
                or result.stdout.strip()
                or "docker compose build failed"
            )
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
            err = (
                result.stderr.strip()
                or result.stdout.strip()
                or "docker compose up failed"
            )
            raise RuntimeError(f"docker compose up failed: {err}")

    # ------------------------------------------------------------------
    # Remote deployment
    # ------------------------------------------------------------------

    # Compose files (+ config dir) shipped to the remote for a source-free
    # deploy. Resolved under self._repo_root, which is the repo root in dev
    # and Contents/Resources in a bundled app (build-standalone.sh copies
    # these there). No repo source is sent — images are pulled from GHCR.
    _REMOTE_MANIFESTS: tuple[str, ...] = (
        "docker-compose.yml",
        "docker-compose.prod.yml",
        "docker-compose.remote.yml",
        "monitoring",
    )

    def _deploy_remote(self, target: DeploymentTarget, emit: ProgressCallback, clean_install: bool = False) -> None:
        if not target.host:
            raise RuntimeError("Remote host is required for remote Docker deployment")

        deploy_dir = self._resolve_remote_deploy_dir(target)

        emit("installing", f"Preparing {target.host}", 15)

        self._ensure_engine_installed(target)

        if (target.container_engine or "docker") == "docker":
            self._ensure_docker_permissions(target)
        else:
            self._prepare_podman_runtime(target)

        emit("installing", "Copying deployment manifests", 25)
        self._copy_manifests_to_remote(target, deploy_dir)

        emit("installing", "Initializing required secrets", 35)
        self._init_remote_secrets(target, deploy_dir)
        emit("preflight_running", "Validating remote container provider", 38)
        self._remote_provider_preflight(target, deploy_dir)
        emit("installing", "Releasing stale NMTK port bindings", 40)
        self._remote_port_owner_probe(target)
        self._remote_cleanup_stale_projects(target, deploy_dir)

        emit("installing", "Stopping existing NMTK stack", 42)
        down_opts = "-v --remove-orphans" if clean_install else "--remove-orphans"
        self._ssh_run(
            target,
            self._remote_compose_cmd(deploy_dir, target, f"down {down_opts}"),
            timeout=300,
        )
        try:
            self._ssh_run(
                target,
                self._remote_compose_cmd(deploy_dir, target, f"down {down_opts}"),
                timeout=300,
            )
        except RuntimeError as exc:
            self._log(f"Existing NMTK stack cleanup skipped: {exc}")
        # Source-free image pull. docker's own per-image/layer progress
        # streams to the log channel via _ssh_run, so the card shows real
        # activity instead of a frozen headline. Generous timeout: first
        # pull on a clean host fetches several images.
        emit("installing", "Pulling backend images", 45)
        self._ssh_run(
            target,
            self._remote_compose_cmd(deploy_dir, target, "pull"),
            timeout=1800,
        )

        emit("installing", "Starting backend services", 80)
        try:
            self._ssh_run(
                target,
                self._remote_compose_cmd(deploy_dir, target, "up -d --remove-orphans"),
                timeout=900,
            )
        except RuntimeError as exc:
            if "address already in use" in str(exc).lower():
                self._remote_port_owner_probe(target)
            self._collect_remote_startup_diagnostics(target, deploy_dir)
            raise self._friendly_remote_port_conflict(exc) from exc

        emit("verifying", "Polling backend health endpoint", 92)
        try:
            self._health_check(target, host=target.host)
        except RuntimeError as exc:
            self._collect_remote_readiness_diagnostics(target, deploy_dir)
            raise RuntimeError(
                f"{exc}. Remote Suite API readiness diagnostics were collected; "
                "review the [nmtk-suite-api] log lines for container state, "
                "startup logs, and in-container probe results."
            ) from exc

        emit("verifying", "Verifying Jupyter notebook readiness", 96)
        try:
            self._jupyter_health_check(target)
        except RuntimeError as exc:
            self._collect_remote_jupyter_diagnostics(target, deploy_dir)
            raise RuntimeError(
                "degraded optional capability: Jupyter is not ready for "
                "CNLStudio notebooks. Remote Jupyter diagnostics were collected; "
                "use Recover Jupyter to retry the saved deployment without "
                "removing notebook data. "
                f"{exc}"
            ) from exc
        self._remote_lava_capability_report(target, deploy_dir)

        engine_label = (target.container_engine or "docker").capitalize()
        emit("completed", f"{engine_label} backend deployed to {target.host}", 100)

    def _ensure_docker_permissions(self, target: DeploymentTarget) -> None:
        """Ensure the SSH user can reach the Docker daemon.

        Probes with ``docker ps -q``. If it fails (most likely because the
        user is not yet in the ``docker`` group), runs a one-liner to add them:

        - Password-auth targets: the SSH password doubles as the sudo password
          (same convention already accepted in deployment_user_bootstrap.py —
          the password is inlined in the remote command because SSH does not
          forward arbitrary local environment variables).
        - Key-auth targets: ``sudo -n`` (NOPASSWD) is tried; if that fails the
          user is left as-is and the compose command's ``sg docker`` wrapper
          will surface a clear error.

        After this call, ``_remote_compose_cmd`` wraps every compose invocation
        in ``sg docker </dev/null`` so a freshly-added group membership takes
        effect in the same SSH session without a re-login.
        """
        remote = f"{target.username}@{target.host}" if target.username else target.host
        with self._ssh_key_context(target) as key_path:
            ssh_args, ssh_env = self._ssh_base_args(target, key_path)
            env = dict(os.environ)
            env.update(ssh_env)

            # Plain probe — no sg wrapper here: sg blocks on a password prompt
            # when the user is not yet in the docker group, causing the full
            # 30-second timeout to be consumed in a non-interactive SSH session.
            probe_cmd = ssh_args + [remote, "docker ps -q"]
            probe = subprocess.run(
                probe_cmd,
                capture_output=True,
                text=True,
                check=False,
                timeout=30,
                env=env,
            )
            if probe.returncode == 0:
                return

            if target.auth_mode == "ssh_password":
                # The SSH login password doubles as the sudo password for the
                # same account (mirrors deployment_user_bootstrap.py convention).
                # Inline it in the remote command — SSH does not forward local
                # env vars, so passing it via the subprocess environment does
                # not work across the SSH boundary.
                password_ref = target.secret_refs.get("sshPassword", "")
                password = self._resolve_secret(password_ref) if password_ref else ""
                if password:
                    fix_remote = (
                        f"id -nG | grep -qw docker || "
                        f"printf '%s\\n' {shlex.quote(password)} | "
                        f'sudo -S usermod -aG docker "$USER"'
                    )
                    subprocess.run(
                        ssh_args + [remote, fix_remote],
                        capture_output=True,
                        text=True,
                        check=False,
                        timeout=30,
                        env=env,
                    )
            else:
                # Key-auth: try passwordless sudo (NOPASSWD); silently skip if
                # not available — the compose sg wrapper will surface a clear
                # Docker error rather than a cryptic permission message.
                fix_remote = (
                    "id -nG | grep -qw docker || "
                    'sudo -n usermod -aG docker "$USER" 2>/dev/null'
                )
                subprocess.run(
                    ssh_args + [remote, fix_remote],
                    capture_output=True,
                    text=True,
                    check=False,
                    timeout=30,
                    env=env,
                )

    def _ensure_engine_installed(self, target: DeploymentTarget) -> None:
        """Install `target.container_engine` on the remote host if missing.

        Runs on every remote deploy -- not just the optional root-bootstrap
        flow -- so switching engines on an already-provisioned target, or
        deploying with a self-managed account that was never bootstrapped,
        still gets the engine installed automatically whenever the account
        has usable sudo access.

        The `command -v` presence check runs before any sudo requirement,
        so an unprivileged-but-already-provisioned deploy account never
        hits the sudo gate just because it lacks elevation it doesn't
        actually need. If install isn't possible (no apt-get for Podman on
        a non-Debian host, or no usable sudo at all), the script produces
        an actionable error and this raises via `_ssh_run` before any
        compose command runs.

        Password resolution mirrors `_ensure_docker_permissions`: the SSH
        login password doubles as the sudo password for password-auth
        targets; key-auth targets rely on passwordless `sudo -n`.
        """
        engine = target.container_engine or "docker"
        script = f"""#!/usr/bin/env bash
set -euo pipefail
if command -v {shlex.quote(engine)} >/dev/null 2>&1; then
  echo "[nmtk-deploy] {engine} already installed"
  exit 0
fi
{sudo_elevation_preamble()}
{container_engine_install_commands(engine)}"""
        password = None
        if target.auth_mode == "ssh_password":
            password_ref = target.secret_refs.get("sshPassword", "")
            password = self._resolve_secret(password_ref) if password_ref else ""
        remote_cmd = encode_remote_script(
            script,
            env=({"NMTK_DEPLOY_SUDO_PASSWORD": password} if password else None),
        )
        self._ssh_run(target, remote_cmd)

    def _prepare_podman_runtime(self, target: DeploymentTarget) -> None:
        """Start and verify the rootless Podman API socket for Compose."""
        password = None
        if target.auth_mode == "ssh_password":
            password_ref = target.secret_refs.get("sshPassword", "")
            password = self._resolve_secret(password_ref) if password_ref else ""
        remote_cmd = encode_remote_script(
            podman_runtime_setup_script(),
            env=({"NMTK_DEPLOY_SUDO_PASSWORD": password} if password else None),
        )
        self._ssh_run(target, remote_cmd, timeout=120)

    def _remote_provider_preflight(
        self, target: DeploymentTarget, deploy_dir: str
    ) -> None:
        """Verify the remote engine, Compose provider, and merged config early."""
        engine = target.container_engine or "docker"
        provider_cmd = (
            f"cd {shlex.quote(deploy_dir)} && "
            f"{self._remote_engine_env(target)}"
            f"{engine} info >/dev/null && {engine} compose version"
        )
        try:
            self._ssh_run(target, provider_cmd, timeout=60)
            self._ssh_run(
                target,
                self._remote_compose_cmd(deploy_dir, target, "config --quiet"),
                timeout=60,
            )
        except RuntimeError as exc:
            raise RuntimeError(
                "Remote container provider preflight failed before startup: "
                f"{exc}. Check the {engine} service, Compose provider, and "
                "rootless socket permissions, then retry."
            ) from exc

    @staticmethod
    def _legacy_compose_project(deploy_dir: str) -> str:
        """Return the directory-derived project name used by older deploys."""
        name = Path(deploy_dir.rstrip("/")).name
        if name in {"", ".", DockerDeploymentExecutor._REMOTE_COMPOSE_PROJECT}:
            return ""
        return re.sub(r"[^a-zA-Z0-9_-]+", "-", name).strip("-_")

    def _remote_cleanup_stale_projects(
        self, target: DeploymentTarget, deploy_dir: str
    ) -> None:
        """Remove only NMTK-labelled containers from current and legacy projects.

        The selected Compose provider cannot see containers left in the other
        runtime's namespace. Older deployments also used the deploy-directory
        basename as the project name before the executor pinned ``nmtk``.
        """
        legacy_project = self._legacy_compose_project(deploy_dir)
        projects = [self._REMOTE_COMPOSE_PROJECT]
        if legacy_project and legacy_project not in projects:
            projects.append(legacy_project)
        project_words = " ".join(shlex.quote(project) for project in projects)
        cleanup_script = f"""for runtime in podman docker; do
  command -v "$runtime" >/dev/null 2>&1 || continue
  for project in {project_words}; do
    ids="$(
      {{
        "$runtime" ps -aq --filter "label=com.docker.compose.project=$project"
        "$runtime" ps -aq --filter "label=io.podman.compose.project=$project"
      }} 2>/dev/null | awk 'NF' | sort -u
    )"
    [ -n "$ids" ] || continue
    echo "[nmtk-cleanup] runtime=$runtime project=$project removing labelled containers"
    printf '%s\\n' "$ids" | while IFS= read -r id; do
      [ -n "$id" ] && "$runtime" rm -f "$id" >/dev/null 2>&1 || true
    done
  done
done"""
        try:
            self._ssh_run(target, cleanup_script, timeout=120)
        except RuntimeError as exc:
            self._log(f"Stale NMTK container cleanup skipped: {exc}")

    def _remote_port_owner_probe(self, target: DeploymentTarget) -> None:
        """Log container labels and listeners for ports exposed to Flutter."""
        ports = " ".join(str(port) for port in self._REMOTE_CLIENT_PORTS)
        probe_script = f"""for port in {ports}; do
  echo "[nmtk-port-owner] tcp/$port"
  for runtime in podman docker; do
    command -v "$runtime" >/dev/null 2>&1 || continue
    "$runtime" ps -a --filter "publish=$port" --format 'runtime=$runtime id={{{{.ID}}}} name={{{{.Names}}}} ports={{{{.Ports}}}} docker_project={{{{.Label "com.docker.compose.project"}}}} podman_project={{{{.Label "io.podman.compose.project"}}}}' 2>/dev/null || true
  done
  if command -v ss >/dev/null 2>&1; then
    ss -ltnp "( sport = :$port )" 2>/dev/null || true
  fi
done"""
        try:
            self._ssh_run(target, probe_script, timeout=60)
        except Exception as exc:
            self._log(f"Remote port ownership probe skipped: {exc}")

    def _collect_remote_startup_diagnostics(
        self, target: DeploymentTarget, deploy_dir: str
    ) -> None:
        """Stream bounded Compose state and Lava health details after failure."""
        self._log(
            "Remote startup failed; collecting Compose status and "
            "lava-backend health diagnostics."
        )
        for label, command in (
            ("compose ps -a", "ps -a"),
            (
                "compose dependency graph",
                "config --format json | python3 -c "
                + shlex.quote(
                    "import json,sys; "
                    "data=json.load(sys.stdin); "
                    "print(json.dumps({name: service.get('depends_on', {}) "
                    "for name, service in data.get('services', {}).items()}, "
                    "sort_keys=True))"
                ),
            ),
            ("lava-backend logs", "logs --tail=100 lava-backend"),
        ):
            try:
                self._log(f"[diagnostic] {label}")
                self._ssh_run(
                    target,
                    self._remote_compose_cmd(deploy_dir, target, command),
                    timeout=120,
                )
            except Exception as exc:
                self._log(f"[diagnostic] {label} unavailable: {exc}")
        self._remote_lava_capability_report(target, deploy_dir, degraded=True)

    def _collect_remote_readiness_diagnostics(
        self, target: DeploymentTarget, deploy_dir: str
    ) -> None:
        """Collect bounded diagnostics when Compose starts but Suite API is not ready."""
        self._log(
            "Remote Suite API readiness failed; collecting [nmtk-suite-api] "
            "container state, logs, and direct probes."
        )
        for label, command in (
            ("compose ps -a", "ps -a"),
            ("suite_api logs", "logs --tail=200 suite_api"),
        ):
            try:
                self._log(f"[nmtk-suite-api] {label}")
                self._ssh_run(
                    target,
                    self._remote_compose_cmd(deploy_dir, target, command),
                    timeout=120,
                )
            except Exception as exc:
                self._log(f"[nmtk-suite-api] {label} unavailable: {exc}")

        inspect_format = (
            "name={{.Name}} status={{.State.Status}} running={{.State.Running}} "
            "started={{.State.StartedAt}} exit={{.State.ExitCode}} "
            "health={{json .State.Health}} healthcheck={{json .Config.Healthcheck}}"
        )
        port = target.backend_port or 9000
        probe_code = (
            "import urllib.request; "
            "response=urllib.request.urlopen("
            f"'http://127.0.0.1:{port}/api/suite/health', timeout=5); "
            "print('probe_status=%s probe_body=%s' % "
            "(response.status, response.read().decode('utf-8', errors='replace')))"
        )
        probe_script = f"""set +e
cd {shlex.quote(deploy_dir)}
for runtime in podman docker; do
  command -v "$runtime" >/dev/null 2>&1 || continue
  ids="$(
    {{
      "$runtime" ps -aq --filter "label=com.docker.compose.project={self._REMOTE_COMPOSE_PROJECT}" --filter "label=com.docker.compose.service=suite_api"
      "$runtime" ps -aq --filter "label=io.podman.compose.project={self._REMOTE_COMPOSE_PROJECT}" --filter "label=io.podman.compose.service=suite_api"
    }} 2>/dev/null | awk 'NF' | sort -u
  )"
  [ -n "$ids" ] || continue
  for id in $ids; do
    echo "[nmtk-suite-api] runtime=$runtime id=$id"
    "$runtime" inspect --format {shlex.quote(inspect_format)} "$id" 2>&1 || true
    "$runtime" exec "$id" python -c {shlex.quote(probe_code)} 2>&1 || true
  done
done
if command -v ss >/dev/null 2>&1; then
  echo "[nmtk-suite-api] host listener tcp/{port}"
  ss -ltnp "( sport = :{port} )" 2>&1 || true
fi
python3 -c {shlex.quote(probe_code)} 2>&1 || true
"""
        try:
            self._ssh_run(target, probe_script, timeout=120)
        except Exception as exc:
            self._log(f"[nmtk-suite-api] direct probes unavailable: {exc}")

    def _collect_remote_jupyter_diagnostics(
        self, target: DeploymentTarget, deploy_dir: str
    ) -> None:
        """Collect Jupyter-specific evidence after a remote readiness failure."""
        self._log(
            "Jupyter notebook readiness failed; collecting [nmtk-jupyter] "
            "Compose state, logs, configuration, and direct probes."
        )
        for label, command in (
            ("compose config", "config --format json"),
            ("compose ps -a", "ps -a jupyter-server"),
            ("jupyter-server logs", "logs --tail=200 jupyter-server"),
        ):
            try:
                self._log(f"[nmtk-jupyter] {label}")
                self._ssh_run(
                    target,
                    self._remote_compose_cmd(deploy_dir, target, command),
                    timeout=120,
                )
            except Exception as exc:
                self._log(f"[nmtk-jupyter] {label} unavailable: {exc}")

        inspect_format = (
            "name={{.Name}} status={{.State.Status}} running={{.State.Running}} "
            "started={{.State.StartedAt}} exit={{.State.ExitCode}} "
            "health={{json .State.Health}} healthcheck={{json .Config.Healthcheck}}"
        )
        probe_code = (
            "import urllib.request; "
            "response=urllib.request.urlopen('http://127.0.0.1:8008/api/status', timeout=5); "
            "print('probe_status=%s probe_body=%s' % "
            "(response.status, response.read().decode('utf-8', errors='replace')))"
        )
        probe_script = f"""set +e
for runtime in podman docker; do
  command -v "$runtime" >/dev/null 2>&1 || continue
  ids="$(
    {{
      "$runtime" ps -aq --filter "label=com.docker.compose.project={self._REMOTE_COMPOSE_PROJECT}" --filter "label=com.docker.compose.service=jupyter-server"
      "$runtime" ps -aq --filter "label=io.podman.compose.project={self._REMOTE_COMPOSE_PROJECT}" --filter "label=io.podman.compose.service=jupyter-server"
    }} 2>/dev/null | awk 'NF' | sort -u
  )"
  [ -n "$ids" ] || continue
  for id in $ids; do
    echo "[nmtk-jupyter] runtime=$runtime id=$id"
    "$runtime" inspect --format {shlex.quote(inspect_format)} "$id" 2>&1 || true
    "$runtime" exec "$id" python -c {shlex.quote(probe_code)} 2>&1 || true
  done
done
"""
        try:
            self._ssh_run(target, probe_script, timeout=120)
        except Exception as exc:
            self._log(f"[nmtk-jupyter] direct probes unavailable: {exc}")

    def _remote_lava_capability_report(
        self, target: DeploymentTarget, deploy_dir: str, *, degraded: bool = False
    ) -> None:
        """Report Lava health history and an in-container HTTP probe.

        Lava is optional for the core deployment, so this method is
        deliberately best-effort. It emits enough provider-neutral state to
        distinguish a failing HTTP endpoint from a stale/unsupported
        healthcheck implementation without turning a degraded capability into
        a deployment failure.
        """
        inspect_format = (
            "name={{.Name}} image={{.Image}} "
            "health={{json .State.Health}} "
            "healthcheck={{json .Config.Healthcheck}}"
        )
        probe_code = (
            "import urllib.request; "
            "response=urllib.request.urlopen('http://127.0.0.1:8012/health', timeout=5); "
            "print('probe_status=%s probe_body=%s' % "
            "(response.status, response.read().decode('utf-8', errors='replace')))"
        )
        report_script = f"""set +e
cd {shlex.quote(deploy_dir)}
for runtime in podman docker; do
  command -v "$runtime" >/dev/null 2>&1 || continue
  ids="$(
    {{
      "$runtime" ps -aq --filter "label=com.docker.compose.project={self._REMOTE_COMPOSE_PROJECT}" --filter "label=com.docker.compose.service=lava-backend"
      "$runtime" ps -aq --filter "label=io.podman.compose.project={self._REMOTE_COMPOSE_PROJECT}" --filter "label=com.docker.compose.service=lava-backend"
    }} 2>/dev/null | awk 'NF' | sort -u
  )"
  [ -n "$ids" ] || continue
  for id in $ids; do
    echo "[nmtk-lava] runtime=$runtime id=$id"
    "$runtime" inspect --format {shlex.quote(inspect_format)} "$id" 2>&1 || true
    "$runtime" exec "$id" python -c {shlex.quote(probe_code)} 2>&1 || true
  done
done"""
        prefix = "[degraded]" if degraded else "[diagnostic]"
        self._log(
            f"{prefix} Lava is optional for core startup; collecting its "
            "health status and direct probe result."
        )
        try:
            self._ssh_run(target, report_script, timeout=120)
        except Exception as exc:
            self._log(f"{prefix} Lava capability diagnostics unavailable: {exc}")

    def _remote_compose_cmd(
        self, deploy_dir: str, target: DeploymentTarget, subcommand: str
    ) -> str:
        """Build a remote `<engine> compose` command for the prod stack.

        Mirrors `make deploy-prod` (Makefile): both compose files via -f, and
        the two env vars the stack expects (LAUNCHER_CONTROL_PORT and a
        host-reachable JUPYTER_PUBLIC_URL). GRAFANA_ADMIN_PASSWORD comes from
        the remote .env seeded by `_init_remote_secrets`.

        Docker path: prefixed with ``sg docker`` so that a docker group
        membership added by ``_ensure_docker_permissions`` in the same deploy
        takes effect immediately — Linux only updates a process\'s group list
        at session start, so ``usermod -aG docker`` alone is not enough without
        a re-login. ``sg docker`` re-execs the shell with the group active.
        Guarded by ``getent group docker`` so it still works on hosts where
        the docker group does not exist (falls back to running compose
        directly, which fails with a clear Docker error rather than an
        opaque ``sg: invalid group name`` error).

        Podman path: rootless by design, no group/`sg` dance needed — runs
        `podman compose` directly.
        """
        engine = target.container_engine or "docker"
        host = target.host
        jupyter_url = f"http://{host}:8008/lab"
        compose_cmd = (
            f"cd {shlex.quote(deploy_dir)} && "
            f"LAUNCHER_CONTROL_PORT=8090 "
            f"JUPYTER_PUBLIC_URL={shlex.quote(jupyter_url)} "
            f"NMTK_IMAGE_TAG={shlex.quote(self._image_tag(target))} "
            f"{self._remote_engine_env(target)}"
            f"{engine} compose --project-name {self._REMOTE_COMPOSE_PROJECT} "
            f"-f docker-compose.yml -f docker-compose.prod.yml "
            f"-f docker-compose.remote.yml "
            f"{subcommand}"
        )
        if engine != "docker":
            return compose_cmd
        # Use sg to activate the docker group for this command so a
        # just-added group membership takes effect without a re-login.
        # </dev/null ensures sg gets EOF immediately if it prompts for a
        # group password (i.e. user not in group) instead of blocking the
        # SSH session for the full 30-minute compose timeout.
        # Falls back to running compose directly if the docker group doesn't
        # exist on the host (avoids 'sg: invalid group name' noise).
        return (
            f"if getent group docker > /dev/null 2>&1; then "
            f"sg docker -c {shlex.quote(compose_cmd)} </dev/null; "
            f"else {compose_cmd}; fi"
        )

    @staticmethod
    def _remote_engine_env(target: DeploymentTarget) -> str:
        if (target.container_engine or "docker") != "podman":
            return ""
        return (
            "XDG_RUNTIME_DIR=/run/user/$(id -u) "
            "DOCKER_HOST=unix:///run/user/$(id -u)/podman/podman.sock "
        )

    @staticmethod
    def _friendly_remote_port_conflict(error: RuntimeError) -> RuntimeError:
        """Turn a host bind failure into a recovery-oriented deployment error."""
        message = str(error)
        if "address already in use" not in message.lower():
            return error
        match = re.search(r"(?:tcp(?:4|6)?|:)\D*(\d{2,5})", message)
        port = match.group(1) if match else "the requested host port"
        return RuntimeError(
            f"Remote deployment could not bind host port {port}: it is already "
            "used by another service on the target host. NMTK-labelled containers "
            "are reclaimed automatically before startup; see the preceding "
            "[nmtk-port-owner] diagnostics for the remaining runtime, Compose "
            "project, or service owner. Internal worker ports are automatically "
            "kept private; only an unrelated service outside NMTK using port "
            f"{port} needs to be moved or stopped before retrying."
        )

    def _copy_manifests_to_remote(
        self, target: DeploymentTarget, deploy_dir: str
    ) -> None:
        """Copy only the compose files + monitoring config to the remote.

        This is the whole "source" the server needs for a pull-based deploy —
        a few KB, not the repo. Fails with an actionable error if the
        manifests are absent (e.g. a bundle that didn't ship them).
        """
        sources = [self._repo_root / name for name in self._REMOTE_MANIFESTS]
        missing = [str(p) for p in sources if not p.exists()]
        if missing:
            raise RuntimeError(
                "Deployment manifests not found: "
                + ", ".join(missing)
                + ". The app bundle must ship docker-compose.yml, "
                "docker-compose.prod.yml, and monitoring/."
            )
        remote = f"{target.username}@{target.host}" if target.username else target.host
        with self._ssh_key_context(target) as key_path:
            ssh_opts, extra_env = self._ssh_opts_str(target, key_path)
            rsync_env = dict(os.environ)
            rsync_env.update(extra_env)
            rsync_cmd = [
                self._resolve_tool("rsync"),
                "-a",
                "-e",
                ssh_opts,
                *[str(p) for p in sources],
                f"{remote}:{deploy_dir}/",
            ]
            result = subprocess.run(
                rsync_cmd,
                capture_output=True,
                text=True,
                check=False,
                timeout=120,
                env=rsync_env,
            )
            if result.returncode != 0:
                err = (
                    result.stderr.strip()
                    or result.stdout.strip()
                    or "manifest copy failed"
                )
                raise RuntimeError(
                    f"Failed to copy deployment manifests to remote: {err}"
                )

    def _resolve_remote_deploy_dir(self, target: DeploymentTarget) -> str:
        """Return the absolute remote directory to deploy into.

        If `target.install_root` is set, it's used as-is. Otherwise falls
        back to `~/nmtk-deploy` under the SSH user's own home directory —
        mirroring the Makefile's `DEPLOY_DIR ?= ~/nmtk-deploy` convention,
        which is always writable without root/sudo, unlike a system path
        such as `/opt/...` (root-owned 755 on standard Linux). Resolved here
        to a concrete absolute path (via `pwd`) in one SSH round trip so `~`
        never has to survive into a shell-quoted string later — `_init_remote_secrets`
        below applies shlex.quote() to deploy_dir, which would prevent `~`
        expansion if a literal tilde were passed through instead.
        """
        configured = (target.install_root or "").strip()
        remote_cmd = (
            f"mkdir -p {shlex.quote(configured)} && cd {shlex.quote(configured)} && pwd"
            if configured
            else "mkdir -p ~/nmtk-deploy && cd ~/nmtk-deploy && pwd"
        )
        remote = f"{target.username}@{target.host}" if target.username else target.host
        with self._ssh_key_context(target) as key_path:
            ssh_args, ssh_env = self._ssh_base_args(target, key_path)
            cmd = ssh_args + [remote, remote_cmd]
            env = dict(os.environ)
            env.update(ssh_env)
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                check=False,
                timeout=30,
                env=env,
            )
        resolved = result.stdout.strip()
        if result.returncode != 0 or not resolved:
            err = result.stderr.strip() or "mkdir failed on remote"
            raise self._friendly_deploy_dir_error(err, configured)
        return resolved

    def _friendly_deploy_dir_error(
        self, stderr: str, configured_install_root: str
    ) -> RuntimeError:
        """Turn a raw mkdir stderr string into an actionable error message."""
        if "Permission denied" in stderr:
            if configured_install_root:
                return RuntimeError(
                    f"Could not create deploy directory on remote: {stderr}. "
                    f"'{configured_install_root}' is not writable by this SSH user. "
                    "Leave the install root unset to use a safe default under the "
                    "user's home directory, or choose a path this SSH user already owns."
                )
            return RuntimeError(
                f"Could not create deploy directory on remote: {stderr}. "
                "The default deploy directory under the SSH user's home directory "
                "could not be created — check that this account has a valid home "
                "directory and isn't a restricted/no-home service account."
            )
        return RuntimeError(f"Could not create deploy directory on remote: {stderr}")

    def _init_remote_secrets(self, target: DeploymentTarget, deploy_dir: str) -> None:
        """Ensure remote .env file exists and contains required secrets."""
        quoted = shlex.quote(deploy_dir)
        init_cmd = (
            f"touch {quoted}/.env && "
            f"grep -q GRAFANA_ADMIN_PASSWORD {quoted}/.env || "
            f'echo "GRAFANA_ADMIN_PASSWORD=$(openssl rand -base64 32 2>/dev/null || head -c 32 /dev/urandom | base64)" >> {quoted}/.env'
        )
        self._ssh_run(target, init_cmd)

    def _ssh_run(
        self, target: DeploymentTarget, remote_cmd: str, timeout: int = 600
    ) -> None:
        """Run a remote command, streaming its output to the log channel.

        Popen + background-reader-thread + queue (rather than a blocking
        `subprocess.run`) so the long-running `docker compose pull`/`up` steps
        stream their real output line-by-line to the UI. Forwarding is
        throttled to at most one line per `_LOG_THROTTLE_SECONDS` because
        docker emits many lines fast and every forwarded line is a job-store
        disk write.
        """
        remote = f"{target.username}@{target.host}" if target.username else target.host
        with self._ssh_key_context(target) as key_path:
            ssh_args, ssh_env = self._ssh_base_args(target, key_path)
            cmd = ssh_args + [remote, remote_cmd]
            env = dict(os.environ)
            env.update(ssh_env)
            proc = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                env=env,
            )
            line_queue: "queue.Queue[str | None]" = queue.Queue()

            def _drain_stdout() -> None:
                assert proc.stdout is not None
                for line in iter(proc.stdout.readline, ""):
                    line_queue.put(line)
                line_queue.put(None)

            reader = threading.Thread(target=_drain_stdout, daemon=True)
            reader.start()

            # Keep only a bounded tail: enough for a useful failure message,
            # but docker build can emit thousands of lines we don't retain.
            output_lines: list[str] = []
            start = time.monotonic()
            last_forwarded = 0.0  # 0 => forward the very first line at once
            pending: str | None = None  # newest line not yet forwarded
            stream_closed = False
            try:
                while True:
                    now = time.monotonic()
                    if now - start > timeout:
                        proc.kill()
                        proc.wait()
                        raise RuntimeError(
                            f"Remote command timed out after {timeout}s: {remote_cmd}"
                        )
                    try:
                        item = line_queue.get(timeout=self._LOG_THROTTLE_SECONDS)
                    except queue.Empty:
                        pass
                    else:
                        if item is None:
                            stream_closed = True
                        else:
                            stripped = item.rstrip()
                            if stripped:
                                output_lines.append(stripped)
                                if len(output_lines) > 40:
                                    del output_lines[0]
                                pending = stripped

                    now = time.monotonic()
                    if (
                        pending is not None
                        and now - last_forwarded >= self._LOG_THROTTLE_SECONDS
                    ):
                        self._log(pending)
                        pending = None
                        last_forwarded = now
                    if stream_closed and proc.poll() is not None:
                        break
            finally:
                returncode = proc.wait()
            # Always surface the final line so the last step stays visible.
            if pending is not None:
                self._log(pending)
            if returncode != 0:
                err = "\n".join(output_lines[-20:]).strip() or "SSH command failed"
                raise RuntimeError(f"Remote command failed: {err}")

    def _ssh_base_args(
        self, target: DeploymentTarget, key_path: str | None
    ) -> tuple[list[str], dict[str, str]]:
        """Build the ssh argv prefix for this target (excluding the remote
        address and command). Resolves the target's stored password (if any)
        and delegates the actual argv construction to the target-agnostic
        `build_ssh_argv`, so that helper can also be used for one-off SSH
        sessions that don't have a `DeploymentTarget` (e.g. root bootstrap).
        """
        password = None
        if not key_path and target.auth_mode == "ssh_password":
            password_ref = target.secret_refs.get("sshPassword", "")
            password = self._resolve_secret(password_ref) if password_ref else ""
            if not password:
                raise RuntimeError("SSH password is required but could not be resolved")
        return build_ssh_argv(target.ssh_port, key_path=key_path, password=password)

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
        )
        if key_path:
            return f"{base} -o BatchMode=yes -i {key_path}", {}
        if target.auth_mode == "ssh_password":
            password_ref = target.secret_refs.get("sshPassword", "")
            password = self._resolve_secret(password_ref) if password_ref else ""
            if password:
                # Use SSHPASS env var + `sshpass -e` to keep the password out of
                # the process argument list (avoids ps/proc exposure). No
                # BatchMode=yes here — it disables the interactive password
                # prompt that sshpass needs to intercept, which would make
                # password auth fail unconditionally.
                return f"{self._resolve_tool('sshpass')} -e {base}", {
                    "SSHPASS": password
                }
        return f"{base} -o BatchMode=yes", {}

    @contextlib.contextmanager
    def _ssh_key_context(self, target: DeploymentTarget):  # type: ignore[return]  # mypy cannot infer Generator return type for contextmanager with conditional early return
        """Write the SSH private key to a temp file for the duration of the block."""
        if target.auth_mode == "ssh_key":
            key_ref = target.secret_refs.get("sshPrivateKey") or target.secret_refs.get(
                "privateKey", ""
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
                    last_err = f"HTTP {resp.status}"
            except Exception as exc:
                last_err = str(exc)
            time.sleep(5.0)
        raise RuntimeError(f"Backend health check timed out at {url}: {last_err}")

    def _jupyter_health_check(self, target: DeploymentTarget) -> None:
        """Require both the Suite API proxy and WebView-facing Jupyter endpoint.

        The first probe proves the Compose-network route from suite_api to the
        worker. The second proves that the URL handed to CNLStudio's embedded
        browser is reachable from this launcher client.
        """
        suite_url = f"http://{target.host}:{target.backend_port or 9000}/api/jupyter/health"
        public_url = f"http://{target.host}:8008/api/status"
        deadline = time.monotonic() + 120.0
        last_error = ""
        while time.monotonic() < deadline:
            try:
                with urllib.request.urlopen(suite_url, timeout=5.0) as response:
                    payload = response.read().decode("utf-8", errors="replace")
                if response.status != 200 or '"status":"ok"' not in payload.replace(" ", ""):
                    raise RuntimeError(
                        f"Suite API reported Jupyter unavailable: HTTP {response.status} {payload}"
                    )
                with urllib.request.urlopen(public_url, timeout=5.0) as response:
                    if response.status == 200:
                        return
                    raise RuntimeError(f"WebView Jupyter endpoint returned HTTP {response.status}")
            except Exception as exc:  # noqa: BLE001 - retry transient startup states
                last_error = str(exc)
            time.sleep(5.0)
        raise RuntimeError(
            f"Jupyter readiness timed out (internal {suite_url}; public {public_url}): {last_error}"
        )


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

    @contextlib.contextmanager
    def _kubectl_env_ctx(self, target: DeploymentTarget):  # type: ignore[return]  # mypy cannot infer Generator return type for contextmanager with conditional early return
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
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                check=False,
                timeout=60,
                env=env,
            )
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
        with self._kubectl_env_ctx(target) as env:
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
    """Return the correct ``DeploymentExecutor`` subclass for the given mode.

    Args:
        mode: One of ``"standalone"``, ``"docker"``, or ``"kubernetes"``.
        repo_root: Absolute path to the repository root used as the Docker
            Compose working directory and rsync source.
        secret_resolver: Optional callable that resolves secret reference
            strings (e.g. ``"ref:my-secret"``) to their plaintext values.

    Returns:
        A ``DeploymentExecutor`` instance ready to ``run()``.

    Raises:
        ValueError: If ``mode`` is not one of the supported values.
    """
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
