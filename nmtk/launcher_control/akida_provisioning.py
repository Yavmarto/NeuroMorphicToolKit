"""Akida provisioning, restart, preflight, and status coordination."""

from __future__ import annotations

import json
import os
import shlex
import tempfile
import threading
from collections.abc import Callable
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Protocol

from .akida_preflight import evaluate_akida_preflight, readiness_message
from .hardware_models import (
    _akida_host_state_for_status,
    _akida_user_space_upgrade_message,
    _default_akida_base_url,
    _default_akida_control_url,
    _describe_akida_preflight,
    _extract_install_status_from_output,
    _load_neurochip_launcher_runtime_contract,
    _preflight_status_for_akida_verification,
    _resolved_akida_base_url,
    _resolved_akida_control_api_url,
    _serialize_akida_host,
)
from .provisioning_helpers import DEFAULT_AKIDA_PYTHON_RANGE, build_akida_host_bundle
from .runtime_artifact import discover_neurochip_runtime_artifact
from .runtime_shared import _module_root
from .state_contracts import PREFLIGHT_DEGRADED, PREFLIGHT_FAILED


class AkidaProvisioningOwnerProtocol(Protocol):
    """State callbacks retained while the launcher façade remains compatible."""

    def _get_akida_host(self, host_id: str) -> dict[str, Any]: ...

    def _update_akida_host_fields(
        self, host_id: str, **fields: Any
    ) -> dict[str, Any]: ...

    def _emit_akida_terminal_log(
        self, host: dict[str, Any], message: str, *, stderr: bool = False
    ) -> None: ...

    def _run_akida_ssh(
        self,
        host: dict[str, Any],
        remote_command: str,
        *,
        display_command: str | None = None,
    ) -> str: ...

    def _run_akida_scp(
        self,
        host: dict[str, Any],
        local_path: Path,
        remote_path: str,
        *,
        recursive: bool = False,
    ) -> None: ...

    def _akida_remote_command_with_sudo_password(
        self, host: dict[str, Any], remote_command: str
    ) -> tuple[str, str]: ...

    def _akida_control_json_request(
        self,
        host: dict[str, Any],
        method: str,
        path: str,
        payload: dict[str, Any] | None = None,
        *,
        emit_terminal_errors: bool = True,
        allow_recovery: bool = True,
    ) -> dict[str, Any]: ...

    def _akida_json_request(
        self,
        host: dict[str, Any],
        method: str,
        path: str,
        payload: dict[str, Any] | None = None,
        *,
        allow_recovery: bool = True,
        timeout: float = 15.0,
    ) -> dict[str, Any]: ...

    def _get_module(self, module_id: str) -> dict[str, Any]: ...

    def _build_local_akida_bundle(
        self, host: dict[str, Any], bundle_dir: Path
    ) -> dict[str, Any]: ...

    def _read_remote_akida_install_status(
        self, host: dict[str, Any]
    ) -> dict[str, Any]: ...

    def _read_remote_akida_token(
        self,
        host: dict[str, Any],
        *,
        install_status: dict[str, Any] | None = None,
    ) -> str: ...

    def _apply_preflight_to_akida_host(
        self,
        host_id: str,
        preflight: dict[str, Any],
        *,
        runtime_status: dict[str, Any] | None = None,
        install_status: dict[str, Any] | None = None,
    ) -> dict[str, Any]: ...

    def _provision_akida_host_unlocked(
        self,
        host_id: str,
        *,
        progress: Callable[[str, int, str], None] | None = None,
    ) -> dict[str, Any]: ...

    def fetch_akida_host_preflight(self, host_id: str) -> dict[str, Any]: ...


