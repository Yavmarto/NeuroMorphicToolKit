"""Bounded and redacted SSH, SCP, and HTTP transport for PYNQ boards."""

from __future__ import annotations

import json
import logging
import os
import shutil
import subprocess
import threading
import urllib.error
import urllib.request
from collections import deque
from collections.abc import Callable
from pathlib import Path
from typing import Any

from .deployment_contracts import redact_text
from .hardware_models import (
    _is_benign_ssh_warning_line,
    _load_neurochip_launcher_runtime_contract,
    _resolved_pynq_runtime_api_url,
    _ssh_failure_message,
)
from .runtime_errors import RuntimeRequestError
from .runtime_shared import _build_password_askpass_env, _runtime_request_error_kind
from .state_contracts import DEFAULT_PYNQ_AUTH_MODE

LOGGER = logging.getLogger(__name__)
_PYNQ_SSH_TIMEOUT_SECONDS = 900.0
_PYNQ_SCP_TIMEOUT_SECONDS = 300.0
_PYNQ_OUTPUT_LINE_LIMIT = 400


class PynqRemoteClient:
    """Own remote process and HTTP calls for paired PYNQ boards."""

    @staticmethod
    def _safe_text(board: dict[str, Any], value: str) -> str:
        safe = str(redact_text(value))
        for key in ("password", "credentialRef"):
            secret = str(board.get(key) or "")
            if secret:
                safe = safe.replace(secret, "<redacted>")
        return safe

    def emit_log(
        self, board: dict[str, Any], message: str, *, stderr: bool = False
    ) -> None:
        """Write a redacted structured launcher log entry."""
        board_label = str(
            board.get("displayName") or board.get("host") or board.get("id") or "pynq"
        )
        log = LOGGER.error if stderr else LOGGER.info
        log(
            "pynq_remote_operation",
            extra={
                "pynq_board": board_label,
                "message_detail": self._safe_text(board, message),
            },
        )

    def prepare_ssh_invocation(
        self,
        board: dict[str, Any],
        *,
        copy_mode: bool = False,
    ) -> tuple[list[str], dict[str, str] | None, Callable[[], None] | None]:
        """Build an SSH/SCP invocation without placing passwords in argv."""
        prefix: list[str] = []
        env: dict[str, str] | None = None
        cleanup: Callable[[], None] | None = None
        auth_mode = str(board.get("authMode", DEFAULT_PYNQ_AUTH_MODE))
        if auth_mode == "password":
            password = str(board.get("password") or "")
            if not password:
                raise RuntimeError("No SSH password is configured for this PYNQ board")
            sshpass = shutil.which("sshpass")
            if sshpass is not None:
                prefix.extend([sshpass, "-e"])
                env = os.environ.copy()
                env["SSHPASS"] = password
            else:
                env, cleanup = _build_password_askpass_env(
                    password=password,
                    env_key="NMTK_PYNQ_PASSWORD",
                    prefix="nmtk-pynq-askpass-",
                )
        command = ["scp"] if copy_mode else ["ssh"]
        command.extend(
            [
                "-o",
                "StrictHostKeyChecking=accept-new",
                "-o",
                "UserKnownHostsFile=/dev/null",
                "-P" if copy_mode else "-p",
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

    def run_ssh(
        self,
        board: dict[str, Any],
        remote_command: str,
        *,
        timeout: float = _PYNQ_SSH_TIMEOUT_SECONDS,
    ) -> str:
        """Run a bounded SSH command and retain only a redacted output tail."""
        target = f"{board['username']}@{board['host']}"
        command, env, cleanup = self.prepare_ssh_invocation(board)
        command.extend([target, remote_command])
        self.emit_log(board, f"ssh -> {target}: {remote_command}")
        process: subprocess.Popen[str] | None = None
        stdout_lines: deque[str] = deque(maxlen=_PYNQ_OUTPUT_LINE_LIMIT)
        stderr_lines: deque[str] = deque(maxlen=_PYNQ_OUTPUT_LINE_LIMIT)
        try:
            process = subprocess.Popen(
                command,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                env=env,
                stdin=subprocess.DEVNULL,
            )

            def pump(stream: Any, sink: deque[str], *, is_stderr: bool = False) -> None:
                for raw_line in iter(stream.readline, ""):
                    line = self._safe_text(board, raw_line.rstrip())
                    if not line:
                        continue
                    sink.append(line)
                    self.emit_log(board, line, stderr=is_stderr)
                stream.close()

            stdout_thread = threading.Thread(
                target=pump,
                args=(process.stdout, stdout_lines),
                name=f"pynq-ssh-stdout-{board['id']}",
                daemon=True,
            )
            stderr_thread = threading.Thread(
                target=pump,
                args=(process.stderr, stderr_lines),
                kwargs={"is_stderr": True},
                name=f"pynq-ssh-stderr-{board['id']}",
                daemon=True,
            )
            stdout_thread.start()
            stderr_thread.start()
            try:
                return_code = process.wait(timeout=timeout)
            except subprocess.TimeoutExpired as exc:
                process.kill()
                process.wait()
                raise RuntimeError(
                    f"PYNQ SSH command timed out after {timeout:g}s"
                ) from exc
            stdout_thread.join(timeout=5)
            stderr_thread.join(timeout=5)
        finally:
            if cleanup is not None:
                cleanup()
        if return_code != 0:
            raise RuntimeError(
                _ssh_failure_message(list(stdout_lines), list(stderr_lines))
            )
        self.emit_log(board, "ssh step completed")
        return "\n".join(stdout_lines).strip()

    def run_ssh_sudo(
        self,
        board: dict[str, Any],
        remote_command: str,
        *,
        timeout: float = 60.0,
    ) -> str:
        """Run a bounded privileged command with the password supplied on stdin."""
        password = str(board.get("password") or "")
        if not password:
            raise RuntimeError("No SSH password is configured for this PYNQ board")
        target = f"{board['username']}@{board['host']}"
        command, env, cleanup = self.prepare_ssh_invocation(board)
        command.extend([target, f"sudo -S -p '' {remote_command}"])
        self.emit_log(board, f"ssh (sudo) -> {target}: {remote_command}")
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
            self.emit_log(board, line)
        for line in stderr_lines:
            self.emit_log(board, line, stderr=True)
        if result.returncode != 0:
            raise RuntimeError(_ssh_failure_message(stdout_lines, stderr_lines))
        self.emit_log(board, "sudo step completed")
        return "\n".join(stdout_lines).strip()

    def run_scp(
        self,
        board: dict[str, Any],
        local_path: Path,
        remote_path: str,
        *,
        recursive: bool = False,
        timeout: float = _PYNQ_SCP_TIMEOUT_SECONDS,
    ) -> None:
        """Copy one path with a timeout and redacted diagnostics."""
        command, env, cleanup = self.prepare_ssh_invocation(board, copy_mode=True)
        if recursive:
            command.append("-r")
        target = f"{board['username']}@{board['host']}:{remote_path}"
        command.extend([str(local_path), target])
        self.emit_log(board, f"scp -> {target} from {local_path}")
        try:
            result = subprocess.run(
                command,
                capture_output=True,
                text=True,
                timeout=timeout,
                check=False,
                env=env,
                stdin=subprocess.DEVNULL,
            )
        finally:
            if cleanup is not None:
                cleanup()
        if result.returncode != 0:
            message = self._safe_text(
                board,
                result.stderr.strip() or result.stdout.strip() or "scp command failed",
            )
            self.emit_log(board, message, stderr=True)
            raise RuntimeError(message)
        self.emit_log(board, "scp step completed")

    def json_request(
        self,
        board: dict[str, Any],
        method: str,
        path: str,
        payload: dict[str, Any] | None = None,
        *,
        timeout: float = 15.0,
    ) -> dict[str, Any]:
        """Issue one bounded runtime request with redacted failures."""
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
                decoded = json.loads(response.read().decode("utf-8"))
                if not isinstance(decoded, dict):
                    raise TypeError("Runtime response must be a JSON object")
                return decoded
        except urllib.error.HTTPError as exc:
            raw_body = exc.read().decode("utf-8", errors="replace").strip()
            error_body = self._safe_text(board, raw_body)
            self.emit_log(
                board,
                f"runtime request failed: {method} {url} returned HTTP {exc.code}",
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
        except (urllib.error.URLError, TimeoutError) as exc:
            kind = _runtime_request_error_kind(exc)
            detail = (
                f"timed out after {timeout:.0f}s"
                if kind == "timeout"
                else f"could not be reached: {self._safe_text(board, str(exc))}"
            )
            self.emit_log(
                board,
                f"runtime request failed: {method} {url} {detail}",
                stderr=True,
            )
            message = (
                f"Runtime request timed out for {method} {url} after {timeout:.0f}s"
                if kind == "timeout"
                else f"Runtime request failed for {method} {url}: {detail}"
            )
            raise RuntimeRequestError(message, kind=kind, url=url) from exc


__all__ = ["PynqRemoteClient"]
