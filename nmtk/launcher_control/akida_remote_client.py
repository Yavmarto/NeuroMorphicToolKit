"""Bounded SSH, SCP, and HTTP transport for paired Akida hosts."""

from __future__ import annotations

import json
import logging
import os
import shlex
import shutil
import subprocess
import threading
import urllib.error
import urllib.request
from collections import deque
from collections.abc import Callable
from pathlib import Path
from typing import Any, Protocol
from urllib.parse import urlparse

from .deployment_contracts import redact_text
from .hardware_models import (
    _load_neurochip_launcher_runtime_contract,
    _resolved_akida_base_url,
    _resolved_akida_control_api_url,
    _ssh_failure_message,
)
from .runtime_errors import RuntimeRequestError
from .runtime_shared import _build_password_askpass_env, _runtime_request_error_kind
from .state_contracts import DEFAULT_AKIDA_AUTH_MODE

LOGGER = logging.getLogger(__name__)
_AKIDA_SELF_HOST_TARGET = "host.docker.internal"
_AKIDA_SSH_TIMEOUT_SECONDS = 900.0
_AKIDA_SCP_TIMEOUT_SECONDS = 300.0
_AKIDA_OUTPUT_LINE_LIMIT = 400


class AkidaRemoteOwnerProtocol(Protocol):
    """Compatibility callbacks supplied by the launcher state façade."""

    def _read_remote_akida_token(
        self,
        host: dict[str, Any],
        *,
        install_status: dict[str, Any] | None = None,
    ) -> str: ...

    def _update_akida_host_fields(
        self, host_id: str, **fields: Any
    ) -> dict[str, Any]: ...


def akida_ssh_connect_host(host: dict[str, Any]) -> str:
    """Resolve the SSH target used from inside launcher-control."""
    if bool(host.get("sameHostAsBackend")):
        return _AKIDA_SELF_HOST_TARGET
    return str(host.get("host") or "")


def akida_request_base_url(base_url: str, host: dict[str, Any]) -> str:
    """Rewrite same-host requests through the container gateway alias."""
    if not base_url or not bool(host.get("sameHostAsBackend")):
        return base_url
    parsed = urlparse(base_url)
    if not parsed.hostname:
        return base_url
    netloc = _AKIDA_SELF_HOST_TARGET
    if parsed.port:
        netloc = f"{netloc}:{parsed.port}"
    return parsed._replace(netloc=netloc).geturl()


