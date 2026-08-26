"""Akida host CRUD, provisioning, SSH/HTTP transport, and runtime proxy behavior."""

from __future__ import annotations

import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import threading
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable
from urllib.parse import urlparse

from .hardware_models import (
    _akida_hardware_runtime_ready,
    _akida_host_state_for_status,
    _akida_user_space_upgrade_message,
    _default_akida_base_url,
    _default_akida_control_url,
    _describe_akida_preflight,
    _extract_install_status_from_output,
    _load_neurochip_launcher_runtime_contract,
    _normalize_akida_host,
    _preflight_status_for_akida_verification,
    _resolved_akida_base_url,
    _resolved_akida_control_api_url,
    _serialize_akida_host,
    _ssh_failure_message,
)
from .provisioning_helpers import DEFAULT_AKIDA_PYTHON_RANGE, build_akida_host_bundle
from .runtime_artifact import discover_neurochip_runtime_artifact
from .runtime_errors import RuntimeRequestError
from .runtime_shared import (
    _build_password_askpass_env,
    _module_root,
    _runtime_request_error_kind,
)
from .state_contracts import (
    DEFAULT_AKIDA_AUTH_MODE,
    PREFLIGHT_DEGRADED,
    PREFLIGHT_FAILED,
    PREFLIGHT_OK,
)

# Signatures of raw driver/SDK output: a bare errno wrapper as the Akida SDK
# writes it ("err(110)", "errno(110)"), or a hex register address. Matching the
# shape rather than a specific errno keeps this from being a list of numbers
# that has to grow every time the SDK gains a new failure.
_RAW_DEVICE_ERROR_PATTERN = re.compile(r"\berr(?:no)?\(\d+\)|\b0x[0-9a-fA-F]{4,}\b")

# The docker/podman compose files map this alias to the container's default
# gateway (`extra_hosts: host.docker.internal:host-gateway`) specifically so
# launcher-control can dial back out to services on its own host machine.
#
# Measured on the dev box (rootless Podman): from inside this container the
# host's LAN address reaches its *published container ports* fine, but reaches
# no host-level service at all — `192.168.2.90:22` behaves exactly like a
# closed port, while `host.docker.internal:22` returns the real sshd banner.
# Both sshd and a natively installed Neurochip runtime are host-level services,
# so both have to be dialed through this alias.
_AKIDA_SELF_HOST_TARGET = "host.docker.internal"


def _akida_ssh_connect_host(host: dict[str, Any]) -> str:
    """Resolve the address SSH/SCP should actually dial for *host*.

    When the Akida card is on the same physical machine as launcher-control
    itself, dialing the LAN address the user entered is refused (see the
    constant above). Everything else about the host record — `runtimeApiUrl`,
    `controlApiUrl`, the displayed `host` value — keeps the real LAN address,
    because the app and other machines reach those directly rather than from
    inside this container.
    """
    if bool(host.get("sameHostAsBackend")):
        return _AKIDA_SELF_HOST_TARGET
    return str(host.get("host") or "")


def _akida_request_base_url(base_url: str, host: dict[str, Any]) -> str:
    """Rewrite *base_url*'s host for HTTP calls made from inside this container.

    Same reason as `_akida_ssh_connect_host`: once provisioned, the Neurochip
    runtime is a native systemd service on the host, so it is only reachable
    through the gateway alias. Only the request target is rewritten — the
    stored and serialized URLs keep the address the user entered, so the UI
    never shows this alias and other clients are unaffected.
    """
    if not base_url or not bool(host.get("sameHostAsBackend")):
        return base_url
    parsed = urlparse(base_url)
    if not parsed.hostname:
        return base_url
    netloc = _AKIDA_SELF_HOST_TARGET
    if parsed.port:
        netloc = f"{netloc}:{parsed.port}"
    return parsed._replace(netloc=netloc).geturl()


