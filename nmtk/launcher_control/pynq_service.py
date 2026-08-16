"""PYNQ board lifecycle, provisioning, and runtime proxy behavior.

Imported by ``server.py`` right before ``LauncherControlState`` is defined, so
the ``from .server import ...`` below resolves against the partially
initialized module rather than re-entering it — the names it pulls in must
already be bound in ``server.py`` above that import line.
"""

from __future__ import annotations

import json
import os
import shlex
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any, Callable

from .provisioning_helpers import (
    build_pynq_agent_bundle,
    build_pynq_agent_match_pattern,
    build_pynq_agent_stop_command,
    build_pynq_user_space_agent_launch_command,
)
from .runtime_artifact import discover_neurochip_runtime_artifact
from .runtime_shared import (
    _build_password_askpass_env,
    _neurochip_module_root,
    _runtime_request_error_kind,
)
from .server import (
    DEFAULT_PYNQ_AUTH_MODE,
    PREFLIGHT_DEGRADED,
    PREFLIGHT_FAILED,
    PREFLIGHT_OK,
    PYNQ_AGENT_HEALTH_HEARTBEAT_AFTER_SECONDS,
    PYNQ_OVERLAY_UPLOAD_RECOVERY_MESSAGE,
    PYNQ_PREFLIGHT_RETRY_COUNT,
    PYNQ_PREFLIGHT_RETRY_DELAY_SECONDS,
    PYNQ_RUNTIME_LOG_TAIL_LINES,
    RuntimeRequestError,
    _describe_pynq_preflight,
    _inspect_staged_pynq_overlay_package,
    _is_benign_ssh_warning_line,
    _load_neurochip_launcher_runtime_contract,
    _pynq_user_space_upgrade_message,
    _resolve_pynq_agent_health_timeout,
    _resolve_pynq_preflight_timeout,
    _resolve_pynq_run_timeout,
    _resolved_pynq_runtime_api_url,
    _serialize_pynq_board,
    _ssh_failure_message,
)


#: Unix groups that own the PL device nodes on the stock PYNQ image
#: (``/dev/dri/card0`` is ``root:video``, ``/dev/dri/renderD128`` is
#: ``root:render``, both mode 0660). A user-space agent must be in both or it
#: cannot open the board it is running on.
PYNQ_DEVICE_GROUPS: tuple[str, ...] = ("video", "render")