class AkidaRemoteClient:
    """Own all remote process and HTTP calls for one paired Akida host."""

    def __init__(self, owner: AkidaRemoteOwnerProtocol) -> None:
        self._owner = owner

    @staticmethod
    def _safe_text(host: dict[str, Any], value: str) -> str:
        safe = redact_text(value)
        for key in ("password", "credentialRef"):
            secret = str(host.get(key) or "")
            if secret:
                safe = safe.replace(secret, "<redacted>")
        return safe

    def emit_log(
        self, host: dict[str, Any], message: str, *, stderr: bool = False
    ) -> None:
        """Write a redacted structured launcher log entry."""
        host_label = str(
            host.get("displayName") or host.get("host") or host.get("id") or "akida"
        )
        safe_message = self._safe_text(host, message)
        log = LOGGER.error if stderr else LOGGER.info
        log(
            "akida_remote_operation",
            extra={"akida_host": host_label, "message_detail": safe_message},
        )

    def prepare_ssh_invocation(
        self,
        host: dict[str, Any],
        *,
        copy_mode: bool = False,
    ) -> tuple[list[str], dict[str, str] | None, Callable[[], None] | None]:
        """Build an SSH/SCP invocation without placing passwords in argv."""
        prefix: list[str] = []
        env: dict[str, str] | None = None
        cleanup: Callable[[], None] | None = None
        auth_mode = str(host.get("authMode", DEFAULT_AKIDA_AUTH_MODE))
        if auth_mode not in {"password", "ssh_key"}:
            raise RuntimeError(
                "Akida host SSH operations require password or SSH-key authentication"
            )
        if auth_mode == "password":
            password = str(host.get("password") or "")
            if not password:
                raise RuntimeError("No SSH password is configured for this Akida host")
            sshpass = shutil.which("sshpass")
            if sshpass is not None:
                prefix.extend([sshpass, "-e"])
                env = os.environ.copy()
                env["SSHPASS"] = password
            else:
                env, cleanup = _build_password_askpass_env(
                    password=password,
                    env_key="NMTK_AKIDA_PASSWORD",
                    prefix="nmtk-akida-askpass-",
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
                    host.get("sshPort")
                    or _load_neurochip_launcher_runtime_contract().akida.ssh_port
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
            ssh_key_path = str(host.get("sshKeyPath") or "").strip()
            if not ssh_key_path:
                raise RuntimeError("SSH-key authentication requires sshKeyPath")
            command.extend(["-i", ssh_key_path])
        return prefix + command, env, cleanup

    @staticmethod
    def remote_command_with_sudo_password(
        host: dict[str, Any], remote_command: str
    ) -> tuple[str, str]:
        """Return executable and redacted display variants of a sudo command."""
        password = str(host.get("password") or "")
        if str(host.get("authMode") or "").strip() != "password" or not password:
            return remote_command, remote_command
        return (
            f"NMTK_AKIDA_SUDO_PASSWORD={shlex.quote(password)} {remote_command}",
            f"NMTK_AKIDA_SUDO_PASSWORD=<redacted> {remote_command}",
        )

    def run_ssh(
        self,
        host: dict[str, Any],
        remote_command: str,
        *,
        display_command: str | None = None,
        timeout: float = _AKIDA_SSH_TIMEOUT_SECONDS,
    ) -> str:
        """Run one bounded SSH command and retain only a redacted output tail."""
        username = str(host.get("username") or "").strip()
        if not username:
            raise RuntimeError("Akida host username is required for SSH operations")
        target = f"{username}@{akida_ssh_connect_host(host)}"
        command, env, cleanup = self.prepare_ssh_invocation(host)
        command.extend([target, remote_command])
        logged_command = (
            display_command if display_command is not None else remote_command
        )
        self.emit_log(host, f"ssh -> {target}: {logged_command}")
        process: subprocess.Popen[str] | None = None
        stdout_lines: deque[str] = deque(maxlen=_AKIDA_OUTPUT_LINE_LIMIT)
        stderr_lines: deque[str] = deque(maxlen=_AKIDA_OUTPUT_LINE_LIMIT)
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
                    line = self._safe_text(host, raw_line.rstrip())
                    if not line:
                        continue
                    sink.append(line)
                    self.emit_log(host, line, stderr=is_stderr)
                stream.close()

            stdout_thread = threading.Thread(
                target=pump,
                args=(process.stdout, stdout_lines),
                name=f"akida-ssh-stdout-{host['id']}",
                daemon=True,
            )
            stderr_thread = threading.Thread(
                target=pump,
                args=(process.stderr, stderr_lines),
                kwargs={"is_stderr": True},
                name=f"akida-ssh-stderr-{host['id']}",
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
                    f"Akida SSH command timed out after {timeout:g}s"
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
        self.emit_log(host, "ssh step completed")
        return "\n".join(stdout_lines).strip()

    def run_scp(
        self,
        host: dict[str, Any],
        local_path: Path,
        remote_path: str,
        *,
        recursive: bool = False,
        timeout: float = _AKIDA_SCP_TIMEOUT_SECONDS,
    ) -> None:
        """Copy a file or directory with bounded execution and safe errors."""
        username = str(host.get("username") or "").strip()
        if not username:
            raise RuntimeError("Akida host username is required for SCP operations")
        command, env, cleanup = self.prepare_ssh_invocation(host, copy_mode=True)
        if recursive:
            command.append("-r")
        target = f"{username}@{akida_ssh_connect_host(host)}:{remote_path}"
        command.extend([str(local_path), target])
        self.emit_log(host, f"scp -> {target} from {local_path}")
        try:
            try:
                result = subprocess.run(
                    command,
                    capture_output=True,
                    text=True,
                    check=False,
                    env=env,
                    stdin=subprocess.DEVNULL,
                    timeout=timeout,
                )
            except subprocess.TimeoutExpired as exc:
                raise RuntimeError(
                    f"Akida SCP command timed out after {timeout:g}s"
                ) from exc
        finally:
            if cleanup is not None:
                cleanup()
        if result.returncode != 0:
            message = self._safe_text(
                host,
                result.stderr.strip() or result.stdout.strip() or "scp command failed",
            )
            self.emit_log(host, message, stderr=True)
            raise RuntimeError(message)
        self.emit_log(host, "scp step completed")

    def recover_credential(self, host: dict[str, Any]) -> str:
        """Re-read and persist the app-managed API token after one 401."""
        host_id = str(host.get("id") or "").strip()
        if not host_id or not str(host.get("username") or "").strip():
            return ""
        try:
            token = self._owner._read_remote_akida_token(host).strip()
        except Exception as exc:  # noqa: BLE001 - recovery must degrade to the original 401
            self.emit_log(
                host,
                f"could not re-read the Akida API token from the host: {exc}",
                stderr=True,
            )
            return ""
        if not token or token == str(host.get("credentialRef") or "").strip():
            return ""
        self._owner._update_akida_host_fields(host_id, credentialRef=token)
        self.emit_log(host, "recovered the Akida API token from the host; retrying")
        return token

    @staticmethod
    def unauthorized_message(host: dict[str, Any], url: str) -> str:
        """Explain an app-managed token failure without asking users for a key."""
        if not str(host.get("username") or "").strip():
            return (
                f"{url} requires an API token, and no SSH login is saved for this "
                "host, so the token could not be read back. Add the host's SSH "
                "login under Setup -> Manage Targets, then choose Install in the "
                "Akida Runtime panel."
            )
        token_path = str(host.get("tokenPath") or "").strip() or "its install directory"
        return (
            f"{url} rejected this app's API token. No key needs to be entered — the "
            f"token is managed for you — but it could not be read from {token_path} "
            "on the host, which usually means the Neurochip runtime there was "
            "installed outside this app. Choose Install in the Akida Runtime panel "
            "to reinstall the runtime and regenerate the token."
        )

    def control_json_request(
        self,
        host: dict[str, Any],
        method: str,
        path: str,
        payload: dict[str, Any] | None = None,
        *,
        emit_terminal_errors: bool = True,
        allow_recovery: bool = True,
    ) -> dict[str, Any]:
        """Call the remote control API with one bounded credential recovery."""
        base_url = _resolved_akida_control_api_url(host).rstrip("/")
        if not base_url:
            raise RuntimeError("Akida host controlApiUrl is not configured")
        return self._json_request(
            host,
            method,
            f"{akida_request_base_url(base_url, host)}{path}",
            payload,
            label="Control",
            timeout=15.0,
            emit_terminal_errors=emit_terminal_errors,
            allow_recovery=allow_recovery,
        )

    def json_request(
        self,
        host: dict[str, Any],
        method: str,
        path: str,
        payload: dict[str, Any] | None = None,
        *,
        allow_recovery: bool = True,
        timeout: float = 15.0,
    ) -> dict[str, Any]:
        """Call the remote runtime API with one bounded credential recovery."""
        base_url = _resolved_akida_base_url(host).rstrip("/")
        if not base_url:
            raise RuntimeError("Akida host baseUrl is not configured")
        return self._json_request(
            host,
            method,
            f"{akida_request_base_url(base_url, host)}{path}",
            payload,
            label="Runtime",
            timeout=timeout,
            emit_terminal_errors=True,
            allow_recovery=allow_recovery,
        )

    def _json_request(
        self,
        host: dict[str, Any],
        method: str,
        url: str,
        payload: dict[str, Any] | None,
        *,
        label: str,
        timeout: float,
        emit_terminal_errors: bool,
        allow_recovery: bool,
    ) -> dict[str, Any]:
        headers = {"Content-Type": "application/json"}
        credential_ref = str(host.get("credentialRef") or "").strip()
        if credential_ref:
            headers["X-API-Key"] = credential_ref
        data = json.dumps(payload).encode("utf-8") if payload is not None else None
        request = urllib.request.Request(url, data=data, headers=headers, method=method)
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                body = response.read().decode("utf-8")
                decoded = json.loads(body) if body else {}
                if not isinstance(decoded, dict):
                    raise TypeError(
                        f"Unexpected {label.lower()} response from {url}"
                    )
                return decoded
        except urllib.error.HTTPError as exc:
            error_body = self._safe_text(
                host, exc.read().decode("utf-8", errors="replace")
            )
            if exc.code == 401 and allow_recovery:
                recovered = self.recover_credential(host)
                if recovered:
                    return self._json_request(
                        {**host, "credentialRef": recovered},
                        method,
                        url,
                        payload,
                        label=label,
                        timeout=timeout,
                        emit_terminal_errors=emit_terminal_errors,
                        allow_recovery=False,
                    )
            if emit_terminal_errors:
                self.emit_log(
                    host,
                    f"{label.lower()} request failed: {method} {url} returned HTTP {exc.code}"
                    + (f" with body: {error_body}" if error_body else ""),
                    stderr=True,
                )
            if exc.code == 401:
                raise RuntimeRequestError(
                    self.unauthorized_message(host, url),
                    kind="http",
                    url=url,
                    status_code=exc.code,
                    response_body=error_body,
                ) from exc
            raise RuntimeRequestError(
                f"{label} request failed for {method} {url}: HTTP {exc.code}"
                + (f" — {error_body}" if error_body else ""),
                kind="http",
                url=url,
                status_code=exc.code,
                response_body=error_body,
            ) from exc
        except urllib.error.URLError as exc:
            kind = _runtime_request_error_kind(exc)
            detail = (
                "timed out" if kind == "timeout" else f"could not be reached: {exc}"
            )
            if emit_terminal_errors:
                self.emit_log(
                    host,
                    f"{label.lower()} request failed: {method} {url} {detail}",
                    stderr=True,
                )
            raise RuntimeRequestError(
                f"{label} request failed for {method} {url}: {detail}",
                kind=kind,
                url=url,
            ) from exc


__all__ = [
    "AkidaRemoteClient",
    "AkidaRemoteOwnerProtocol",
    "akida_request_base_url",
    "akida_ssh_connect_host",
]
