"""PYNQ provisioning, restart, preflight, and status coordination."""

from __future__ import annotations

import json
import os
import shlex
import subprocess
import tempfile
import time
import urllib.request
from collections.abc import Callable
from pathlib import Path
from typing import Any, Protocol

from .hardware_models import (
    _describe_pynq_preflight,
    _inspect_staged_pynq_overlay_package,
    _is_benign_ssh_warning_line,
    _load_neurochip_launcher_runtime_contract,
    _pynq_user_space_upgrade_message,
    _resolve_pynq_agent_health_timeout,
    _resolve_pynq_preflight_timeout,
    _resolved_pynq_runtime_api_url,
)
from .provisioning_helpers import (
    build_pynq_agent_bundle,
    build_pynq_agent_match_pattern,
    build_pynq_agent_stop_command,
    build_pynq_user_space_agent_launch_command,
)
from .pynq_status import (
    preflight_board_fields,
    runtime_status_board_fields,
    serialize_pynq_board,
)
from .runtime_artifact import discover_neurochip_runtime_artifact
from .runtime_errors import RuntimeRequestError
from .runtime_shared import _neurochip_module_root
from .state_contracts import (
    PREFLIGHT_DEGRADED,
    PYNQ_AGENT_HEALTH_HEARTBEAT_AFTER_SECONDS,
    PYNQ_OVERLAY_UPLOAD_RECOVERY_MESSAGE,
    PYNQ_PREFLIGHT_RETRY_COUNT,
    PYNQ_PREFLIGHT_RETRY_DELAY_SECONDS,
    PYNQ_RUNTIME_LOG_TAIL_LINES,
    PynqBoardState,
)

PYNQ_DEVICE_GROUPS: tuple[str, ...] = ("video", "render")


class PynqProvisioningOwnerProtocol(Protocol):
    """Compatibility callbacks used while launcher state remains the route owner."""

    def _get_pynq_board(self, board_id: str) -> dict[str, Any]: ...

    def _update_pynq_board_fields(
        self, board_id: str, **fields: Any
    ) -> dict[str, Any]: ...

    def _emit_pynq_terminal_log(
        self, board: dict[str, Any], message: str, *, stderr: bool = False
    ) -> None: ...

    def _prepare_ssh_invocation(
        self,
        board: dict[str, Any],
        *,
        copy_mode: bool = False,
    ) -> tuple[list[str], dict[str, str] | None, Callable[[], None] | None]: ...

    def _run_ssh(self, board: dict[str, Any], remote_command: str) -> str: ...

    def _run_ssh_sudo(
        self,
        board: dict[str, Any],
        remote_command: str,
        *,
        timeout: float = 60.0,
    ) -> str: ...

    def _run_scp(
        self,
        board: dict[str, Any],
        local_path: Path,
        remote_path: str,
        *,
        recursive: bool = False,
    ) -> None: ...

    def _runtime_json_request(
        self,
        board: dict[str, Any],
        method: str,
        path: str,
        payload: dict[str, Any] | None = None,
        *,
        timeout: float = 15.0,
    ) -> dict[str, Any]: ...

    def _ensure_pynq_device_group_access(self, board: dict[str, Any]) -> None: ...

    def _remote_pynq_install_status_path(self, board: dict[str, Any]) -> str: ...

    def _read_remote_pynq_install_status(
        self, board: dict[str, Any]
    ) -> dict[str, Any]: ...

    def _wait_for_board_agent_health(
        self, board: dict[str, Any], timeout: float | None = None
    ) -> None: ...

    def _emit_runtime_log_tail(
        self,
        board: dict[str, Any],
        install_status: dict[str, Any],
        *,
        lines: int = PYNQ_RUNTIME_LOG_TAIL_LINES,
    ) -> None: ...

    def _build_remote_pynq_user_space_launch_command(
        self,
        *,
        agent_venv_path: str,
        pynq_python_path: str,
        install_status_path: str,
        overlay_dir: str,
        runtime_log_path: str,
        agent_executable_name: str,
    ) -> str: ...

    def _run_ssh_detached(
        self,
        board: dict[str, Any],
        remote_command: str,
        *,
        ssh_timeout: float = 15.0,
    ) -> None: ...

    def _restart_user_space_agent(
        self, board: dict[str, Any], install_status: dict[str, Any]
    ) -> None: ...

    def _run_ssh_privileged(
        self,
        board: dict[str, Any],
        remote_command: str,
        *,
        timeout: float = 60.0,
    ) -> str: ...

    def _promote_pynq_install_to_systemd(
        self,
        board: dict[str, Any],
        remote_bundle_dir: str,
        install_status: dict[str, Any],
    ) -> dict[str, Any]: ...

    def _write_remote_pynq_install_mode(
        self, board: dict[str, Any], install_mode: str, message: str
    ) -> None: ...

    def _confirm_remote_pynq_agent_process(
        self, board: dict[str, Any], agent_executable: str
    ) -> None: ...

    def _apply_preflight_to_board(
        self,
        board_id: str,
        preflight: dict[str, Any],
        *,
        fallback_error_state: PynqBoardState = "error",
    ) -> dict[str, Any]: ...

    def fetch_pynq_board_preflight(
        self,
        board_id: str,
        *,
        request_timeout: float | None = None,
    ) -> dict[str, Any]: ...

    def _refresh_pynq_board_preflight(
        self, board_id: str, *, stage: str
    ) -> dict[str, Any]: ...

    def _build_local_pynq_bundle(
        self, board: dict[str, Any], bundle_dir: Path
    ) -> dict[str, Any]: ...

    def _inspect_local_pynq_overlay_package(self) -> dict[str, Any]: ...


