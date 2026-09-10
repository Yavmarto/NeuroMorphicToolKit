"""Docker and Podman launcher deployment executor."""

from __future__ import annotations

import contextlib
import os
import re
import shlex
import tempfile
import time
from collections.abc import Generator
from pathlib import Path

from .deployment_contracts import (
    DeploymentTarget,
    container_engine_install_commands,
    encode_remote_script,
    podman_runtime_setup_script,
    redact_text,
    sudo_elevation_preamble,
)
from .deployment_executor_base import (
    DeploymentExecutor,
    LogCallback,
    ProgressCallback,
    _bundled_or_path,
    build_ssh_argv,
)
from .deployment_preflight import run_preflight


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
            self._deploy_local(target, emit, clean_install=clean_install)
        elif target.target_type == "remote_host":
            self._deploy_remote(target, emit, clean_install=clean_install)
        else:
            raise RuntimeError(
                f"Docker mode does not support target type: {target.target_type!r}"
            )

    # ------------------------------------------------------------------
    # Local deployment
    # ------------------------------------------------------------------

    def _deploy_local(
        self,
        target: DeploymentTarget,
        emit: ProgressCallback,
        clean_install: bool = False,
    ) -> None:
        engine = target.container_engine or "docker"
        docker = _bundled_or_path(engine)
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

    def _compose_down_local(
        self, docker: str, target: DeploymentTarget, volumes: bool = False
    ) -> None:
        cmd = [docker, "compose", "down", "--remove-orphans"]
        if volumes:
            cmd.append("-v")
        result = self._commands.run(
            cmd,
            cwd=str(self._repo_root),
            capture_output=True,
            text=True,
            check=False,
            timeout=300,
            env=self._compose_env(target),
        )
        self._require_not_timed_out(
            result, operation="docker compose down", timeout=300
        )

    def _compose_build_local(self, docker: str, target: DeploymentTarget) -> None:
        cmd = [docker, "compose", "build", "--parallel"]
        result = self._commands.run(
            cmd,
            cwd=str(self._repo_root),
            capture_output=True,
            text=True,
            check=False,
            timeout=600,
            env=self._compose_env(target),
        )
        self._require_not_timed_out(
            result, operation="docker compose build", timeout=600
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
        result = self._commands.run(
            cmd,
            cwd=str(self._repo_root),
            capture_output=True,
            text=True,
            check=False,
            timeout=300,
            env=self._compose_env(target),
        )
        self._require_not_timed_out(result, operation="docker compose up", timeout=300)
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

    def _deploy_remote(
        self,
        target: DeploymentTarget,
        emit: ProgressCallback,
        clean_install: bool = False,
    ) -> None:
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
        self._remote_cleanup_stale_projects(
            target,
            deploy_dir,
            remove_volumes=clean_install,
        )

        emit("installing", "Stopping existing NMTK stack", 42)
        down_opts = "-v --remove-orphans" if clean_install else "--remove-orphans"
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
            probe = self._commands.run(
                probe_cmd,
                capture_output=True,
                text=True,
                check=False,
                timeout=30,
                env=env,
            )
            self._require_not_timed_out(
                probe, operation="remote Docker permission probe", timeout=30
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
                    update = self._commands.run(
                        ssh_args + [remote, fix_remote],
                        capture_output=True,
                        text=True,
                        check=False,
                        timeout=30,
                        env=env,
                    )
                    self._require_not_timed_out(
                        update,
                        operation="remote Docker group update",
                        timeout=30,
                    )
            else:
                # Key-auth: try passwordless sudo (NOPASSWD); silently skip if
                # not available — the compose sg wrapper will surface a clear
                # Docker error rather than a cryptic permission message.
                fix_remote = (
                    "id -nG | grep -qw docker || "
                    'sudo -n usermod -aG docker "$USER" 2>/dev/null'
                )
                update = self._commands.run(
                    ssh_args + [remote, fix_remote],
                    capture_output=True,
                    text=True,
                    check=False,
                    timeout=30,
                    env=env,
                )
                self._require_not_timed_out(
                    update,
                    operation="remote Docker group update",
                    timeout=30,
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
        self,
        target: DeploymentTarget,
        deploy_dir: str,
        *,
        remove_volumes: bool = False,
    ) -> None:
        """Remove only NMTK-labelled containers from current and legacy projects.

        The selected Compose provider cannot see containers left in the other
        runtime's namespace. Older deployments also used the deploy-directory
        basename as the project name before the executor pinned ``nmtk``.
        """
        legacy_project = self._legacy_compose_project(deploy_dir)
        projects = [self._REMOTE_COMPOSE_PROJECT, "nmtk-deploy", "deploy"]
        if legacy_project and legacy_project not in projects:
            projects.append(legacy_project)
        project_words = " ".join(shlex.quote(project) for project in projects)
        volume_cleanup = (
            """
    volumes="$(
      {
        "$runtime" volume ls -q --filter "label=com.docker.compose.project=$project"
        "$runtime" volume ls -q --filter "label=io.podman.compose.project=$project"
      } 2>/dev/null | awk 'NF' | sort -u
    )"
    if [ -n "$volumes" ]; then
      printf '%s\\n' "$volumes" | while IFS= read -r volume; do
        [ -n "$volume" ] && "$runtime" volume rm -f "$volume"
      done
    fi
"""
            if remove_volumes
            else ""
        )
        cleanup_script = f"""set -e
for runtime in podman docker; do
  command -v "$runtime" >/dev/null 2>&1 || continue
  "$runtime" info >/dev/null
  known_ids="$(
    "$runtime" ps -a --format '{{{{.ID}}}} {{{{.Names}}}}' |
      awk '$2 ~ /^(nmtk|nmtk-deploy|deploy)[_-](suite_api|neurosense-hw-worker|neurobench-runner-worker|neurochip-hw-worker|lava-backend|launcher-control|neurocnl-physics-worker|snn-mlir-compiler|jupyter-server)([-_][0-9]+)?$/ {{print $1}}'
  )"
  if [ -n "$known_ids" ]; then
    echo "[nmtk-cleanup] runtime=$runtime removing known NMTK containers"
    printf '%s\\n' "$known_ids" | while IFS= read -r id; do
      [ -n "$id" ] && "$runtime" rm -f "$id" >/dev/null
    done
  fi
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
      if [ -n "$id" ]; then
        "$runtime" rm -f "$id" >/dev/null
      fi
    done
{volume_cleanup}
  done
done"""
        try:
            self._ssh_run(target, cleanup_script, timeout=120)
        except RuntimeError as exc:
            raise RuntimeError(
                "Existing NMTK containers could not be reconciled safely "
                f"across Docker and Podman: {exc}"
            ) from exc

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
        except Exception as exc:  # noqa: BLE001 - probe is best-effort; logged below
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
            except Exception as exc:  # noqa: BLE001 - diagnostic remains best-effort
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
            except Exception as exc:  # noqa: BLE001 - diagnostics remain best-effort
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
        except Exception as exc:  # noqa: BLE001 - probe is best-effort; logged below
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
            except Exception as exc:  # noqa: BLE001 - diagnostics remain best-effort
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
        except Exception as exc:  # noqa: BLE001 - probe is best-effort; logged below
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
        except Exception as exc:  # noqa: BLE001 - capability report remains best-effort
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
            result = self._commands.run(
                rsync_cmd,
                capture_output=True,
                text=True,
                check=False,
                timeout=120,
                env=rsync_env,
            )
            self._require_not_timed_out(
                result, operation="deployment manifest copy", timeout=120
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
            result = self._commands.run(
                cmd,
                capture_output=True,
                text=True,
                check=False,
                timeout=30,
                env=env,
            )
        self._require_not_timed_out(
            result, operation="remote deploy directory preparation", timeout=30
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
        from .module_deployment_env import build_dotenv_sync_script

        quoted = shlex.quote(deploy_dir)
        init_cmd = (
            f"touch {quoted}/.env && "
            f"grep -q GRAFANA_ADMIN_PASSWORD {quoted}/.env || "
            f'echo "GRAFANA_ADMIN_PASSWORD=$(openssl rand -base64 32 2>/dev/null || head -c 32 /dev/urandom | base64)" >> {quoted}/.env'
        )
        self._ssh_run(target, init_cmd)
        module_env = dict(target.module_environment)
        for key, secret_ref in target.module_secret_refs.items():
            if not secret_ref:
                continue
            secret = self._resolve_secret(secret_ref)
            if secret:
                module_env[str(key)] = secret
        if module_env:
            self._ssh_run(
                target,
                build_dotenv_sync_script(deploy_dir, module_env),
            )

    def _ssh_run(
        self, target: DeploymentTarget, remote_cmd: str, timeout: int = 600
    ) -> None:
        """Run a remote command, streaming its output to the log channel.

        Popen + background-reader-thread + queue (rather than a blocking
        `subprocess.run`) so the long-running `docker compose pull`/`up` steps
        stream every real output line to the UI while the timeout remains
        enforceable.
        """
        remote = f"{target.username}@{target.host}" if target.username else target.host
        safe_remote_cmd = remote_cmd
        sensitive_values: list[str] = []
        for secret_ref in target.secret_refs.values():
            if not secret_ref:
                continue
            try:
                secret = self._resolve_secret(secret_ref)
            except Exception:  # noqa: BLE001, S112 - redaction must never block setup
                continue
            if secret:
                sensitive_values.append(secret)
                safe_remote_cmd = safe_remote_cmd.replace(secret, "<redacted>")
        self._log(f"$ {redact_text(safe_remote_cmd)}")
        with self._ssh_key_context(target) as key_path:
            ssh_args, ssh_env = self._ssh_base_args(target, key_path)
            cmd = ssh_args + [remote, remote_cmd]
            env = dict(os.environ)
            env.update(ssh_env)
            result = self._commands.stream(
                cmd,
                env=env,
                timeout=timeout,
                on_line=self._log,
                sensitive_values=sensitive_values,
            )
            if result.timed_out:
                self._log(f"[client: command timed out after {timeout}s]")
                raise RuntimeError(
                    f"Remote command timed out after {timeout}s: {safe_remote_cmd}"
                )
            if result.returncode != 0:
                self._log(f"[client: command exited {result.returncode}]")
                output_lines = result.stdout.splitlines()
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
    def _ssh_key_context(
        self, target: DeploymentTarget
    ) -> Generator[str | None, None, None]:
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
                with self._open_url(url, timeout=5.0) as resp:
                    if resp.status == 200:
                        return
                    last_err = f"HTTP {resp.status}"
            except Exception as exc:  # noqa: BLE001 - capture last error across retries
                last_err = str(exc)
            time.sleep(5.0)
        raise RuntimeError(f"Backend health check timed out at {url}: {last_err}")

    def _jupyter_health_check(self, target: DeploymentTarget) -> None:
        """Require both the Suite API proxy and WebView-facing Jupyter endpoint.

        The first probe proves the Compose-network route from suite_api to the
        worker. The second proves that the URL handed to CNLStudio's embedded
        browser is reachable from this launcher client.
        """
        suite_url = (
            f"http://{target.host}:{target.backend_port or 9000}/api/jupyter/health"
        )
        public_url = f"http://{target.host}:8008/api/status"
        deadline = time.monotonic() + 120.0
        last_error = ""
        while time.monotonic() < deadline:
            try:
                with self._open_url(suite_url, timeout=5.0) as response:
                    payload = response.read().decode("utf-8", errors="replace")
                if response.status != 200 or '"status":"ok"' not in payload.replace(
                    " ", ""
                ):
                    raise RuntimeError(
                        f"Suite API reported Jupyter unavailable: HTTP {response.status} {payload}"
                    )
                with self._open_url(public_url, timeout=5.0) as response:
                    if response.status == 200:
                        return
                    raise RuntimeError(
                        f"WebView Jupyter endpoint returned HTTP {response.status}"
                    )
            except Exception as exc:  # noqa: BLE001 - retry transient startup states
                last_error = str(exc)
            time.sleep(5.0)
        raise RuntimeError(
            f"Jupyter readiness timed out (internal {suite_url}; public {public_url}): {last_error}"
        )