class AkidaServiceMixin:
    def list_akida_hosts(self) -> list[dict[str, Any]]:
        with self._lock:
            hosts = self._settings.get("akidaHosts", [])
            return [_serialize_akida_host(host) for host in hosts]

    def get_akida_host(self, host_id: str) -> dict[str, Any]:
        with self._lock:
            host = self._get_akida_host(host_id)
            return _serialize_akida_host(host)

    def create_akida_host(self, payload: dict[str, Any]) -> dict[str, Any]:
        host = _normalize_akida_host(payload)
        if (
            not _resolved_akida_base_url(host)
            and not str(host.get("host") or "").strip()
        ):
            raise ValueError("Akida host runtimeApiUrl or host is required")
        with self._lock:
            hosts = self._settings["akidaHosts"]
            if any(existing["id"] == host["id"] for existing in hosts):
                raise ValueError(f"Akida host '{host['id']}' already exists")
            if host.get("isDefault"):
                for existing in hosts:
                    existing["isDefault"] = False
            hosts.append(host)
            if not self._settings.get("selectedAkidaHostId"):
                self._settings["selectedAkidaHostId"] = host["id"]
            self._persist_settings()
            return _serialize_akida_host(host)

    def update_akida_host(
        self, host_id: str, payload: dict[str, Any]
    ) -> dict[str, Any]:
        with self._lock:
            host = self._get_akida_host(host_id)
            normalized = self._normalize_updated_akida_host(
                host, {"id": host_id, **payload}
            )
            if normalized.get("isDefault"):
                for existing in self._settings.get("akidaHosts", []):
                    if existing["id"] != host_id:
                        existing["isDefault"] = False
            host.clear()
            host.update(normalized)
            self._persist_settings()
            return _serialize_akida_host(host)

    def delete_akida_host(self, host_id: str) -> None:
        with self._lock:
            hosts = self._settings["akidaHosts"]
            next_hosts = [host for host in hosts if host["id"] != host_id]
            if len(next_hosts) == len(hosts):
                raise KeyError(f"Unknown Akida host '{host_id}'")
            self._settings["akidaHosts"] = next_hosts
            if self._settings.get("selectedAkidaHostId") == host_id:
                self._settings["selectedAkidaHostId"] = (
                    next_hosts[0]["id"] if next_hosts else None
                )
            self._persist_settings()

    def _get_akida_host(self, host_id: str) -> dict[str, Any]:
        for host in self._settings.get("akidaHosts", []):
            if host["id"] == host_id:
                return host
        raise KeyError(f"Unknown Akida host '{host_id}'")

    def _update_akida_host_fields(self, host_id: str, **fields: Any) -> dict[str, Any]:
        with self._lock:
            host = self._get_akida_host(host_id)
            normalized = self._normalize_updated_akida_host(
                host, {"id": host_id, **fields}
            )
            host.clear()
            host.update(normalized)
            self._persist_settings()
            return dict(host)

    def _normalize_updated_akida_host(
        self,
        host: dict[str, Any],
        updates: dict[str, Any],
    ) -> dict[str, Any]:
        merged = dict(host)
        merged.update(updates)
        # An *absent* password key already keeps the stored one, because `merged`
        # starts from `host`. An explicitly empty one therefore means "clear it":
        # treating the two the same made a saved password impossible to remove,
        # and every internal caller of _update_akida_host_fields omits the key
        # rather than sending "".
        if str(merged.get("password") or "") and "authMode" not in updates:
            merged["authMode"] = "password"
        if "baseUrl" in updates and "runtimeApiUrl" not in updates:
            merged.pop("runtimeApiUrl", None)
        if "baseUrl" in updates and "port" not in updates:
            merged.pop("port", None)
        return _normalize_akida_host(merged)

    def proxy_akida_map(
        self,
        host_id: str,
        payload: dict[str, Any],
        *,
        bit_width: int = 4,
    ) -> dict[str, Any]:
        host = self._get_akida_host(host_id)
        self._emit_akida_terminal_log(
            host, f"proxying runtime map request (bit_width={bit_width})"
        )
        status = self._akida_json_request(
            host,
            "POST",
            f"/api/neurochip/akida/map?bit_width={bit_width}",
            payload,
        )
        self._emit_akida_terminal_log(
            host,
            (
                "runtime map completed with target "
                f"{str(status.get('runtime_target') or 'unknown').strip() or 'unknown'}"
            ),
        )
        self._update_akida_host_fields(
            host_id,
            state=_akida_host_state_for_status(host, status),
            lastStatus=status,
        )
        return status

    def proxy_akida_run(self, host_id: str, payload: dict[str, Any]) -> dict[str, Any]:
        host = self._get_akida_host(host_id)
        self._emit_akida_terminal_log(host, "proxying runtime inference request")
        result = self._akida_json_request(
            host,
            "POST",
            "/api/neurochip/akida/inference",
            payload,
        )
        self._emit_akida_terminal_log(
            host,
            (
                "runtime inference completed on "
                f"{str(result.get('runtime_target') or 'unknown').strip() or 'unknown'}"
            ),
        )
        return result

    def proxy_akida_model_job(
        self, host_id: str, payload: dict[str, Any]
    ) -> dict[str, Any]:
        """Submit a checksummed model bundle to the selected Akida host."""
        encoded = payload.get("bundleBase64")
        if not isinstance(encoded, str) or not encoded:
            raise ValueError("bundleBase64 is required")
        if len(encoded) > 45 * 1024 * 1024:
            raise ValueError("Encoded model bundle exceeds the 45 MB proxy limit")
        host = self._get_akida_host(host_id)
        self._emit_akida_terminal_log(host, "submitting Akida model conversion job")
        return self._akida_json_request(
            host,
            "POST",
            "/api/neurochip/akida/model-jobs",
            payload,
            # The default 15s is for small control calls. This body is base64 and
            # allowed up to 45 MB just above, so on a slow link the upload itself
            # outran the timeout and the submission failed for no stated reason.
            timeout=300.0,
        )

    def proxy_akida_model_job_status(self, host_id: str, job_id: str) -> dict[str, Any]:
        """Poll one model conversion job using stored host credentials."""
        host = self._get_akida_host(host_id)
        return self._akida_json_request(
            host,
            "GET",
            f"/api/neurochip/akida/model-jobs/{job_id}",
        )

    def proxy_akida_model_inference(
        self,
        host_id: str,
        model_id: str,
        payload: dict[str, Any],
    ) -> dict[str, Any]:
        """Run sample inference for a converted bundle model."""
        host = self._get_akida_host(host_id)
        return self._akida_json_request(
            host,
            "POST",
            f"/api/neurochip/akida/models/{model_id}/inference",
            payload,
        )

    def proxy_akida_model_benchmark(
        self, host_id: str, model_id: str
    ) -> dict[str, Any]:
        """Start a whole-dataset benchmark run for a converted bundle model.

        The default timeout is fine here even though the run itself is long:
        the host returns a job immediately and progress is polled through
        ``proxy_akida_model_job_status``.
        """
        host = self._get_akida_host(host_id)
        self._emit_akida_terminal_log(host, "starting Akida benchmark run")
        return self._akida_json_request(
            host,
            "POST",
            f"/api/neurochip/akida/models/{model_id}/benchmark",
            {},
        )

    def proxy_akida_model_visualization(
        self,
        host_id: str,
        model_id: str,
        payload: dict[str, Any],
    ) -> dict[str, Any]:
        """Replay a deployed model layer through the selected Akida host."""
        host = self._get_akida_host(host_id)
        return self._akida_json_request(
            host,
            "POST",
            f"/api/neurochip/akida/models/{model_id}/visualization",
            payload,
            # Benchmark visualization replays the complete evaluation set in
            # software before returning its compressed matrix.
            timeout=300.0,
        )

    def _emit_akida_terminal_log(
        self, host: dict[str, Any], message: str, *, stderr: bool = False
    ) -> None:
        stream = sys.stderr if stderr else sys.stdout
        host_label = str(
            host.get("displayName") or host.get("host") or host.get("id") or "akida"
        )
        print(f"[akida:{host_label}] {message}", file=stream, flush=True)

    def _prepare_akida_ssh_invocation(
        self,
        host: dict[str, Any],
        *,
        copy_mode: bool = False,
    ) -> tuple[list[str], dict[str, str] | None, Callable[[], None] | None]:
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
                prefix.extend([sshpass, "-p", password])
            else:
                env, cleanup = _build_password_askpass_env(
                    password=password,
                    env_key="NMTK_AKIDA_PASSWORD",
                    prefix="nmtk-akida-askpass-",
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

    def _akida_remote_command_with_sudo_password(
        self,
        host: dict[str, Any],
        remote_command: str,
    ) -> tuple[str, str]:
        password = str(host.get("password") or "")
        if str(host.get("authMode") or "").strip() != "password" or not password:
            return remote_command, remote_command
        return (
            f"NMTK_AKIDA_SUDO_PASSWORD={shlex.quote(password)} {remote_command}",
            f"NMTK_AKIDA_SUDO_PASSWORD=<redacted> {remote_command}",
        )

    def _run_akida_ssh(
        self,
        host: dict[str, Any],
        remote_command: str,
        *,
        display_command: str | None = None,
    ) -> str:
        username = str(host.get("username") or "").strip()
        if not username:
            raise RuntimeError("Akida host username is required for SSH operations")
        target = f"{username}@{_akida_ssh_connect_host(host)}"
        command, env, cleanup = self._prepare_akida_ssh_invocation(host)
        command.extend([target, remote_command])
        logged_command = (
            display_command if display_command is not None else remote_command
        )
        self._emit_akida_terminal_log(host, f"ssh -> {target}: {logged_command}")
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
                    self._emit_akida_terminal_log(host, line, stderr=stderr)
                stream.close()

            stdout_thread = threading.Thread(
                target=_pump,
                args=(process.stdout, stdout_lines),
                name=f"akida-ssh-stdout-{host['id']}",
            )
            stderr_thread = threading.Thread(
                target=_pump,
                args=(process.stderr, stderr_lines),
                kwargs={"stderr": True},
                name=f"akida-ssh-stderr-{host['id']}",
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
        self._emit_akida_terminal_log(host, "ssh step completed")
        return "\n".join(stdout_lines).strip()

    def _run_akida_scp(
        self,
        host: dict[str, Any],
        local_path: Path,
        remote_path: str,
        *,
        recursive: bool = False,
    ) -> None:
        username = str(host.get("username") or "").strip()
        if not username:
            raise RuntimeError("Akida host username is required for SCP operations")
        command, env, cleanup = self._prepare_akida_ssh_invocation(host, copy_mode=True)
        if recursive:
            command.append("-r")
        target = f"{username}@{_akida_ssh_connect_host(host)}:{remote_path}"
        command.extend([str(local_path), target])
        self._emit_akida_terminal_log(host, f"scp -> {target} from {local_path}")
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
            self._emit_akida_terminal_log(
                host,
                result.stderr.strip() or result.stdout.strip() or "scp command failed",
                stderr=True,
            )
            raise RuntimeError(
                result.stderr.strip() or result.stdout.strip() or "scp command failed"
            )
        self._emit_akida_terminal_log(host, "scp step completed")

    def _recover_akida_credential(self, host: dict[str, Any]) -> str:
        """Re-read the host's API token over SSH after a 401.

        Provisioning turns API-key auth on at the host itself — it writes
        ``NEUROCHIP_AUTH_ENABLED=true`` plus a generated token into the service
        env files — and records that token in ``credentialRef``. Anything that
        separates the two leaves the host enforcing a key this app does not
        hold: a runtime installed outside the app, a recreated settings file, or
        a provision that started the services but failed its token read-back.
        Because every request only sets ``X-API-Key`` when ``credentialRef`` is
        non-empty, the result is a permanent 401 with no way out from the UI.

        The token is readable with the SSH credentials already saved, so recover
        it rather than asking for a key the user was never given.

        Returns the recovered token, or ``''`` when recovery is not possible.
        """
        host_id = str(host.get("id") or "").strip()
        if not host_id or not str(host.get("username") or "").strip():
            return ""
        try:
            token = self._read_remote_akida_token(host).strip()
        except Exception as exc:  # noqa: BLE001
            self._emit_akida_terminal_log(
                host,
                f"could not re-read the Akida API token from the host: {exc}",
                stderr=True,
            )
            return ""
        if not token or token == str(host.get("credentialRef") or "").strip():
            return ""
        self._update_akida_host_fields(host_id, credentialRef=token)
        self._emit_akida_terminal_log(
            host, "recovered the Akida API token from the host; retrying"
        )
        return token

    def _akida_unauthorized_message(self, host: dict[str, Any], url: str) -> str:
        """Actionable replacement for the host's bare 401 body.

        The host answers "Invalid or missing API Key", which reads as though the
        user forgot to enter a credential. They have none to enter: the token is
        generated and carried by this app. Say what is actually wrong and which
        in-app action fixes it.
        """
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

    def _akida_control_json_request(
        self,
        host: dict[str, Any],
        method: str,
        path: str,
        payload: dict[str, Any] | None = None,
        *,
        emit_terminal_errors: bool = True,
        allow_recovery: bool = True,
    ) -> dict[str, Any]:
        base_url = _resolved_akida_control_api_url(host).rstrip("/")
        if not base_url:
            raise RuntimeError("Akida host controlApiUrl is not configured")
        url = f"{_akida_request_base_url(base_url, host)}{path}"
        headers = {"Content-Type": "application/json"}
        credential_ref = str(host.get("credentialRef") or "").strip()
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
            with urllib.request.urlopen(request, timeout=15.0) as response:
                body = response.read().decode("utf-8")
                decoded = json.loads(body) if body else {}
                if not isinstance(decoded, dict):
                    raise RuntimeError(f"Unexpected control response from {url}")
                return decoded
        except urllib.error.HTTPError as exc:
            error_body = exc.read().decode("utf-8", errors="replace")
            # `allow_recovery=False` on the retry: a plain recursive call would
            # loop forever against a host whose token genuinely does not match.
            if exc.code == 401 and allow_recovery:
                recovered = self._recover_akida_credential(host)
                if recovered:
                    return self._akida_control_json_request(
                        {**host, "credentialRef": recovered},
                        method,
                        path,
                        payload,
                        emit_terminal_errors=emit_terminal_errors,
                        allow_recovery=False,
                    )
            if emit_terminal_errors:
                self._emit_akida_terminal_log(
                    host,
                    (
                        f"control request failed: {method} {url} returned HTTP {exc.code}"
                        + (f" with body: {error_body}" if error_body else "")
                    ),
                    stderr=True,
                )
            if exc.code == 401:
                raise RuntimeRequestError(
                    self._akida_unauthorized_message(host, url),
                    kind="http",
                    url=url,
                    status_code=exc.code,
                    response_body=error_body,
                ) from exc
            raise RuntimeRequestError(
                f"Control request failed for {method} {url}: HTTP {exc.code}"
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
                self._emit_akida_terminal_log(
                    host,
                    f"control request failed: {method} {url} {detail}",
                    stderr=True,
                )
            raise RuntimeRequestError(
                f"Control request failed for {method} {url}: {detail}",
                kind=kind,
                url=url,
            ) from exc

    def _akida_json_request(
        self,
        host: dict[str, Any],
        method: str,
        path: str,
        payload: dict[str, Any] | None = None,
        *,
        allow_recovery: bool = True,
        timeout: float = 15.0,
    ) -> dict[str, Any]:
        base_url = _resolved_akida_base_url(host).rstrip("/")
        if not base_url:
            raise RuntimeError("Akida host baseUrl is not configured")
        url = f"{_akida_request_base_url(base_url, host)}{path}"
        headers = {"Content-Type": "application/json"}
        credential_ref = str(host.get("credentialRef") or "").strip()
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
            # See _akida_control_json_request: recover the app's own token once,
            # then stop. The retry passes allow_recovery=False so a host whose
            # token really does not match cannot loop.
            if exc.code == 401 and allow_recovery:
                recovered = self._recover_akida_credential(host)
                if recovered:
                    return self._akida_json_request(
                        {**host, "credentialRef": recovered},
                        method,
                        path,
                        payload,
                        allow_recovery=False,
                    )
            self._emit_akida_terminal_log(
                host,
                (
                    f"runtime request failed: {method} {url} returned HTTP {exc.code}"
                    + (f" with body: {error_body}" if error_body else "")
                ),
                stderr=True,
            )
            if exc.code == 401:
                raise RuntimeRequestError(
                    self._akida_unauthorized_message(host, url),
                    kind="http",
                    url=url,
                    status_code=exc.code,
                    response_body=error_body,
                ) from exc
            raise RuntimeRequestError(
                f"Runtime request failed for {method} {url}: HTTP {exc.code}"
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
            self._emit_akida_terminal_log(
                host,
                f"runtime request failed: {method} {url} {detail}",
                stderr=True,
            )
            raise RuntimeRequestError(
                f"Runtime request failed for {method} {url}: {detail}",
                kind=kind,
                url=url,
            ) from exc

    def test_akida_host_connection(self, host_id: str) -> dict[str, Any]:
        host = self._get_akida_host(host_id)
        if str(host.get("username") or "").strip():
            self._emit_akida_terminal_log(host, "testing SSH connectivity")
            self._run_akida_ssh(host, "python3 --version")
            self._emit_akida_terminal_log(host, "SSH connectivity succeeded")
            message = "SSH reachable"
        else:
            self._emit_akida_terminal_log(host, "testing HTTP connectivity")
            health = self._akida_json_request(host, "GET", "/health")
            health_status = str(health.get("status") or "ok").strip() or "ok"
            self._emit_akida_terminal_log(host, "HTTP connectivity succeeded")
            message = f"Health reachable: {health_status}"
        return _serialize_akida_host(
            self._update_akida_host_fields(
                host_id,
                state="reachable",
                lastPreflightMessage=message,
                # Also recorded as the readiness message: that is the field the
                # Dart model parses and the Akida Runtime panel renders, so
                # without it the verdict ("SSH reachable") was dropped at the
                # client boundary and the UI could only show the state label.
                lastReadinessMessage=message,
            )
        )

    def _build_local_akida_bundle(
        self, host: dict[str, Any], bundle_dir: Path
    ) -> dict[str, Any]:
        neurochip_module = self._get_module("Neurochip")
        neurochip_root = _module_root(neurochip_module)
        akida_runtime = neurochip_module.get("akidaRuntime", {})
        required_packages = akida_runtime.get("requiredPackages", [])
        if not isinstance(required_packages, list) or not all(
            isinstance(item, str) for item in required_packages
        ):
            raise RuntimeError("Neurochip Akida runtime manifest is invalid")
        # The SDK only publishes wheels for a narrow CPython range, so the
        # install script has to pick a matching interpreter rather than assume
        # the host's `python3` is usable. Both values are optional: an older
        # manifest simply keeps the built-in defaults.
        python_range = str(
            akida_runtime.get("pythonRange") or DEFAULT_AKIDA_PYTHON_RANGE
        ).strip()
        standalone_python = akida_runtime.get("standaloneCPython")
        if not isinstance(standalone_python, dict):
            standalone_python = None
        akida_contract = _load_neurochip_launcher_runtime_contract().akida
        artifact_directory = str(os.getenv("NMTK_NEUROCHIP_ARTIFACT_DIR") or "").strip()
        wheel_path = None
        if artifact_directory:
            wheel_path = discover_neurochip_runtime_artifact(
                Path(artifact_directory)
            ).wheel_path
        return build_akida_host_bundle(
            bundle_dir,
            repo_root=neurochip_root,
            required_packages=required_packages,
            wheel_path=wheel_path,
            install_root=str(host["remoteInstallRoot"]),
            service_user=str(host["serviceUser"]),
            venv_path=str(host["remoteVenvPath"]),
            runtime_service_name=str(host["runtimeServiceName"]),
            control_service_name=str(host["controlServiceName"]),
            runtime_port=int(host.get("port") or akida_contract.runtime_port),
            control_port=int(host.get("controlPort") or akida_contract.control_port),
            token_path=str(host["tokenPath"]),
            install_status_path=str(host["installStatusPath"]),
            python_range=python_range,
            standalone_python=standalone_python,
        )

    def _remote_akida_install_status_path(self, host: dict[str, Any]) -> str:
        return str(
            host.get("installStatusPath")
            or _load_neurochip_launcher_runtime_contract().akida.install_status_path_for(
                str(host["remoteInstallRoot"])
            )
        )

    def _read_remote_akida_install_status(self, host: dict[str, Any]) -> dict[str, Any]:
        raw = self._run_akida_ssh(
            host, f"cat {self._remote_akida_install_status_path(host)}"
        )
        raw = raw.strip()
        if not raw:
            raise RuntimeError("Remote Akida install status file is empty")
        try:
            decoded = json.loads(raw)
        except json.JSONDecodeError as exc:
            raise RuntimeError(
                f"Remote Akida install status is not valid JSON: {raw}"
            ) from exc
        if not isinstance(decoded, dict):
            raise RuntimeError("Remote Akida install status must decode to an object")
        return decoded

    def _read_remote_akida_token(
        self,
        host: dict[str, Any],
        *,
        install_status: dict[str, Any] | None = None,
    ) -> str:
        token_path = str(
            host.get("tokenPath")
            or _load_neurochip_launcher_runtime_contract().akida.token_path_for(
                str(host["remoteInstallRoot"])
            )
        ).strip()
        install_mode = str(
            (install_status or host.get("lastInstallStatus") or {}).get("installMode")
            or ""
        ).strip()
        username = str(host.get("username") or "").strip()
        service_user = str(host.get("serviceUser") or "").strip()
        command = f"cat {shlex.quote(token_path)}"
        display_command = command
        if install_mode != "user-space" and service_user and service_user != username:
            if str(host.get("authMode") or "").strip() == "password" and str(
                host.get("password") or ""
            ):
                password = str(host.get("password") or "")
                command = (
                    f"printf '%s\\n' {shlex.quote(password)} | sudo -S -p '' {command}"
                )
                display_command = (
                    "printf '%s\\n' <redacted> "
                    f"| sudo -S -p '' cat {shlex.quote(token_path)}"
                )
            else:
                command = f"sudo {command}"
                display_command = command
        return self._run_akida_ssh(
            host,
            command,
            display_command=display_command,
        ).strip()

    def _readiness_message(self, message: str) -> str:
        """Keep raw SDK and driver output out of the user-facing field.

        The transport-level failure path already rewrites errno text for the
        launcher-to-host hop, but an SDK-internal failure arrives inside a 200
        JSON body and never passes through it -- which is how
        "Error reading at 0xf0000010 len 4: err(110)" reached a user.

        The paired host classifies board faults itself and sends a plain
        sentence, so anything still carrying a raw errno or register address
        here means the host could not name the cause. Say that, rather than
        forwarding a register address nobody can act on. The raw text stays on
        lastPreflightMessage, which no Akida client model reads.
        """
        if not _RAW_DEVICE_ERROR_PATTERN.search(message):
            return message
        return (
            "The Akida board could not be reached. Switch the host fully off "
            "and on again, then re-check."
        )

    def _apply_preflight_to_akida_host(
        self,
        host_id: str,
        preflight: dict[str, Any],
        *,
        runtime_status: dict[str, Any] | None = None,
        install_status: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        status = str(preflight.get("preflight_status") or "").strip().lower()
        message = str(preflight.get("preflight_message") or "").strip()
        runtime_target = str(preflight.get("runtime_target") or "").strip()
        sdk_status = str(preflight.get("sdk_status") or "").strip()
        if status == PREFLIGHT_DEGRADED and runtime_status is not None:
            if _akida_hardware_runtime_ready(runtime_status):
                status = PREFLIGHT_OK
                message = "Akida hardware runtime is ready."
                runtime_target = str(runtime_status.get("runtime_target") or "").strip()
                sdk_status = str(runtime_status.get("sdk_status") or "").strip()
        state = "preflight_failed"
        if status == PREFLIGHT_OK:
            state = (
                "ready"
                if runtime_target == "hardware"
                else "degraded_optional_capability"
            )
        elif status == PREFLIGHT_DEGRADED:
            state = (
                "simulator_only"
                if runtime_target in {"software_fallback", "akd1000_simulator"}
                else "degraded_optional_capability"
            )
        # Sanitised before the user-space note is appended, so the advice
        # survives onto the readiness message instead of being discarded with
        # the raw text it was joined to.
        readiness_message = self._readiness_message(message)
        install_mode = str((install_status or {}).get("installMode") or "").strip()
        if install_mode == "user-space":
            upgrade_note = _akida_user_space_upgrade_message(
                str(self._get_akida_host(host_id).get("username") or "")
            )
            message = " ".join(part for part in (message, upgrade_note) if part)
            readiness_message = " ".join(
                part for part in (readiness_message, upgrade_note) if part
            )
            if state == "ready":
                state = "degraded_optional_capability"
        return self._update_akida_host_fields(
            host_id,
            state=state,
            lastPreflightStatus=status,
            # Raw here, sanitised on the readiness field: this one is the
            # developer's copy and no Akida client model reads it.
            lastPreflightMessage=message,
            lastSdkStatus=sdk_status,
            lastRuntimeTarget=runtime_target,
            lastStatus=runtime_status,
            lastInstallStatus=install_status,
            lastReadinessMessage=readiness_message,
            lastVerifiedAt=datetime.now(timezone.utc).isoformat(),
        )

    def _provision_akida_host_unlocked(
        self,
        host_id: str,
        *,
        progress: Callable[[str, int, str], None] | None = None,
    ) -> dict[str, Any]:
        def report(stage: str, percent: int, message: str) -> None:
            if progress is not None:
                progress(stage, percent, message)

        host = self._update_akida_host_fields(
            host_id,
            state="bootstrapping",
            lastReadinessMessage="Starting blank-host bootstrap.",
        )
        install_status: dict[str, Any] = {}
        try:
            report("validating_host", 10, "Validating Akida host access")
            # The asynchronous release updater owns an explicit connectivity
            # stage. Keep the legacy synchronous Provision/Repair endpoints'
            # SSH command sequence stable for compatibility; their first
            # bundle operation still fails safely when the host is unreachable.
            if progress is not None:
                self.test_akida_host_connection(host_id)
            with tempfile.TemporaryDirectory(prefix="akida-host-bundle-") as tmp_dir:
                bundle_dir = Path(tmp_dir) / "bundle"
                bundle_dir.mkdir(parents=True, exist_ok=True)
                report("packaging", 25, "Packaging the Neurochip runtime")
                self._emit_akida_terminal_log(host, "building local Akida host bundle")
                self._build_local_akida_bundle(host, bundle_dir)
                remote_bundle_parent = "/tmp"
                remote_bundle_dir = f"{remote_bundle_parent}/{bundle_dir.name}"
                self._run_akida_ssh(
                    host,
                    f"rm -rf {remote_bundle_dir}",
                )
                report("uploading", 40, "Uploading the Neurochip runtime")
                self._emit_akida_terminal_log(host, "uploading provisioning bundle")
                self._run_akida_scp(
                    host, bundle_dir, remote_bundle_parent, recursive=True
                )
                host = self._update_akida_host_fields(
                    host_id,
                    state="installing_runtime",
                    lastReadinessMessage="Running remote install script.",
                )
                report("installing", 55, "Installing the staged Neurochip runtime")
                self._emit_akida_terminal_log(host, "running remote install script")
                install_command = " ".join(
                    [
                        f"INSTALL_ROOT={shlex.quote(str(host['remoteInstallRoot']))}",
                        f"SERVICE_USER={shlex.quote(str(host['serviceUser']))}",
                        f"VENV_PATH={shlex.quote(str(host['remoteVenvPath']))}",
                        f"RUNTIME_SERVICE_NAME={shlex.quote(str(host['runtimeServiceName']))}",
                        f"CONTROL_SERVICE_NAME={shlex.quote(str(host['controlServiceName']))}",
                        f"RUNTIME_PORT={shlex.quote(str(host['port']))}",
                        f"CONTROL_PORT={shlex.quote(str(host['controlPort']))}",
                        f"TOKEN_PATH={shlex.quote(str(host['tokenPath']))}",
                        f"bash {shlex.quote(remote_bundle_dir)}/install-akida-host.sh",
                    ]
                )
                install_command, display_install_command = (
                    self._akida_remote_command_with_sudo_password(
                        host,
                        install_command,
                    )
                )
                install_output = self._run_akida_ssh(
                    host,
                    install_command,
                    display_command=display_install_command,
                )
                install_status = (
                    _extract_install_status_from_output(install_output) or {}
                )
                if not install_status:
                    install_status = self._read_remote_akida_install_status(host)
                host = self._update_akida_host_fields(
                    host_id,
                    remoteInstallRoot=str(
                        install_status.get("installRoot") or host["remoteInstallRoot"]
                    ).strip(),
                    remoteVenvPath=str(
                        install_status.get("venvPath") or host["remoteVenvPath"]
                    ).strip(),
                    serviceUser=str(
                        install_status.get("serviceUser") or host["serviceUser"]
                    ).strip(),
                    tokenPath=str(
                        install_status.get("tokenPath") or host["tokenPath"]
                    ).strip(),
                    installStatusPath=str(
                        install_status.get("installStatusPath")
                        or host["installStatusPath"]
                    ).strip(),
                    lastInstallStatus=install_status,
                )
                token_value = self._read_remote_akida_token(
                    host,
                    install_status=install_status,
                )
                if not token_value:
                    raise RuntimeError(
                        "Remote Akida API token read returned an empty value"
                    )
                host = self._update_akida_host_fields(
                    host_id,
                    credentialRef=token_value,
                    runtimeApiUrl=_default_akida_base_url(
                        str(host["host"]), int(host["port"])
                    ),
                    controlApiUrl=_default_akida_control_url(
                        str(host["host"]), int(host["controlPort"])
                    ),
                    hostOs=str(install_status.get("hostOs") or "").strip(),
                    pythonVersion=str(
                        install_status.get("pythonVersion") or ""
                    ).strip(),
                    state="verifying_sdk",
                    lastInstallStatus=install_status,
                    lastReadinessMessage="Remote install completed; verifying SDK and hardware.",
                )
            report("verifying", 90, "Verifying the installed Neurochip runtime")
            result = self.fetch_akida_host_preflight(host_id)
            result["installStatus"] = install_status
            return result
        except Exception as exc:  # noqa: BLE001
            self._emit_akida_terminal_log(
                host, f"runtime provisioning failed: {exc}", stderr=True
            )
            updated = self._update_akida_host_fields(
                host_id,
                state="provision_failed",
                lastPreflightMessage=str(exc),
                lastReadinessMessage=str(exc),
                lastInstallStatus=install_status if install_status else None,
            )
            return {
                "host": _serialize_akida_host(updated),
                "error": str(exc),
                "installStatus": install_status if install_status else None,
            }

    def _provision_akida_host(
        self,
        host_id: str,
        *,
        progress: Callable[[str, int, str], None] | None = None,
    ) -> dict[str, Any]:
        """Run one locked installer shared by update, Provision, and Repair."""
        with self._lock:
            locks = getattr(self, "_akida_host_update_locks", None)
            if not isinstance(locks, dict):
                locks = {}
                self._akida_host_update_locks = locks
            host_lock = locks.setdefault(host_id, threading.Lock())
        if not host_lock.acquire(blocking=False):
            host = self._get_akida_host(host_id)
            return {
                "host": _serialize_akida_host(host),
                "error": "An Akida runtime update is already running for this host.",
                "installStatus": host.get("lastInstallStatus"),
            }
        try:
            return self._provision_akida_host_unlocked(host_id, progress=progress)
        finally:
            host_lock.release()

    def provision_akida_host(self, host_id: str) -> dict[str, Any]:
        return self._provision_akida_host(host_id)

    def repair_akida_host(self, host_id: str) -> dict[str, Any]:
        return self.provision_akida_host(host_id)

    def restart_akida_host_services(self, host_id: str) -> dict[str, Any]:
        host = self._get_akida_host(host_id)
        install_status = self._read_remote_akida_install_status(host)
        install_mode = (
            str(install_status.get("installMode") or "unknown").strip() or "unknown"
        )
        if install_mode == "user-space":
            message = _akida_user_space_upgrade_message(str(host.get("username") or ""))
            updated = self._update_akida_host_fields(
                host_id,
                state="degraded_optional_capability",
                lastPreflightStatus=PREFLIGHT_DEGRADED,
                lastPreflightMessage=message,
            )
            self._emit_akida_terminal_log(host, message)
            return {
                "host": _serialize_akida_host(updated),
                "warning": message,
                "installStatus": install_status,
            }
        self._emit_akida_terminal_log(host, "restarting remote Akida services")
        self._run_akida_ssh(
            host,
            (
                f"sudo systemctl restart {host['runtimeServiceName']}.service "
                f"{host['controlServiceName']}.service"
            ),
        )
        result = self.fetch_akida_host_preflight(host_id)
        result["installStatus"] = install_status
        return result

    def fetch_akida_host_preflight(self, host_id: str) -> dict[str, Any]:
        host = self._get_akida_host(host_id)
        self._emit_akida_terminal_log(host, "requesting runtime preflight")
        verification: dict[str, Any] = {}
        runtime_status: dict[str, Any] | None = None
        install_status: dict[str, Any] | None = None
        try:
            if _resolved_akida_control_api_url(host):
                try:
                    doctor = self._akida_control_json_request(
                        host,
                        "GET",
                        "/api/remote-akida/doctor",
                        emit_terminal_errors=False,
                    )
                    preflight = doctor.get("preflight")
                    if isinstance(preflight, dict):
                        verification = preflight
                    runtime_status = (
                        doctor.get("runtimeStatus")
                        if isinstance(doctor.get("runtimeStatus"), dict)
                        else None
                    )
                    install_status = (
                        doctor.get("installStatus")
                        if isinstance(doctor.get("installStatus"), dict)
                        else None
                    )
                except Exception as control_exc:  # noqa: BLE001
                    self._emit_akida_terminal_log(
                        host,
                        (
                            "remote control API unavailable during preflight; "
                            f"falling back to runtime status: {control_exc}"
                        ),
                        stderr=True,
                    )
                    verification = self._akida_json_request(
                        host, "GET", "/api/neurochip/akida/status"
                    )
                    runtime_status = verification
            else:
                verification = self._akida_json_request(
                    host, "GET", "/api/neurochip/akida/status"
                )
                runtime_status = verification
        except Exception as exc:  # noqa: BLE001
            _url = _resolved_akida_base_url(host).rstrip("/") or "(unknown)"
            _raw = str(exc)
            if "111" in _raw or "connection refused" in _raw.lower():
                _msg = (
                    f"Akida runtime service not reachable at {_url}. "
                    "Ensure the Neurochip runtime service is running on the target host."
                )
            elif "timed out" in _raw.lower() or "timeout" in _raw.lower():
                _msg = (
                    f"Connection to Akida runtime at {_url} timed out. "
                    "Check network connectivity and firewall rules."
                )
            else:
                _msg = _raw
            verification = {
                "preflight_status": PREFLIGHT_FAILED,
                "preflight_message": _msg,
                "sdk_status": "",
                "runtime_target": "",
                "sdk_available": False,
                "sdk_issues": [],
                "sdk_issue_detail": _raw,
                "environment_checks": None,
            }
        if "preflight_status" not in verification:
            preflight_status = _preflight_status_for_akida_verification(verification)
            verification = {
                "preflight_status": preflight_status,
                "preflight_message": _describe_akida_preflight(verification),
                "sdk_status": str(verification.get("sdk_status") or "").strip(),
                "runtime_target": str(verification.get("runtime_target") or "").strip(),
                "sdk_available": bool(verification.get("sdk_available")),
                "sdk_issues": verification.get("sdk_issues")
                if isinstance(verification.get("sdk_issues"), list)
                else [],
                "sdk_issue_detail": str(
                    verification.get("sdk_issue_detail") or ""
                ).strip(),
                "environment_checks": verification.get("environment_checks")
                if isinstance(verification.get("environment_checks"), dict)
                else None,
                "sdk_verification": verification,
            }
        self._emit_akida_terminal_log(
            host,
            f"preflight {verification.get('preflight_status')}: {verification.get('preflight_message')}",
        )
        updated = self._apply_preflight_to_akida_host(
            host_id,
            verification,
            runtime_status=runtime_status,
            install_status=install_status,
        )
        if str(updated.get("hostOs") or "").strip() == "" and install_status:
            updated = self._update_akida_host_fields(
                host_id,
                hostOs=str(install_status.get("hostOs") or "").strip(),
                pythonVersion=str(install_status.get("pythonVersion") or "").strip(),
            )
        return {
            "host": _serialize_akida_host(updated),
            "preflight": verification,
            "status": runtime_status,
            "installStatus": install_status,
        }

    def fetch_akida_host_status(self, host_id: str) -> dict[str, Any]:
        host = self._get_akida_host(host_id)
        self._emit_akida_terminal_log(host, "requesting runtime status")
        if _resolved_akida_control_api_url(host):
            try:
                doctor = self._akida_control_json_request(
                    host,
                    "GET",
                    "/api/remote-akida/doctor",
                    emit_terminal_errors=False,
                )
                runtime_status = (
                    doctor.get("runtimeStatus")
                    if isinstance(doctor.get("runtimeStatus"), dict)
                    else {}
                )
                preflight = (
                    doctor.get("preflight")
                    if isinstance(doctor.get("preflight"), dict)
                    else {}
                )
                updated = self._apply_preflight_to_akida_host(
                    host_id,
                    preflight,
                    runtime_status=runtime_status,
                    install_status=doctor.get("installStatus")
                    if isinstance(doctor.get("installStatus"), dict)
                    else None,
                )
                return {
                    "host": _serialize_akida_host(updated),
                    "status": runtime_status,
                }
            except Exception as control_exc:  # noqa: BLE001
                self._emit_akida_terminal_log(
                    host,
                    (
                        "remote control API unavailable during status poll; "
                        f"falling back to runtime status: {control_exc}"
                    ),
                    stderr=True,
                )
        status = self._akida_json_request(host, "GET", "/api/neurochip/akida/status")
        updated = self._update_akida_host_fields(
            host_id,
            state=_akida_host_state_for_status(host, status),
            lastStatus=status,
        )
        return {"host": _serialize_akida_host(updated), "status": status}