class PynqServiceMixin:
    def _emit_pynq_terminal_log(
        self, board: dict[str, Any], message: str, *, stderr: bool = False
    ) -> None:
        stream = sys.stderr if stderr else sys.stdout
        board_label = str(
            board.get("displayName") or board.get("host") or board.get("id") or "pynq"
        )
        print(f"[pynq:{board_label}] {message}", file=stream, flush=True)

    def _prepare_ssh_invocation(
        self,
        board: dict[str, Any],
        *,
        copy_mode: bool = False,
    ) -> tuple[list[str], dict[str, str] | None, Callable[[], None] | None]:
        prefix: list[str] = []
        env: dict[str, str] | None = None
        cleanup: Callable[[], None] | None = None
        auth_mode = str(board.get("authMode", DEFAULT_PYNQ_AUTH_MODE))
        if auth_mode == "password":
            password = str(board.get("password") or "")
            if not password:
                raise RuntimeError(
                    "No SSH password is configured for this PYNQ board"
                )
            sshpass = shutil.which("sshpass")
            if sshpass is not None:
                prefix.extend([sshpass, "-p", password])
            else:
                env, cleanup = _build_password_askpass_env(
                    password=password,
                    env_key="NMTK_PYNQ_PASSWORD",
                    prefix="nmtk-pynq-askpass-",
                )
        command = ["scp"] if copy_mode else ["ssh"]
        port_flag = "-P" if copy_mode else "-p"
        command.extend(
            [
                "-o",
                "StrictHostKeyChecking=accept-new",
                "-o",
                "UserKnownHostsFile=/dev/null",
                port_flag,
                str(
                    board.get("sshPort")
                    or _load_neurochip_launcher_runtime_contract().pynq.ssh_port
                ),
            ]
        )
        if auth_mode == "password":
            command.extend(
                [
                    "-o",
                    "PreferredAuthentications=password",
                    "-o",
                    "PubkeyAuthentication=no",
                    "-o",
                    "NumberOfPasswordPrompts=1",
                ]
            )
        if auth_mode == "ssh_key":
            ssh_key_path = str(board.get("sshKeyPath") or "").strip()
            if not ssh_key_path:
                raise RuntimeError("SSH-key authentication requires sshKeyPath")
            command.extend(["-i", ssh_key_path])
        return prefix + command, env, cleanup

    def _run_ssh(self, board: dict[str, Any], remote_command: str) -> str:
        target = f"{board['username']}@{board['host']}"
        command, env, cleanup = self._prepare_ssh_invocation(board)
        command.extend([target, remote_command])
        self._emit_pynq_terminal_log(board, f"ssh -> {target}: {remote_command}")
        try:
            process = subprocess.Popen(
                command,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                env=env,
                stdin=subprocess.DEVNULL,
            )
            stdout_lines: list[str] = []
            stderr_lines: list[str] = []

            def _pump(stream: Any, sink: list[str], *, stderr: bool = False) -> None:
                for raw_line in iter(stream.readline, ""):
                    line = raw_line.rstrip()
                    if not line:
                        continue
                    sink.append(line)
                    self._emit_pynq_terminal_log(board, line, stderr=stderr)
                stream.close()

            stdout_thread = threading.Thread(
                target=_pump,
                args=(process.stdout, stdout_lines),
                name=f"pynq-ssh-stdout-{board['id']}",
            )
            stderr_thread = threading.Thread(
                target=_pump,
                args=(process.stderr, stderr_lines),
                kwargs={"stderr": True},
                name=f"pynq-ssh-stderr-{board['id']}",
            )
            stdout_thread.start()
            stderr_thread.start()
            return_code = process.wait()
            stdout_thread.join()
            stderr_thread.join()
        finally:
            if cleanup is not None:
                cleanup()
        if return_code != 0:
            message = _ssh_failure_message(stdout_lines, stderr_lines)
            raise RuntimeError(message)
        self._emit_pynq_terminal_log(board, "ssh step completed")
        return "\n".join(stdout_lines).strip()

    def _run_ssh_sudo(
        self,
        board: dict[str, Any],
        remote_command: str,
        *,
        timeout: float = 60.0,
    ) -> str:
        """Run one privileged command on the board using the board's own password.

        The password already authenticates every SSH call to this board, so this
        adds no new secret — only a broader command. It travels on the SSH
        session's stdin into ``sudo -S`` rather than in argv or the environment,
        so it never appears in the board's process list.
        """
        password = str(board.get("password") or "")
        if not password:
            raise RuntimeError("No SSH password is configured for this PYNQ board")
        target = f"{board['username']}@{board['host']}"
        command, env, cleanup = self._prepare_ssh_invocation(board)
        command.extend([target, f"sudo -S -p '' {remote_command}"])
        self._emit_pynq_terminal_log(board, f"ssh (sudo) -> {target}: {remote_command}")
        try:
            result = subprocess.run(
                command,
                capture_output=True,
                text=True,
                timeout=timeout,
                check=False,
                env=env,
                input=f"{password}\n",
            )
        finally:
            if cleanup is not None:
                cleanup()
        stdout_lines = [line for line in result.stdout.splitlines() if line.strip()]
        stderr_lines = [
            line
            for line in result.stderr.splitlines()
            if line.strip() and not _is_benign_ssh_warning_line(line.strip())
        ]
        for line in stdout_lines:
            self._emit_pynq_terminal_log(board, line)
        for line in stderr_lines:
            self._emit_pynq_terminal_log(board, line, stderr=True)
        if result.returncode != 0:
            raise RuntimeError(_ssh_failure_message(stdout_lines, stderr_lines))
        self._emit_pynq_terminal_log(board, "sudo step completed")
        return "\n".join(stdout_lines).strip()

    def _ensure_pynq_device_group_access(self, board: dict[str, Any]) -> None:
        """Give the agent user read access to the PL device nodes.

        A user-space agent runs as the SSH user, but ``/dev/dri/card0`` and
        ``/dev/dri/renderD128`` ship as ``root:video`` / ``root:render`` mode 0660
        on the stock image — which nobody notices while everything runs as root.
        Without membership the agent starts, sees the device through XRT, and then
        fails to open it: "PYNQ device probe failed: no programmable devices
        found". Membership applies to new login sessions, and the agent is always
        launched over a fresh SSH session after this, so one grant is enough.
        """
        try:
            groups = self._run_ssh(board, "id -nG").split()
        except RuntimeError as exc:
            self._emit_pynq_terminal_log(
                board, f"could not read group membership: {exc}", stderr=True
            )
            return
        missing = [group for group in PYNQ_DEVICE_GROUPS if group not in groups]
        if not missing:
            return
        self._emit_pynq_terminal_log(
            board,
            f"granting {board['username']} access to the PL device nodes "
            f"(adding to {', '.join(missing)})",
        )
        try:
            self._run_ssh_sudo(
                board,
                f"usermod -aG {','.join(missing)} {shlex.quote(str(board['username']))}",
            )
        except RuntimeError as exc:
            # Not fatal: the agent still starts, it just cannot open the device.
            # Say so here, or the only symptom is a device-probe failure that
            # looks like a hardware fault.
            self._emit_pynq_terminal_log(
                board,
                "could not grant device access, so the board will report no "
                f"programmable devices until {board['username']} joins the "
                f"{', '.join(missing)} group(s): {exc}",
                stderr=True,
            )

    def _remote_pynq_install_status_path(self, board: dict[str, Any]) -> str:
        return str(
            board.get("remoteInstallStatusPath")
            or _load_neurochip_launcher_runtime_contract().pynq.install_status_path_for(
                str(board["remoteInstallRoot"])
            )
        )

    def _read_remote_pynq_install_status(self, board: dict[str, Any]) -> dict[str, Any]:
        raw = self._run_ssh(
            board,
            f"cat {self._remote_pynq_install_status_path(board)}",
        )
        try:
            decoded = json.loads(raw)
        except json.JSONDecodeError as exc:
            raise RuntimeError(
                f"Remote install status is not valid JSON: {raw}"
            ) from exc
        if not isinstance(decoded, dict):
            raise RuntimeError("Remote install status must decode to an object")
        return decoded

    def _wait_for_board_agent_health(
        self,
        board: dict[str, Any],
        timeout: float | None = None,
    ) -> None:
        effective_timeout = (
            _resolve_pynq_agent_health_timeout() if timeout is None else float(timeout)
        )
        base_url = _resolved_pynq_runtime_api_url(board).rstrip("/")
        health_url = f"{base_url}/health"
        self._emit_pynq_terminal_log(
            board,
            f"polling agent health at {health_url} (timeout {effective_timeout:.0f}s)",
        )
        start = time.monotonic()
        deadline = start + effective_timeout
        last_exc: Exception | None = None
        heartbeat_emitted = False
        while time.monotonic() < deadline:
            try:
                with urllib.request.urlopen(health_url, timeout=2.0) as resp:
                    if resp.status == 200:
                        self._emit_pynq_terminal_log(board, "agent health check passed")
                        return
            except Exception as exc:
                last_exc = exc
            elapsed = time.monotonic() - start
            if (
                not heartbeat_emitted
                and elapsed >= PYNQ_AGENT_HEALTH_HEARTBEAT_AFTER_SECONDS
            ):
                self._emit_pynq_terminal_log(
                    board, f"still polling /health ({elapsed:.0f}s elapsed)"
                )
                heartbeat_emitted = True
            time.sleep(1.0)
        raise RuntimeError(
            f"Agent at {health_url} did not become healthy within {effective_timeout:.0f}s"
            + (f": {last_exc}" if last_exc else "")
        )

    def _emit_runtime_log_tail(
        self,
        board: dict[str, Any],
        install_status: dict[str, Any],
        *,
        lines: int = PYNQ_RUNTIME_LOG_TAIL_LINES,
    ) -> None:
        runtime_log_path = str(
            install_status.get("runtimeLogPath")
            or board.get("remoteRuntimeLogPath")
            or _load_neurochip_launcher_runtime_contract().pynq.runtime_log_path_for(
                str(board["remoteInstallRoot"])
            )
        )
        self._emit_pynq_terminal_log(
            board, f"fetching last {lines} lines of {runtime_log_path}"
        )
        try:
            tail = self._run_ssh(board, f"tail -n {int(lines)} {runtime_log_path}")
        except Exception as exc:  # noqa: BLE001
            self._emit_pynq_terminal_log(
                board,
                f"could not read remote runtime log at {runtime_log_path}: {exc}",
                stderr=True,
            )
            return
        for line in tail.splitlines() or [tail]:
            if line:
                self._emit_pynq_terminal_log(
                    board, f"runtime.log | {line}", stderr=True
                )

    def _build_remote_pynq_user_space_launch_command(
        self,
        *,
        agent_venv_path: str,
        pynq_python_path: str,
        install_status_path: str,
        overlay_dir: str,
        runtime_log_path: str,
        agent_executable_name: str,
    ) -> str:
        return build_pynq_user_space_agent_launch_command(
            agent_executable=f"{agent_venv_path}/bin/{agent_executable_name}",
            pynq_python_path=pynq_python_path,
            install_status_path=install_status_path,
            overlay_dir=overlay_dir,
            runtime_log_path=runtime_log_path,
        )

    def _run_ssh_detached(
        self,
        board: dict[str, Any],
        remote_command: str,
        *,
        ssh_timeout: float = 15.0,
    ) -> None:
        """Run an SSH command that starts a detached background process.

        sshd keeps the channel open until all its pipe fds reach EOF, which
        prevents the SSH client from exiting even after the remote shell exits.
        We tolerate this by killing the local SSH client after ssh_timeout seconds;
        the remote background process continues running independently.
        """
        target = f"{board['username']}@{board['host']}"
        command, env, cleanup = self._prepare_ssh_invocation(board)
        command.extend([target, remote_command])
        self._emit_pynq_terminal_log(
            board, f"ssh (detached) -> {target}: {remote_command}"
        )
        try:
            result = subprocess.run(
                command,
                capture_output=True,
                text=True,
                timeout=ssh_timeout,
                check=False,
                env=env,
                stdin=subprocess.DEVNULL,
            )
            if result.stdout.strip():
                self._emit_pynq_terminal_log(board, result.stdout.strip())
            if result.stderr.strip():
                self._emit_pynq_terminal_log(board, result.stderr.strip())
            if result.returncode != 0:
                stderr_lines = [
                    line.strip() for line in result.stderr.splitlines() if line.strip()
                ]
                non_benign_stderr = [
                    line
                    for line in stderr_lines
                    if not _is_benign_ssh_warning_line(line)
                ]
                if non_benign_stderr:
                    raise RuntimeError("\n".join(non_benign_stderr))
                stdout_lines = [
                    line.strip() for line in result.stdout.splitlines() if line.strip()
                ]
                if stdout_lines:
                    raise RuntimeError("\n".join(stdout_lines))
                # Name the exit code. A remote shell killed by a signal exits
                # non-zero with nothing on either stream, and reporting that as
                # plain success is how a restart that killed itself looked like a
                # restart that worked.
                self._emit_pynq_terminal_log(
                    board,
                    f"ssh step exited {result.returncode} with no output beyond benign "
                    "SSH warnings; proceeding to health check",
                )
                return
            self._emit_pynq_terminal_log(board, "ssh step completed")
        except subprocess.TimeoutExpired:
            self._emit_pynq_terminal_log(
                board,
                f"ssh client timed out after {ssh_timeout:.0f}s; "
                "background agent process was already started — proceeding to health check",
            )
        finally:
            if cleanup is not None:
                cleanup()

    def _restart_user_space_agent(
        self, board: dict[str, Any], install_status: dict[str, Any]
    ) -> None:
        agent_venv_path = str(
            install_status.get("agentVenvPath") or board["remoteVenvPath"]
        )
        # The interpreter the install actually settled on wins. The isolated
        # pynq-venv is only built when the board has no canonical stock-image
        # interpreter, so assuming it restarts a working board with a python that
        # does not exist — the agent comes back up, finds no pynq, and silently
        # reports simulator mode instead of hardware.
        pynq_python_path = str(
            install_status.get("effectivePynqPython")
            or f"{install_status.get('pynqVenvPath') or board['remotePynqVenvPath']}/bin/python"
        )
        runtime_log_path = str(
            install_status.get("runtimeLogPath")
            or board.get("remoteRuntimeLogPath")
            or _load_neurochip_launcher_runtime_contract().pynq.runtime_log_path_for(
                str(board["remoteInstallRoot"])
            )
        )
        install_status_path = self._remote_pynq_install_status_path(board)
        overlay_dir = str(board["remoteOverlayDir"])
        agent_executable_name = str(
            board.get("agentExecutableName")
            or _load_neurochip_launcher_runtime_contract().pynq.agent_executable_name
        )
        self._emit_pynq_terminal_log(
            board,
            f"restarting user-space agent with NEUROCHIP_PYNQ_OVERLAY_DIR={overlay_dir}",
        )
        agent_executable = f"{agent_venv_path}/bin/{agent_executable_name}"
        launch_command = self._build_remote_pynq_user_space_launch_command(
            agent_venv_path=agent_venv_path,
            pynq_python_path=pynq_python_path,
            install_status_path=install_status_path,
            overlay_dir=overlay_dir,
            runtime_log_path=runtime_log_path,
            agent_executable_name=agent_executable_name,
        )
        # Stop and start travel as two separate SSH commands on purpose. Sent as
        # one, the remote shell's own command line carries the agent path, `pkill
        # -f` matches it, and the stop step kills the shell that was about to run
        # the start step — the agent goes down and never comes back.
        self._run_ssh(
            board,
            build_pynq_agent_stop_command(agent_executable=agent_executable)
            + "; sleep 1",
        )
        # Before the launch, not after: group membership only reaches new login
        # sessions, and the launch below opens one.
        self._ensure_pynq_device_group_access(board)
        self._run_ssh_detached(board, launch_command)
        self._confirm_remote_pynq_agent_process(board, agent_executable)
        self._emit_pynq_terminal_log(
            board, "waiting for restarted agent to become healthy"
        )
        self._wait_for_board_agent_health(board)

    def _confirm_remote_pynq_agent_process(
        self, board: dict[str, Any], agent_executable: str
    ) -> None:
        """Fail immediately when the launch command left no process behind.

        Without this the only signal is a 120s health timeout followed by three
        45s retries, and the reported failure is "did not become healthy" — which
        reads as a slow board rather than a start that never happened.
        """
        pattern = build_pynq_agent_match_pattern(agent_executable)
        found = self._run_ssh(
            board,
            f"pgrep -f {shlex.quote(pattern)} >/dev/null 2>&1 && echo running || echo missing",
        )
        if "running" in found:
            return
        raise RuntimeError(
            "the agent process did not start on the board; see runtime.log below"
        )

    def _run_scp(
        self,
        board: dict[str, Any],
        local_path: Path,
        remote_path: str,
        *,
        recursive: bool = False,
    ) -> None:
        command, env, cleanup = self._prepare_ssh_invocation(board, copy_mode=True)
        if recursive:
            command.append("-r")
        target = f"{board['username']}@{board['host']}:{remote_path}"
        command.extend([str(local_path), target])
        self._emit_pynq_terminal_log(board, f"scp -> {target} from {local_path}")
        try:
            result = subprocess.run(
                command,
                capture_output=True,
                text=True,
                check=False,
                env=env,
                stdin=subprocess.DEVNULL,
            )
        finally:
            if cleanup is not None:
                cleanup()
        if result.returncode != 0:
            self._emit_pynq_terminal_log(
                board,
                result.stderr.strip() or result.stdout.strip() or "scp command failed",
                stderr=True,
            )
            raise RuntimeError(
                result.stderr.strip() or result.stdout.strip() or "scp command failed"
            )
        self._emit_pynq_terminal_log(board, "scp step completed")

    def _runtime_json_request(
        self,
        board: dict[str, Any],
        method: str,
        path: str,
        payload: dict[str, Any] | None = None,
        *,
        timeout: float = 15.0,
    ) -> dict[str, Any]:
        base_url = _resolved_pynq_runtime_api_url(board).rstrip("/")
        url = f"{base_url}{path}"
        headers = {"Content-Type": "application/json"}
        credential_ref = str(board.get("credentialRef") or "").strip()
        if credential_ref:
            headers["X-API-Key"] = credential_ref
        data = json.dumps(payload).encode("utf-8") if payload is not None else None
        request = urllib.request.Request(
            url,
            data=data,
            headers=headers,
            method=method,
        )
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                body = response.read().decode("utf-8")
                decoded = json.loads(body) if body else {}
                if not isinstance(decoded, dict):
                    raise RuntimeError(f"Unexpected runtime response from {url}")
                return decoded
        except urllib.error.HTTPError as exc:
            error_body = exc.read().decode("utf-8", errors="replace")
            self._emit_pynq_terminal_log(
                board,
                (
                    f"runtime request failed: {method} {url} returned HTTP {exc.code}"
                    + (f" with body: {error_body}" if error_body else "")
                ),
                stderr=True,
            )
            raise RuntimeRequestError(
                f"Runtime request failed for {method} {url}: HTTP {exc.code}"
                + (f" - {error_body}" if error_body else ""),
                kind="http",
                url=url,
                status_code=exc.code,
                response_body=error_body,
            ) from exc
        except (urllib.error.URLError, TimeoutError, socket.timeout) as exc:
            kind = _runtime_request_error_kind(exc)
            if kind == "timeout":
                detail = f"timed out after {timeout:.0f}s"
            else:
                detail = f"could not be reached: {exc}"
            self._emit_pynq_terminal_log(
                board,
                f"runtime request failed: {method} {url} {detail}",
                stderr=True,
            )
            raise RuntimeRequestError(
                (
                    f"Runtime request failed for {method} {url}: {detail}"
                    if kind != "timeout"
                    else f"Runtime request timed out for {method} {url} after {timeout:.0f}s"
                ),
                kind=kind,
                url=url,
            ) from exc

    def _apply_preflight_to_board(
        self,
        board_id: str,
        preflight: dict[str, Any],
        *,
        fallback_error_state: str = "error",
    ) -> dict[str, Any]:
        status = str(preflight.get("preflight_status") or "").strip().lower()
        message = str(preflight.get("preflight_message") or "").strip()
        runtime_mode = str(preflight.get("runtime_mode") or "").strip()
        overlay_assets = preflight.get("overlay_assets")
        board_state = fallback_error_state
        overlay_missing = isinstance(overlay_assets, dict) and not overlay_assets.get(
            "ready_for_hardware", False
        )
        if overlay_missing:
            board_state = "overlay_missing"
        elif status == PREFLIGHT_OK:
            board_state = "ready"
        elif status == PREFLIGHT_DEGRADED:
            board_state = "degraded_optional_capability"
        elif status == PREFLIGHT_FAILED:
            board_state = "preflight_failed"
        return self._update_pynq_board_fields(
            board_id,
            state=board_state,
            lastPreflightStatus=status,
            lastPreflightMessage=message,
            lastRuntimeMode=runtime_mode,
        )

    def test_pynq_board_connection(self, board_id: str) -> dict[str, Any]:
        board = self._get_pynq_board(board_id)
        self._emit_pynq_terminal_log(board, "testing SSH connectivity")
        self._run_ssh(board, "python3 --version")
        self._emit_pynq_terminal_log(board, "SSH connectivity succeeded")
        return _serialize_pynq_board(
            self._update_pynq_board_fields(
                board_id, state="reachable", lastPreflightMessage="SSH reachable"
            )
        )

    def fetch_pynq_board_preflight(
        self,
        board_id: str,
        *,
        request_timeout: float | None = None,
    ) -> dict[str, Any]:
        board = self._get_pynq_board(board_id)
        self._emit_pynq_terminal_log(board, "requesting runtime preflight")
        preflight = self._runtime_json_request(
            board,
            "GET",
            "/hardware/pynq/preflight",
            timeout=(
                _resolve_pynq_preflight_timeout()
                if request_timeout is None
                else float(request_timeout)
            ),
        )
        self._emit_pynq_terminal_log(
            board,
            _describe_pynq_preflight(preflight),
        )
        updated = self._apply_preflight_to_board(board_id, preflight)
        return {
            "board": _serialize_pynq_board(updated),
            "preflight": preflight,
        }

    def _refresh_pynq_board_preflight(self, board_id: str, *, stage: str) -> dict[str, Any]:
        board = self._get_pynq_board(board_id)
        request_timeout = _resolve_pynq_preflight_timeout()
        last_error: RuntimeRequestError | None = None
        for attempt in range(1, PYNQ_PREFLIGHT_RETRY_COUNT + 1):
            try:
                return self.fetch_pynq_board_preflight(
                    board_id,
                    request_timeout=request_timeout,
                )
            except RuntimeRequestError as exc:
                last_error = exc
                if exc.kind not in {"timeout", "unreachable"}:
                    raise
                if attempt >= PYNQ_PREFLIGHT_RETRY_COUNT:
                    break
                if exc.kind == "timeout":
                    self._emit_pynq_terminal_log(
                        board,
                        (
                            f"runtime preflight is still running after {request_timeout:.0f}s "
                            f"during {stage}; retrying ({attempt + 1}/{PYNQ_PREFLIGHT_RETRY_COUNT})"
                        ),
                    )
                else:
                    self._emit_pynq_terminal_log(
                        board,
                        (
                            f"runtime preflight could not reach the agent during {stage}; "
                            f"rechecking /health before retry ({attempt + 1}/{PYNQ_PREFLIGHT_RETRY_COUNT})"
                        ),
                    )
                    try:
                        self._wait_for_board_agent_health(
                            board,
                            timeout=min(
                                _resolve_pynq_agent_health_timeout(),
                                request_timeout,
                            ),
                        )
                    except RuntimeError as health_exc:
                        self._emit_pynq_terminal_log(
                            board,
                            f"/health was not stable during {stage}: {health_exc}",
                            stderr=True,
                        )
                time.sleep(PYNQ_PREFLIGHT_RETRY_DELAY_SECONDS)
        if last_error is not None:
            raise last_error
        raise RuntimeError(f"Runtime preflight refresh failed during {stage}")

    def fetch_pynq_board_status(self, board_id: str) -> dict[str, Any]:
        board = self._get_pynq_board(board_id)
        self._emit_pynq_terminal_log(board, "requesting runtime status")
        status = self._runtime_json_request(board, "GET", "/hardware/pynq/status")
        updated = self._update_pynq_board_fields(
            board_id,
            lastStatus=status,
            lastRuntimeMode=str(status.get("runtime_mode") or "").strip(),
        )
        return {"board": _serialize_pynq_board(updated), "status": status}

    def _build_local_pynq_bundle(
        self, board: dict[str, Any], bundle_dir: Path
    ) -> dict[str, Any]:
        neurochip_root = _neurochip_module_root()
        artifact_directory = str(os.getenv("NMTK_NEUROCHIP_ARTIFACT_DIR") or "").strip()
        wheel_path = None
        if artifact_directory:
            wheel_path = discover_neurochip_runtime_artifact(
                Path(artifact_directory)
            ).wheel_path

        overlay_version = str(board.get("overlayVersion") or "dev")
        return build_pynq_agent_bundle(
            bundle_dir,
            overlay_version=overlay_version,
            repo_root=neurochip_root,
            wheel_path=wheel_path,
            install_root=str(board["remoteInstallRoot"]),
            agent_venv_path=str(board["remoteVenvPath"]),
            pynq_venv_path=str(board["remotePynqVenvPath"]),
            overlay_dir=str(board["remoteOverlayDir"]),
            service_name=str(board["remoteServiceName"]),
            agent_executable_name=str(board["agentExecutableName"]),
            install_status_path=str(board["remoteInstallStatusPath"]),
            runtime_log_path=str(board["remoteRuntimeLogPath"]),
        )

    def _inspect_local_pynq_overlay_package(self) -> dict[str, Any]:
        artifact_root = str(os.getenv("NMTK_NEUROCHIP_ARTIFACT_DIR") or "").strip()
        candidates = _load_neurochip_launcher_runtime_contract().pynq.overlay_staging_candidates(
            _neurochip_module_root(),
            Path(artifact_root) if artifact_root else None,
        )
        # Report the first complete package. Falling back on `ready` rather than
        # on directory existence matters in the container, where the module root
        # resolves to a path that simply is not there — reporting *its* issues
        # would tell the user to stage files into a directory the image never
        # ships, instead of using the overlay it already carries.
        inspected = [
            _inspect_staged_pynq_overlay_package(candidate)
            for candidate in candidates
        ]
        for result in inspected:
            if bool(result.get("ready", False)):
                return result
        # Nothing is usable, so this becomes the failure the user reads. Prefer a
        # candidate that actually exists on disk: its issues name the real defect
        # (a malformed manifest, a truncated bitstream) instead of "directory not
        # found" for the module root, which in the container never exists and
        # sends the user off to update a backend that is already current.
        for result in inspected:
            if Path(str(result["stagingDir"])).exists():
                return result
        return inspected[0]

    def provision_pynq_board(self, board_id: str) -> dict[str, Any]:
        board = self._update_pynq_board_fields(board_id, state="provisioning")
        self._emit_pynq_terminal_log(board, "starting runtime provisioning")
        install_status: dict[str, Any] = {}
        install_mode = "unknown"
        install_script_started = False
        try:
            with tempfile.TemporaryDirectory(prefix="pynq-agent-bundle-") as tmp_dir:
                bundle_dir = Path(tmp_dir) / "bundle"
                bundle_dir.mkdir(parents=True, exist_ok=True)
                self._emit_pynq_terminal_log(board, "building local PYNQ agent bundle")
                self._build_local_pynq_bundle(board, bundle_dir)
                remote_bundle_parent = "/tmp"
                remote_bundle_dir = f"{remote_bundle_parent}/{bundle_dir.name}"
                self._emit_pynq_terminal_log(
                    board,
                    f"preparing remote install directories at {board['remoteInstallRoot']}",
                )
                self._run_ssh(
                    board,
                    (
                        f"mkdir -p {board['remoteInstallRoot']} {board['remoteOverlayDir']} "
                        f"&& rm -rf {remote_bundle_dir}"
                    ),
                )
                self._emit_pynq_terminal_log(
                    board, f"uploading provisioning bundle to {remote_bundle_parent}"
                )
                self._run_scp(board, bundle_dir, remote_bundle_parent, recursive=True)
                # The install script starts the agent itself when it falls back to
                # a user-space install, so the grant has to land first to reach
                # that process.
                self._ensure_pynq_device_group_access(board)
                self._emit_pynq_terminal_log(board, "running remote install script")
                install_script_started = True
                self._run_ssh(
                    board,
                    " ".join(
                        [
                            f"INSTALL_ROOT={board['remoteInstallRoot']}",
                            f"AGENT_VENV_PATH={board['remoteVenvPath']}",
                            f"PYNQ_VENV_PATH={board['remotePynqVenvPath']}",
                            f"OVERLAY_DIR={board['remoteOverlayDir']}",
                            f"SERVICE_NAME={board['remoteServiceName']}",
                            f"AGENT_EXECUTABLE_NAME={board['agentExecutableName']}",
                            f"INSTALL_STATUS_PATH={board['remoteInstallStatusPath']}",
                            f"RUNTIME_LOG_PATH={board['remoteRuntimeLogPath']}",
                            f"bash {remote_bundle_dir}/install-pynq-agent.sh",
                        ]
                    ),
                )
                install_status = self._read_remote_pynq_install_status(board)
                install_mode = (
                    str(install_status.get("installMode") or "unknown").strip()
                    or "unknown"
                )
                self._emit_pynq_terminal_log(
                    board,
                    f"runtime install mode resolved to {install_mode}",
                )
            self._update_pynq_board_fields(board_id, state="runtime_installed")
            self._emit_pynq_terminal_log(
                board, "runtime install finished; fetching preflight"
            )
            result = self._refresh_pynq_board_preflight(
                board_id,
                stage="runtime provisioning",
            )
            board_state = str(result.get("board", {}).get("state") or "").strip()
            if board_state == "overlay_missing":
                self._emit_pynq_terminal_log(
                    board,
                    "runtime installed successfully; overlay assets are still missing, so the board is not hardware-ready yet",
                )
            if install_mode == "user-space":
                guidance = _pynq_user_space_upgrade_message(
                    str(board.get("username") or "")
                )
                prior_message = str(
                    result["board"].get("lastPreflightMessage") or ""
                ).strip()
                updated = self._update_pynq_board_fields(
                    board_id,
                    lastPreflightMessage=(
                        f"{prior_message} {guidance}".strip()
                        if prior_message
                        else guidance
                    ),
                )
                result["board"] = _serialize_pynq_board(updated)
                preflight = result.get("preflight")
                if isinstance(preflight, dict):
                    preflight["preflight_message"] = updated["lastPreflightMessage"]
            result["installStatus"] = install_status
            return result
        except Exception as exc:  # noqa: BLE001
            if install_script_started:
                self._emit_runtime_log_tail(board, install_status)
            self._emit_pynq_terminal_log(
                board, f"runtime provisioning failed: {exc}", stderr=True
            )
            updated = self._update_pynq_board_fields(
                board_id,
                state="provision_failed",
                lastPreflightMessage=str(exc),
            )
            return {"board": _serialize_pynq_board(updated), "error": str(exc)}

    def install_pynq_overlay_assets(self, board_id: str) -> dict[str, Any]:
        board = self._get_pynq_board(board_id)
        self._emit_pynq_terminal_log(board, "starting overlay asset install")
        overlay_package = self._inspect_local_pynq_overlay_package()
        bitstream = Path(str(overlay_package["bitstreamPath"]))
        hwh = Path(str(overlay_package["hwhPath"]))
        manifest = Path(str(overlay_package["manifestPath"]))
        if not bool(overlay_package.get("ready", False)):
            issues = overlay_package.get("issues", [])
            issues_text = (
                "; ".join(str(issue) for issue in issues)
                if isinstance(issues, list) and issues
                else "staged overlay package is incomplete"
            )
            # The overlay ships with the backend, so this is a broken install
            # rather than something the user forgot to do — telling them to go
            # synthesise a bitstream would be wrong and unactionable. Say which
            # kind of broken it is: "files are absent" and "the files are there
            # but their manifest is rejected" send the user looking in very
            # different places, and the second one used to be reported as the first.
            files_present = all(
                bool(overlay_package.get(key))
                for key in ("bitstreamExists", "hwhExists", "manifestPresent")
            )
            if files_present:
                summary = (
                    "The PYNQ overlay that ships with the backend does not match "
                    "the contract this launcher expects, so installing it could "
                    "leave the board running an overlay that cannot compute. "
                    "Update the backend to get a matching overlay."
                )
            else:
                summary = (
                    "The PYNQ overlay package that ships with the backend is "
                    "missing or incomplete, so there is nothing to install on "
                    "the board. Update the backend to restore it."
                )
            message = (
                f"{summary} "
                f"Looked in {overlay_package['stagingDir']}. Details: {issues_text}"
            )
            self._emit_pynq_terminal_log(
                board,
                message,
                stderr=True,
            )
            updated = self._update_pynq_board_fields(
                board_id,
                state="overlay_missing",
                lastPreflightMessage=message,
            )
            return {
                "board": _serialize_pynq_board(updated),
                "localOverlayPackage": overlay_package,
            }
        self._emit_pynq_terminal_log(
            board,
            f"using staged overlay package from {overlay_package['stagingDir']}",
        )
        self._emit_pynq_terminal_log(
            board, f"ensuring remote overlay dir {board['remoteOverlayDir']}"
        )
        self._run_ssh(board, f"mkdir -p {board['remoteOverlayDir']}")
        self._emit_pynq_terminal_log(board, "uploading snn_overlay.bit")
        self._run_scp(board, bitstream, f"{board['remoteOverlayDir']}/snn_overlay.bit")
        self._emit_pynq_terminal_log(board, "uploading snn_overlay.hwh")
        self._run_scp(board, hwh, f"{board['remoteOverlayDir']}/snn_overlay.hwh")
        self._emit_pynq_terminal_log(board, "uploading overlay_manifest.json")
        self._run_scp(
            board, manifest, f"{board['remoteOverlayDir']}/overlay_manifest.json"
        )
        self._emit_pynq_terminal_log(
            board, "overlay upload finished; checking install mode"
        )
        try:
            install_status = self._read_remote_pynq_install_status(board)
        except Exception:
            install_status = {}
        install_mode = str(install_status.get("installMode") or "unknown").strip()
        restart_warning: str | None = None
        if install_mode == "user-space":
            try:
                self._restart_user_space_agent(board, install_status)
            except RuntimeError as exc:
                restart_warning = str(exc)
                self._emit_runtime_log_tail(board, install_status)
                self._emit_pynq_terminal_log(
                    board,
                    (
                        f"user-space agent restart did not become healthy: {exc}; "
                        "overlay files are uploaded — restart the board or run "
                        "restart-runtime manually"
                    ),
                    stderr=True,
                )
        self._emit_pynq_terminal_log(board, "fetching preflight")
        try:
            result = self._refresh_pynq_board_preflight(
                board_id,
                stage="overlay install",
            )
        except Exception as exc:
            if install_mode != "user-space":
                raise
            if restart_warning is None:
                restart_warning = (
                    "Follow-up preflight could not reach the runtime after overlay upload: "
                    f"{exc}"
                )
                self._emit_pynq_terminal_log(
                    board,
                    (
                        "readiness refresh after overlay upload did not complete: "
                        f"{exc}; {PYNQ_OVERLAY_UPLOAD_RECOVERY_MESSAGE}"
                    ),
                    stderr=True,
                )
            updated = self._update_pynq_board_fields(
                board_id,
                state="degraded_optional_capability",
                lastPreflightStatus=PREFLIGHT_DEGRADED,
                lastPreflightMessage=PYNQ_OVERLAY_UPLOAD_RECOVERY_MESSAGE,
            )
            result = {
                "board": _serialize_pynq_board(updated),
                "preflight": {
                    "preflight_status": PREFLIGHT_DEGRADED,
                    "preflight_message": PYNQ_OVERLAY_UPLOAD_RECOVERY_MESSAGE,
                    "runtime_mode": str(updated.get("lastRuntimeMode") or "unknown"),
                },
            }
        result["localOverlayPackage"] = overlay_package
        if restart_warning is not None:
            result["overlayRestartWarning"] = restart_warning
        return result

    def restart_pynq_runtime(self, board_id: str) -> dict[str, Any]:
        board = self._get_pynq_board(board_id)
        install_status = self._read_remote_pynq_install_status(board)
        install_mode = (
            str(install_status.get("installMode") or "unknown").strip() or "unknown"
        )
        if install_mode == "user-space":
            self._emit_pynq_terminal_log(board, "restarting user-space runtime")
            try:
                self._restart_user_space_agent(board, install_status)
                result = self._refresh_pynq_board_preflight(
                    board_id, stage="user-space runtime restart"
                )
            except RuntimeError as exc:
                self._emit_runtime_log_tail(board, install_status)
                message = f"Could not restart the user-space runtime: {exc}"
                updated = self._update_pynq_board_fields(
                    board_id,
                    state="degraded_optional_capability",
                    lastPreflightStatus=PREFLIGHT_DEGRADED,
                    lastPreflightMessage=message,
                )
                return {
                    "board": _serialize_pynq_board(updated),
                    "warning": message,
                    "installStatus": install_status,
                }
            result["installStatus"] = install_status
            return result
        self._emit_pynq_terminal_log(
            board, f"restarting systemd service {board['remoteServiceName']}.service"
        )
        self._run_ssh(
            board, f"sudo systemctl restart {board['remoteServiceName']}.service"
        )
        self._emit_pynq_terminal_log(
            board, "waiting for restarted systemd service to become healthy"
        )
        self._wait_for_board_agent_health(board)
        self._emit_pynq_terminal_log(
            board, "runtime restart completed; fetching preflight"
        )
        result = self._refresh_pynq_board_preflight(board_id, stage="runtime restart")
        result["installStatus"] = install_status
        return result

    def proxy_pynq_deploy(
        self, board_id: str, payload: dict[str, Any]
    ) -> dict[str, Any]:
        board = self._get_pynq_board(board_id)
        response = self._runtime_json_request(
            board, "POST", "/hardware/pynq/deploy", payload, timeout=120.0
        )
        return response

    def proxy_pynq_verify(
        self, board_id: str, payload: dict[str, Any]
    ) -> dict[str, Any]:
        board = self._get_pynq_board(board_id)
        return self._runtime_json_request(
            board, "POST", "/hardware/pynq/verify", payload
        )

    def proxy_pynq_run(self, board_id: str, payload: dict[str, Any]) -> dict[str, Any]:
        board = self._get_pynq_board(board_id)
        return self._runtime_json_request(
            board, "POST", "/hardware/pynq/run", payload,
            timeout=_resolve_pynq_run_timeout(),
        )

    def proxy_pynq_runtime_status(self, board_id: str) -> dict[str, Any]:
        board = self._get_pynq_board(board_id)
        return self._runtime_json_request(board, "GET", "/hardware/pynq/status")