class PynqProvisioningCoordinator:
    """Coordinate PYNQ installation and readiness without owning persisted state."""

    def __init__(self, owner: PynqProvisioningOwnerProtocol) -> None:
        self._owner = owner

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
            groups = self._owner._run_ssh(board, "id -nG").split()
        except RuntimeError as exc:
            self._owner._emit_pynq_terminal_log(
                board, f"could not read group membership: {exc}", stderr=True
            )
            return
        missing = [group for group in PYNQ_DEVICE_GROUPS if group not in groups]
        if not missing:
            return
        self._owner._emit_pynq_terminal_log(
            board,
            f"granting {board['username']} access to the PL device nodes "
            f"(adding to {', '.join(missing)})",
        )
        try:
            self._owner._run_ssh_sudo(
                board,
                f"usermod -aG {','.join(missing)} {shlex.quote(str(board['username']))}",
            )
        except RuntimeError as exc:
            # Not fatal: the agent still starts, it just cannot open the device.
            # Say so here, or the only symptom is a device-probe failure that
            # looks like a hardware fault.
            self._owner._emit_pynq_terminal_log(
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
        raw = self._owner._run_ssh(
            board,
            f"cat {self._owner._remote_pynq_install_status_path(board)}",
        )
        try:
            decoded = json.loads(raw)
        except json.JSONDecodeError as exc:
            raise RuntimeError(
                f"Remote install status is not valid JSON: {raw}"
            ) from exc
        if not isinstance(decoded, dict):
            raise TypeError("Remote install status must decode to an object")
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
        self._owner._emit_pynq_terminal_log(
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
                        self._owner._emit_pynq_terminal_log(
                            board, "agent health check passed"
                        )
                        return
            except Exception as exc:  # noqa: BLE001 - capture last error across retries
                last_exc = exc
            elapsed = time.monotonic() - start
            if (
                not heartbeat_emitted
                and elapsed >= PYNQ_AGENT_HEALTH_HEARTBEAT_AFTER_SECONDS
            ):
                self._owner._emit_pynq_terminal_log(
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
        self._owner._emit_pynq_terminal_log(
            board, f"fetching last {lines} lines of {runtime_log_path}"
        )
        try:
            tail = self._owner._run_ssh(
                board, f"tail -n {int(lines)} {runtime_log_path}"
            )
        except Exception as exc:  # noqa: BLE001
            self._owner._emit_pynq_terminal_log(
                board,
                f"could not read remote runtime log at {runtime_log_path}: {exc}",
                stderr=True,
            )
            return
        for line in tail.splitlines() or [tail]:
            if line:
                self._owner._emit_pynq_terminal_log(
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
        launch_command: str = build_pynq_user_space_agent_launch_command(
            agent_executable=f"{agent_venv_path}/bin/{agent_executable_name}",
            pynq_python_path=pynq_python_path,
            install_status_path=install_status_path,
            overlay_dir=overlay_dir,
            runtime_log_path=runtime_log_path,
        )
        return launch_command

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
        command, env, cleanup = self._owner._prepare_ssh_invocation(board)
        command.extend([target, remote_command])
        self._owner._emit_pynq_terminal_log(
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
                self._owner._emit_pynq_terminal_log(board, result.stdout.strip())
            if result.stderr.strip():
                self._owner._emit_pynq_terminal_log(board, result.stderr.strip())
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
                self._owner._emit_pynq_terminal_log(
                    board,
                    f"ssh step exited {result.returncode} with no output beyond benign "
                    "SSH warnings; proceeding to health check",
                )
                return
            self._owner._emit_pynq_terminal_log(board, "ssh step completed")
        except subprocess.TimeoutExpired:
            self._owner._emit_pynq_terminal_log(
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
        install_status_path = self._owner._remote_pynq_install_status_path(board)
        overlay_dir = str(board["remoteOverlayDir"])
        agent_executable_name = str(
            board.get("agentExecutableName")
            or _load_neurochip_launcher_runtime_contract().pynq.agent_executable_name
        )
        self._owner._emit_pynq_terminal_log(
            board,
            f"restarting user-space agent with NEUROCHIP_PYNQ_OVERLAY_DIR={overlay_dir}",
        )
        agent_executable = f"{agent_venv_path}/bin/{agent_executable_name}"
        launch_command = self._owner._build_remote_pynq_user_space_launch_command(
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
        self._owner._run_ssh(
            board,
            build_pynq_agent_stop_command(agent_executable=agent_executable)
            + "; sleep 1",
        )
        # Before the launch, not after: group membership only reaches new login
        # sessions, and the launch below opens one.
        self._owner._ensure_pynq_device_group_access(board)
        self._owner._run_ssh_detached(board, launch_command)
        self._owner._confirm_remote_pynq_agent_process(board, agent_executable)
        self._owner._emit_pynq_terminal_log(
            board, "waiting for restarted agent to become healthy"
        )
        self._owner._wait_for_board_agent_health(board)

    def _run_ssh_privileged(
        self,
        board: dict[str, Any],
        remote_command: str,
        *,
        timeout: float = 60.0,
    ) -> str:
        """Run a privileged command whichever way this board grants root.

        A board paired with a password uses it; one paired with a key has to
        already have passwordless sudo, which is exactly the case the install
        script's own ``sudo -n`` branch covers.
        """
        if str(board.get("password") or "").strip():
            return self._owner._run_ssh_sudo(board, remote_command, timeout=timeout)
        return self._owner._run_ssh(board, f"sudo -n {remote_command}")

    def _promote_pynq_install_to_systemd(
        self,
        board: dict[str, Any],
        remote_bundle_dir: str,
        install_status: dict[str, Any],
    ) -> dict[str, Any]:
        """Reinstall a user-space runtime as a root-owned systemd service.

        PYNQ refuses to program the PL from a non-root process — ``Overlay(...)``
        raises "Root permissions required." — so a user-space agent passes every
        readiness check the app shows and then fails the first real deploy with
        an error the user can do nothing about. The install script only reaches
        its systemd branch when *passwordless* sudo works, which the stock PYNQ
        image does not have. The board's own password does, and the launcher
        already holds it to open every SSH session to this board, so this asks
        for nothing the user has not already given.

        Best effort by design: a board that will not grant root keeps the
        user-space runtime it already has, and the user-space guidance the
        caller appends still applies.
        """
        service_name = str(board["remoteServiceName"])
        agent_venv_path = str(
            install_status.get("agentVenvPath") or board["remoteVenvPath"]
        )
        agent_executable_name = str(
            board.get("agentExecutableName")
            or _load_neurochip_launcher_runtime_contract().pynq.agent_executable_name
        )
        agent_executable = f"{agent_venv_path}/bin/{agent_executable_name}"
        pynq_python_path = str(install_status.get("effectivePynqPython") or "").strip()

        try:
            self._owner._run_ssh_privileged(board, "true", timeout=30.0)
        except Exception as exc:  # noqa: BLE001
            self._owner._emit_pynq_terminal_log(
                board,
                f"this board grants no administrator access ({exc}), so the "
                "runtime stays in user space and cannot program the FPGA",
                stderr=True,
            )
            return install_status

        self._owner._emit_pynq_terminal_log(
            board,
            "promoting the runtime to a privileged systemd service so it can "
            "program the FPGA and start itself after a reboot",
        )
        staged_unit = f"/tmp/{service_name}.service"
        unit_source = f"{remote_bundle_dir}/systemd/{service_name}.service"
        try:
            if pynq_python_path:
                # The unit ships the default interpreter path; the install has
                # since settled on whichever one the board actually has.
                expression = (
                    "s|^Environment=NEUROCHIP_PYNQ_PYTHON=.*|"
                    f"Environment=NEUROCHIP_PYNQ_PYTHON={pynq_python_path}|"
                )
                stage = (
                    f"sed {shlex.quote(expression)} {shlex.quote(unit_source)} "
                    f"> {shlex.quote(staged_unit)}"
                )
            else:
                stage = f"cp {shlex.quote(unit_source)} {shlex.quote(staged_unit)}"
            self._owner._run_ssh(
                board, f"{stage} && chmod 0644 {shlex.quote(staged_unit)}"
            )
            self._owner._run_ssh(
                board,
                build_pynq_agent_stop_command(agent_executable=agent_executable)
                + "; sleep 1",
            )
            self._owner._run_ssh_privileged(
                board,
                f"mv {shlex.quote(staged_unit)} "
                f"/etc/systemd/system/{service_name}.service",
            )
            self._owner._run_ssh_privileged(board, "systemctl daemon-reload")
            self._owner._run_ssh_privileged(
                board, f"systemctl enable {service_name}.service"
            )
            self._owner._run_ssh_privileged(
                board, f"systemctl restart {service_name}.service"
            )
            self._owner._write_remote_pynq_install_mode(
                board,
                "systemd",
                "Runtime installed as a privileged systemd service; it can "
                "program the FPGA and starts again by itself after a board "
                "reboot.",
            )
            self._owner._wait_for_board_agent_health(board)
        except Exception as exc:  # noqa: BLE001
            self._owner._emit_pynq_terminal_log(
                board,
                f"privileged runtime install did not complete ({exc}); restoring "
                "the user-space runtime",
                stderr=True,
            )
            try:
                self._owner._restart_user_space_agent(board, install_status)
            except Exception as restore_exc:  # noqa: BLE001
                self._owner._emit_pynq_terminal_log(
                    board,
                    f"could not restore the user-space runtime either: {restore_exc}",
                    stderr=True,
                )
            return install_status

        self._owner._emit_pynq_terminal_log(
            board, "privileged runtime install completed; the agent now runs as root"
        )
        try:
            return self._owner._read_remote_pynq_install_status(board)
        except Exception:  # noqa: BLE001
            return install_status

    def _write_remote_pynq_install_mode(
        self, board: dict[str, Any], install_mode: str, message: str
    ) -> None:
        """Rewrite installMode in the board's install-status file.

        Preflight and every restart path read this file to decide how to talk to
        the runtime, so a promoted board that still claims "user-space" would be
        restarted with the launch command instead of systemctl.
        """
        script = (
            "import json,sys\n"
            "path, mode, message = sys.argv[1:4]\n"
            'with open(path, encoding="utf-8") as handle:\n'
            "    data = json.load(handle)\n"
            'data["installMode"] = mode\n'
            'data["message"] = message\n'
            'data["autoStartSupported"] = True\n'
            'with open(path, "w", encoding="utf-8") as handle:\n'
            "    json.dump(data, handle, indent=2, sort_keys=True)\n"
        )
        path = self._owner._remote_pynq_install_status_path(board)
        self._owner._run_ssh(
            board,
            " ".join(
                [
                    "python3 -c",
                    shlex.quote(script),
                    shlex.quote(path),
                    shlex.quote(install_mode),
                    shlex.quote(message),
                ]
            ),
        )

    def _confirm_remote_pynq_agent_process(
        self, board: dict[str, Any], agent_executable: str
    ) -> None:
        """Fail immediately when the launch command left no process behind.

        Without this the only signal is a 120s health timeout followed by three
        45s retries, and the reported failure is "did not become healthy" — which
        reads as a slow board rather than a start that never happened.
        """
        pattern = build_pynq_agent_match_pattern(agent_executable)
        found = self._owner._run_ssh(
            board,
            f"pgrep -f {shlex.quote(pattern)} >/dev/null 2>&1 && echo running || echo missing",
        )
        if "running" in found:
            return
        raise RuntimeError(
            "the agent process did not start on the board; see runtime.log below"
        )

    def _apply_preflight_to_board(
        self,
        board_id: str,
        preflight: dict[str, Any],
        *,
        fallback_error_state: PynqBoardState = "error",
    ) -> dict[str, Any]:
        fields = preflight_board_fields(
            preflight,
            fallback_error_state=fallback_error_state,
        )
        # The board reads the overlay version out of the manifest it actually
        # installed, and this is the only place that answer reaches the record.
        # Nothing wrote it before, so the app showed "Overlay: Not installed"
        # beside a board whose overlay was loaded and running. An absent value
        # leaves the stored one alone: a preflight that could not read the
        # manifest is not evidence the overlay was removed.
        return self._owner._update_pynq_board_fields(board_id, **fields)

    def test_pynq_board_connection(self, board_id: str) -> dict[str, Any]:
        board = self._owner._get_pynq_board(board_id)
        self._owner._emit_pynq_terminal_log(board, "testing SSH connectivity")
        self._owner._run_ssh(board, "python3 --version")
        self._owner._emit_pynq_terminal_log(board, "SSH connectivity succeeded")
        serialized: dict[str, Any] = serialize_pynq_board(
            self._owner._update_pynq_board_fields(
                board_id, state="reachable", lastPreflightMessage="SSH reachable"
            )
        )
        return serialized

    def fetch_pynq_board_preflight(
        self,
        board_id: str,
        *,
        request_timeout: float | None = None,
    ) -> dict[str, Any]:
        board = self._owner._get_pynq_board(board_id)
        self._owner._emit_pynq_terminal_log(board, "requesting runtime preflight")
        preflight = self._owner._runtime_json_request(
            board,
            "GET",
            "/hardware/pynq/preflight",
            timeout=(
                _resolve_pynq_preflight_timeout()
                if request_timeout is None
                else float(request_timeout)
            ),
        )
        self._owner._emit_pynq_terminal_log(
            board,
            _describe_pynq_preflight(preflight),
        )
        updated = self._owner._apply_preflight_to_board(board_id, preflight)
        return {
            "board": serialize_pynq_board(updated),
            "preflight": preflight,
        }

    def _refresh_pynq_board_preflight(
        self, board_id: str, *, stage: str
    ) -> dict[str, Any]:
        board = self._owner._get_pynq_board(board_id)
        request_timeout = _resolve_pynq_preflight_timeout()
        last_error: RuntimeRequestError | None = None
        for attempt in range(1, PYNQ_PREFLIGHT_RETRY_COUNT + 1):
            try:
                return self._owner.fetch_pynq_board_preflight(
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
                    self._owner._emit_pynq_terminal_log(
                        board,
                        (
                            f"runtime preflight is still running after {request_timeout:.0f}s "
                            f"during {stage}; retrying ({attempt + 1}/{PYNQ_PREFLIGHT_RETRY_COUNT})"
                        ),
                    )
                else:
                    self._owner._emit_pynq_terminal_log(
                        board,
                        (
                            f"runtime preflight could not reach the agent during {stage}; "
                            f"rechecking /health before retry ({attempt + 1}/{PYNQ_PREFLIGHT_RETRY_COUNT})"
                        ),
                    )
                    try:
                        self._owner._wait_for_board_agent_health(
                            board,
                            timeout=min(
                                _resolve_pynq_agent_health_timeout(),
                                request_timeout,
                            ),
                        )
                    except RuntimeError as health_exc:
                        self._owner._emit_pynq_terminal_log(
                            board,
                            f"/health was not stable during {stage}: {health_exc}",
                            stderr=True,
                        )
                time.sleep(PYNQ_PREFLIGHT_RETRY_DELAY_SECONDS)
        if last_error is not None:
            raise last_error
        raise RuntimeError(f"Runtime preflight refresh failed during {stage}")

    def fetch_pynq_board_status(self, board_id: str) -> dict[str, Any]:
        board = self._owner._get_pynq_board(board_id)
        self._owner._emit_pynq_terminal_log(board, "requesting runtime status")
        status = self._owner._runtime_json_request(
            board, "GET", "/hardware/pynq/status"
        )
        updated = self._owner._update_pynq_board_fields(
            board_id,
            **runtime_status_board_fields(status),
        )
        return {"board": serialize_pynq_board(updated), "status": status}

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
        bundle: dict[str, Any] = build_pynq_agent_bundle(
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
        return bundle

    def _inspect_local_pynq_overlay_package(self) -> dict[str, Any]:
        artifact_root = str(os.getenv("NMTK_NEUROCHIP_ARTIFACT_DIR") or "").strip()
        candidates = (
            _load_neurochip_launcher_runtime_contract().pynq.overlay_staging_candidates(
                _neurochip_module_root(),
                Path(artifact_root) if artifact_root else None,
            )
        )
        # Report the first complete package. Falling back on `ready` rather than
        # on directory existence matters in the container, where the module root
        # resolves to a path that simply is not there — reporting *its* issues
        # would tell the user to stage files into a directory the image never
        # ships, instead of using the overlay it already carries.
        inspected: list[dict[str, Any]] = [
            _inspect_staged_pynq_overlay_package(candidate) for candidate in candidates
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
        board = self._owner._update_pynq_board_fields(board_id, state="provisioning")
        self._owner._emit_pynq_terminal_log(board, "starting runtime provisioning")
        install_status: dict[str, Any] = {}
        install_mode = "unknown"
        install_script_started = False
        try:
            with tempfile.TemporaryDirectory(prefix="pynq-agent-bundle-") as tmp_dir:
                bundle_dir = Path(tmp_dir) / "bundle"
                bundle_dir.mkdir(parents=True, exist_ok=True)
                self._owner._emit_pynq_terminal_log(
                    board, "building local PYNQ agent bundle"
                )
                self._owner._build_local_pynq_bundle(board, bundle_dir)
                remote_bundle_parent = "/tmp"
                remote_bundle_dir = f"{remote_bundle_parent}/{bundle_dir.name}"
                self._owner._emit_pynq_terminal_log(
                    board,
                    f"preparing remote install directories at {board['remoteInstallRoot']}",
                )
                self._owner._run_ssh(
                    board,
                    (
                        f"mkdir -p {board['remoteInstallRoot']} {board['remoteOverlayDir']} "
                        f"&& rm -rf {remote_bundle_dir}"
                    ),
                )
                self._owner._emit_pynq_terminal_log(
                    board, f"uploading provisioning bundle to {remote_bundle_parent}"
                )
                self._owner._run_scp(
                    board, bundle_dir, remote_bundle_parent, recursive=True
                )
                # The install script starts the agent itself when it falls back to
                # a user-space install, so the grant has to land first to reach
                # that process.
                self._owner._ensure_pynq_device_group_access(board)
                self._owner._emit_pynq_terminal_log(
                    board, "running remote install script"
                )
                install_script_started = True
                self._owner._run_ssh(
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
                install_status = self._owner._read_remote_pynq_install_status(board)
                install_mode = (
                    str(install_status.get("installMode") or "unknown").strip()
                    or "unknown"
                )
                self._owner._emit_pynq_terminal_log(
                    board,
                    f"runtime install mode resolved to {install_mode}",
                )
                if install_mode != "systemd":
                    # A user-space agent cannot program the FPGA at all, so this
                    # is not a nicety — without root the board reaches "ready"
                    # and then fails every deploy.
                    install_status = self._owner._promote_pynq_install_to_systemd(
                        board, remote_bundle_dir, install_status
                    )
                    install_mode = (
                        str(install_status.get("installMode") or "unknown").strip()
                        or "unknown"
                    )
            self._owner._update_pynq_board_fields(board_id, state="runtime_installed")
            self._owner._emit_pynq_terminal_log(
                board, "runtime install finished; fetching preflight"
            )
            result = self._owner._refresh_pynq_board_preflight(
                board_id,
                stage="runtime provisioning",
            )
            board_state = str(result.get("board", {}).get("state") or "").strip()
            if board_state == "overlay_missing":
                self._owner._emit_pynq_terminal_log(
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
                updated = self._owner._update_pynq_board_fields(
                    board_id,
                    lastPreflightMessage=(
                        f"{prior_message} {guidance}".strip()
                        if prior_message
                        else guidance
                    ),
                )
                result["board"] = serialize_pynq_board(updated)
                preflight = result.get("preflight")
                if isinstance(preflight, dict):
                    preflight["preflight_message"] = updated["lastPreflightMessage"]
            result["installStatus"] = install_status
            return result
        except Exception as exc:  # noqa: BLE001
            if install_script_started:
                self._owner._emit_runtime_log_tail(board, install_status)
            self._owner._emit_pynq_terminal_log(
                board, f"runtime provisioning failed: {exc}", stderr=True
            )
            updated = self._owner._update_pynq_board_fields(
                board_id,
                state="provision_failed",
                lastPreflightMessage=str(exc),
            )
            return {"board": serialize_pynq_board(updated), "error": str(exc)}

    def install_pynq_overlay_assets(self, board_id: str) -> dict[str, Any]:
        board = self._owner._get_pynq_board(board_id)
        self._owner._emit_pynq_terminal_log(board, "starting overlay asset install")
        overlay_package = self._owner._inspect_local_pynq_overlay_package()
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
            self._owner._emit_pynq_terminal_log(
                board,
                message,
                stderr=True,
            )
            updated = self._owner._update_pynq_board_fields(
                board_id,
                state="overlay_missing",
                lastPreflightMessage=message,
            )
            return {
                "board": serialize_pynq_board(updated),
                "localOverlayPackage": overlay_package,
            }
        self._owner._emit_pynq_terminal_log(
            board,
            f"using staged overlay package from {overlay_package['stagingDir']}",
        )
        self._owner._emit_pynq_terminal_log(
            board, f"ensuring remote overlay dir {board['remoteOverlayDir']}"
        )
        self._owner._run_ssh(board, f"mkdir -p {board['remoteOverlayDir']}")
        self._owner._emit_pynq_terminal_log(board, "uploading snn_overlay.bit")
        self._owner._run_scp(
            board, bitstream, f"{board['remoteOverlayDir']}/snn_overlay.bit"
        )
        self._owner._emit_pynq_terminal_log(board, "uploading snn_overlay.hwh")
        self._owner._run_scp(board, hwh, f"{board['remoteOverlayDir']}/snn_overlay.hwh")
        self._owner._emit_pynq_terminal_log(board, "uploading overlay_manifest.json")
        self._owner._run_scp(
            board, manifest, f"{board['remoteOverlayDir']}/overlay_manifest.json"
        )
        self._owner._emit_pynq_terminal_log(
            board, "overlay upload finished; checking install mode"
        )
        try:
            install_status = self._owner._read_remote_pynq_install_status(board)
        except Exception:  # noqa: BLE001 - install status read is best-effort
            install_status = {}
        install_mode = str(install_status.get("installMode") or "unknown").strip()
        restart_warning: str | None = None
        if install_mode == "user-space":
            try:
                self._owner._restart_user_space_agent(board, install_status)
            except RuntimeError as exc:
                restart_warning = str(exc)
                self._owner._emit_runtime_log_tail(board, install_status)
                self._owner._emit_pynq_terminal_log(
                    board,
                    (
                        f"user-space agent restart did not become healthy: {exc}; "
                        "overlay files are uploaded — restart the board or run "
                        "restart-runtime manually"
                    ),
                    stderr=True,
                )
        self._owner._emit_pynq_terminal_log(board, "fetching preflight")
        try:
            result = self._owner._refresh_pynq_board_preflight(
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
                self._owner._emit_pynq_terminal_log(
                    board,
                    (
                        "readiness refresh after overlay upload did not complete: "
                        f"{exc}; {PYNQ_OVERLAY_UPLOAD_RECOVERY_MESSAGE}"
                    ),
                    stderr=True,
                )
            updated = self._owner._update_pynq_board_fields(
                board_id,
                state="degraded_optional_capability",
                lastPreflightStatus=PREFLIGHT_DEGRADED,
                lastPreflightMessage=PYNQ_OVERLAY_UPLOAD_RECOVERY_MESSAGE,
            )
            result = {
                "board": serialize_pynq_board(updated),
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
        board = self._owner._get_pynq_board(board_id)
        install_status = self._owner._read_remote_pynq_install_status(board)
        install_mode = (
            str(install_status.get("installMode") or "unknown").strip() or "unknown"
        )
        if install_mode == "user-space":
            self._owner._emit_pynq_terminal_log(board, "restarting user-space runtime")
            try:
                self._owner._restart_user_space_agent(board, install_status)
                result = self._owner._refresh_pynq_board_preflight(
                    board_id, stage="user-space runtime restart"
                )
            except RuntimeError as exc:
                self._owner._emit_runtime_log_tail(board, install_status)
                message = f"Could not restart the user-space runtime: {exc}"
                updated = self._owner._update_pynq_board_fields(
                    board_id,
                    state="degraded_optional_capability",
                    lastPreflightStatus=PREFLIGHT_DEGRADED,
                    lastPreflightMessage=message,
                )
                return {
                    "board": serialize_pynq_board(updated),
                    "warning": message,
                    "installStatus": install_status,
                }
            result["installStatus"] = install_status
            return result
        self._owner._emit_pynq_terminal_log(
            board, f"restarting systemd service {board['remoteServiceName']}.service"
        )
        # Through the password-carrying helper: the stock PYNQ image has no
        # passwordless sudo, so a plain `sudo systemctl` here waits for a prompt
        # that never comes and the restart times out.
        self._owner._run_ssh_privileged(
            board, f"systemctl restart {board['remoteServiceName']}.service"
        )
        self._owner._emit_pynq_terminal_log(
            board, "waiting for restarted systemd service to become healthy"
        )
        self._owner._wait_for_board_agent_health(board)
        self._owner._emit_pynq_terminal_log(
            board, "runtime restart completed; fetching preflight"
        )
        result = self._owner._refresh_pynq_board_preflight(
            board_id, stage="runtime restart"
        )
        result["installStatus"] = install_status
        return result


__all__ = [
    "PYNQ_DEVICE_GROUPS",
    "PynqProvisioningCoordinator",
    "PynqProvisioningOwnerProtocol",
]
