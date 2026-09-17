"""Compatibility façade for typed Akida host services.

All new Akida behavior belongs in the repository, remote-client, runtime-proxy,
preflight, or provisioning modules. Launcher state and tests keep this mixin for
one compatibility release so public routes and established private patch points
remain stable while internal ownership moves to injected components.
"""

from __future__ import annotations

import shutil
import subprocess
import urllib
from collections.abc import Callable
from contextlib import AbstractContextManager
from pathlib import Path
from typing import Any

from .akida_host_repository import AkidaHostRepository
from .akida_provisioning import AkidaProvisioningCoordinator
from .akida_remote_client import (
    AkidaRemoteClient,
)
from .akida_remote_client import (
    akida_request_base_url as _akida_request_base_url,
)
from .akida_remote_client import (
    akida_ssh_connect_host as _akida_ssh_connect_host,
)
from .akida_runtime_proxy import AkidaRuntimeProxyService
from .state_contracts import LauncherSettingsRecord


class AkidaServiceMixin:
    """Delegate the legacy launcher state surface to typed Akida components."""

    _lock: AbstractContextManager[Any]
    _settings: LauncherSettingsRecord
    _persist_settings: Callable[[], None]
    _get_module: Callable[[str], dict[str, Any]]

    _akida_hosts: AkidaHostRepository
    _akida_remote: AkidaRemoteClient
    _akida_proxy: AkidaRuntimeProxyService
    _akida_provisioning: AkidaProvisioningCoordinator

    def _init_akida_components(self) -> None:
        """Construct Akida services after persisted launcher settings are loaded."""
        self._akida_hosts = AkidaHostRepository(
            settings=self._settings,
            lock=self._lock,
            persist=self._persist_settings,
        )
        self._akida_remote = AkidaRemoteClient(self)
        self._akida_proxy = AkidaRuntimeProxyService(self)
        self._akida_provisioning = AkidaProvisioningCoordinator(self)

    def list_akida_hosts(self) -> list[dict[str, Any]]:
        return self._akida_hosts.list()

    def get_akida_host(self, host_id: str) -> dict[str, Any]:
        return self._akida_hosts.get_serialized(host_id)

    def create_akida_host(self, payload: dict[str, Any]) -> dict[str, Any]:
        return self._akida_hosts.create(payload)

    def update_akida_host(
        self, host_id: str, payload: dict[str, Any]
    ) -> dict[str, Any]:
        return self._akida_hosts.update(host_id, payload)

    def delete_akida_host(self, host_id: str) -> None:
        self._akida_hosts.delete(host_id)

    def _get_akida_host(self, host_id: str) -> dict[str, Any]:
        return dict(self._akida_hosts.get(host_id))

    def _update_akida_host_fields(self, host_id: str, **fields: Any) -> dict[str, Any]:
        return dict(self._akida_hosts.update_fields(host_id, **fields))

    def _normalize_updated_akida_host(
        self,
        host: dict[str, Any],
        updates: dict[str, Any],
    ) -> dict[str, Any]:
        return dict(self._akida_hosts.normalize_update(host, updates))

    def proxy_akida_map(
        self,
        host_id: str,
        payload: dict[str, Any],
        *,
        bit_width: int = 4,
    ) -> dict[str, Any]:
        return self._akida_proxy.map(host_id, payload, bit_width=bit_width)

    def proxy_akida_run(self, host_id: str, payload: dict[str, Any]) -> dict[str, Any]:
        return self._akida_proxy.run(host_id, payload)

    def proxy_akida_model_job(
        self, host_id: str, payload: dict[str, Any]
    ) -> dict[str, Any]:
        return self._akida_proxy.submit_model_job(host_id, payload)

    def proxy_akida_model_job_status(self, host_id: str, job_id: str) -> dict[str, Any]:
        return self._akida_proxy.model_job_status(host_id, job_id)

    def proxy_akida_model_inference(
        self,
        host_id: str,
        model_id: str,
        payload: dict[str, Any],
    ) -> dict[str, Any]:
        return self._akida_proxy.model_inference(host_id, model_id, payload)

    def proxy_akida_model_benchmark(
        self, host_id: str, model_id: str
    ) -> dict[str, Any]:
        return self._akida_proxy.model_benchmark(host_id, model_id)

    def proxy_akida_model_visualization(
        self,
        host_id: str,
        model_id: str,
        payload: dict[str, Any],
    ) -> dict[str, Any]:
        return self._akida_proxy.model_visualization(host_id, model_id, payload)

    def _emit_akida_terminal_log(
        self, host: dict[str, Any], message: str, *, stderr: bool = False
    ) -> None:
        self._akida_remote.emit_log(host, message, stderr=stderr)

    def _prepare_akida_ssh_invocation(
        self,
        host: dict[str, Any],
        *,
        copy_mode: bool = False,
    ) -> tuple[list[str], dict[str, str] | None, Callable[[], None] | None]:
        return self._akida_remote.prepare_ssh_invocation(host, copy_mode=copy_mode)

    def _akida_remote_command_with_sudo_password(
        self,
        host: dict[str, Any],
        remote_command: str,
    ) -> tuple[str, str]:
        return self._akida_remote.remote_command_with_sudo_password(
            host, remote_command
        )

    def _run_akida_ssh(
        self,
        host: dict[str, Any],
        remote_command: str,
        *,
        display_command: str | None = None,
    ) -> str:
        return self._akida_remote.run_ssh(
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
        self._akida_remote.run_scp(host, local_path, remote_path, recursive=recursive)

    def _recover_akida_credential(self, host: dict[str, Any]) -> str:
        return self._akida_remote.recover_credential(host)

    def _akida_unauthorized_message(self, host: dict[str, Any], url: str) -> str:
        return self._akida_remote.unauthorized_message(host, url)

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
        return self._akida_remote.control_json_request(
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
        return self._akida_remote.json_request(
            host,
            method,
            path,
            payload,
            allow_recovery=allow_recovery,
            timeout=timeout,
        )

    def test_akida_host_connection(self, host_id: str) -> dict[str, Any]:
        return self._akida_provisioning.test_akida_host_connection(host_id)

    def _build_local_akida_bundle(
        self, host: dict[str, Any], bundle_dir: Path
    ) -> dict[str, Any]:
        return self._akida_provisioning._build_local_akida_bundle(host, bundle_dir)

    def _remote_akida_install_status_path(self, host: dict[str, Any]) -> str:
        return self._akida_provisioning._remote_akida_install_status_path(host)

    def _read_remote_akida_install_status(self, host: dict[str, Any]) -> dict[str, Any]:
        return self._akida_provisioning._read_remote_akida_install_status(host)

    def _read_remote_akida_token(
        self,
        host: dict[str, Any],
        *,
        install_status: dict[str, Any] | None = None,
    ) -> str:
        return self._akida_provisioning._read_remote_akida_token(
            host, install_status=install_status
        )

    def _readiness_message(self, message: str) -> str:
        return self._akida_provisioning._readiness_message(message)

    def _apply_preflight_to_akida_host(
        self,
        host_id: str,
        preflight: dict[str, Any],
        *,
        runtime_status: dict[str, Any] | None = None,
        install_status: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        return self._akida_provisioning._apply_preflight_to_akida_host(
            host_id,
            preflight,
            runtime_status=runtime_status,
            install_status=install_status,
        )

    def _provision_akida_host_unlocked(
        self,
        host_id: str,
        *,
        progress: Callable[[str, int, str], None] | None = None,
    ) -> dict[str, Any]:
        return self._akida_provisioning._provision_akida_host_unlocked(
            host_id, progress=progress
        )

    def _provision_akida_host(
        self,
        host_id: str,
        *,
        progress: Callable[[str, int, str], None] | None = None,
    ) -> dict[str, Any]:
        return self._akida_provisioning._provision_akida_host(
            host_id, progress=progress
        )

    def provision_akida_host(self, host_id: str) -> dict[str, Any]:
        return self._akida_provisioning.provision_akida_host(host_id)

    def repair_akida_host(self, host_id: str) -> dict[str, Any]:
        return self._akida_provisioning.repair_akida_host(host_id)

    def restart_akida_host_services(self, host_id: str) -> dict[str, Any]:
        return self._akida_provisioning.restart_akida_host_services(host_id)

    def fetch_akida_host_preflight(self, host_id: str) -> dict[str, Any]:
        return self._akida_provisioning.fetch_akida_host_preflight(host_id)

    def fetch_akida_host_status(self, host_id: str) -> dict[str, Any]:
        return self._akida_provisioning.fetch_akida_host_status(host_id)


__all__ = [
    "AkidaServiceMixin",
    "_akida_request_base_url",
    "_akida_ssh_connect_host",
    "shutil",
    "subprocess",
    "urllib",
]