class AkidaProvisioningCoordinator:
    """Coordinate paired-host installation and readiness without owning state."""

    def __init__(self, owner: AkidaProvisioningOwnerProtocol) -> None:
        self._owner = owner
        self._host_locks_guard = threading.Lock()
        self._host_locks: dict[str, threading.Lock] = {}

    def _get_akida_host(self, host_id: str) -> dict[str, Any]:
        return self._owner._get_akida_host(host_id)

    def _update_akida_host_fields(self, host_id: str, **fields: Any) -> dict[str, Any]:
        return self._owner._update_akida_host_fields(host_id, **fields)

    def _emit_akida_terminal_log(
        self, host: dict[str, Any], message: str, *, stderr: bool = False
    ) -> None:
        self._owner._emit_akida_terminal_log(host, message, stderr=stderr)

    def _run_akida_ssh(
        self,
        host: dict[str, Any],
        remote_command: str,
        *,
        display_command: str | None = None,
    ) -> str:
        if display_command is None:
            return self._owner._run_akida_ssh(host, remote_command)
        return self._owner._run_akida_ssh(
            host, remote_command, display_command=display_command
        )

    def _run_akida_scp(
        self,
        host: dict[str, Any],
        local_path: Path,
        remote_path: str,
        *,
        recursive: bool = False,
    ) -> None:
        self._owner._run_akida_scp(host, local_path, remote_path, recursive=recursive)

    def _akida_remote_command_with_sudo_password(
        self, host: dict[str, Any], remote_command: str
    ) -> tuple[str, str]:
        return self._owner._akida_remote_command_with_sudo_password(
            host, remote_command
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
        if payload is None and emit_terminal_errors and allow_recovery:
            return self._owner._akida_control_json_request(host, method, path)
        if payload is None and allow_recovery:
            return self._owner._akida_control_json_request(
                host,
                method,
                path,
                emit_terminal_errors=emit_terminal_errors,
            )
        return self._owner._akida_control_json_request(
            host,
            method,
            path,
            payload,
            emit_terminal_errors=emit_terminal_errors,
            allow_recovery=allow_recovery,
        )

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
        if payload is None and allow_recovery and timeout == 15.0:
            return self._owner._akida_json_request(host, method, path)
        return self._owner._akida_json_request(
            host,
            method,
            path,
            payload,
            allow_recovery=allow_recovery,
            timeout=timeout,
        )

    def _get_module(self, module_id: str) -> dict[str, Any]:
        return self._owner._get_module(module_id)

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
            raise TypeError("Remote Akida install status must decode to an object")
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
        return readiness_message(message)

    def _apply_preflight_to_akida_host(
        self,
        host_id: str,
        preflight: dict[str, Any],
        *,
        runtime_status: dict[str, Any] | None = None,
        install_status: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        host = self._get_akida_host(host_id)
        evaluation = evaluate_akida_preflight(
            host,
            preflight,
            runtime_status=runtime_status,
            install_status=install_status,
        )
        return self._update_akida_host_fields(
            host_id,
            state=evaluation.state,
            lastPreflightStatus=evaluation.status,
            lastPreflightMessage=evaluation.message,
            lastSdkStatus=evaluation.sdk_status,
            lastRuntimeTarget=evaluation.runtime_target,
            lastStatus=runtime_status,
            lastInstallStatus=install_status,
            lastReadinessMessage=evaluation.readiness_message,
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
                self._owner._build_local_akida_bundle(host, bundle_dir)
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
                    install_status = self._owner._read_remote_akida_install_status(host)
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
                token_value = self._owner._read_remote_akida_token(
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
            result = self._owner.fetch_akida_host_preflight(host_id)
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
        with self._host_locks_guard:
            host_lock = self._host_locks.setdefault(host_id, threading.Lock())
        if not host_lock.acquire(blocking=False):
            host = self._get_akida_host(host_id)
            return {
                "host": _serialize_akida_host(host),
                "error": "An Akida runtime update is already running for this host.",
                "installStatus": host.get("lastInstallStatus"),
            }
        try:
            return self._owner._provision_akida_host_unlocked(
                host_id, progress=progress
            )
        finally:
            host_lock.release()

    def provision_akida_host(self, host_id: str) -> dict[str, Any]:
        return self._provision_akida_host(host_id)

    def repair_akida_host(self, host_id: str) -> dict[str, Any]:
        return self.provision_akida_host(host_id)

    def restart_akida_host_services(self, host_id: str) -> dict[str, Any]:
        host = self._get_akida_host(host_id)
        install_status = self._owner._read_remote_akida_install_status(host)
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
        result = self._owner.fetch_akida_host_preflight(host_id)
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
        updated = self._owner._apply_preflight_to_akida_host(
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
                raw_preflight = doctor.get("preflight")
                preflight: dict[str, Any] = (
                    dict(raw_preflight) if isinstance(raw_preflight, dict) else {}
                )
                updated = self._owner._apply_preflight_to_akida_host(
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


__all__ = ["AkidaProvisioningCoordinator", "AkidaProvisioningOwnerProtocol"]
