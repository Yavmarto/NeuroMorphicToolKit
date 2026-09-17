"""Compatibility façade for typed PYNQ board services.

All new PYNQ behavior belongs in the repository, remote-client, runtime-proxy,
preflight, or provisioning modules. Launcher state and tests keep this mixin for
one compatibility release so routes and established private patch points remain
stable while internal ownership moves to injected components.
"""

from __future__ import annotations

from collections.abc import Callable
from contextlib import AbstractContextManager
from pathlib import Path
from typing import Any

from .pynq_board_repository import PynqBoardRepository
from .pynq_provisioning import PYNQ_DEVICE_GROUPS, PynqProvisioningCoordinator
from .pynq_remote_client import PynqRemoteClient
from .pynq_runtime_proxy import PynqRuntimeProxyService
from .state_contracts import (
    PYNQ_RUNTIME_LOG_TAIL_LINES,
    LauncherSettingsRecord,
    PynqBoardState,
)


class PynqServiceMixin:
    """Delegate the legacy launcher state surface to typed PYNQ components."""

    _lock: AbstractContextManager[Any]
    _settings: LauncherSettingsRecord
    _persist_settings: Callable[[], None]
    _pynq_boards: PynqBoardRepository
    _pynq_remote: PynqRemoteClient
    _pynq_proxy: PynqRuntimeProxyService
    _pynq_provisioning: PynqProvisioningCoordinator

    def _init_pynq_components(self) -> None:
        """Construct PYNQ services after persisted launcher settings are loaded."""
        self._pynq_boards = PynqBoardRepository(
            settings=self._settings,
            lock=self._lock,
            persist=self._persist_settings,
        )
        self._pynq_remote = PynqRemoteClient()
        self._pynq_proxy = PynqRuntimeProxyService(self)
        self._pynq_provisioning = PynqProvisioningCoordinator(self)

    def list_pynq_boards(self) -> list[dict[str, Any]]:
        return self._pynq_boards.list()

    def get_pynq_board(self, board_id: str) -> dict[str, Any]:
        return self._pynq_boards.get_serialized(board_id)

    def create_pynq_board(self, payload: dict[str, Any]) -> dict[str, Any]:
        return self._pynq_boards.create(payload)

    def update_pynq_board(
        self, board_id: str, payload: dict[str, Any]
    ) -> dict[str, Any]:
        return self._pynq_boards.update(board_id, payload)

    def delete_pynq_board(self, board_id: str) -> None:
        self._pynq_boards.delete(board_id)

    def _get_pynq_board(self, board_id: str) -> dict[str, Any]:
        return dict(self._pynq_boards.get(board_id))

    def _update_pynq_board_fields(self, board_id: str, **fields: Any) -> dict[str, Any]:
        return dict(self._pynq_boards.update_fields(board_id, **fields))

    def _normalize_updated_pynq_board(
        self,
        board: dict[str, Any],
        updates: dict[str, Any],
    ) -> dict[str, Any]:
        return dict(self._pynq_boards.normalize_update(board, updates))

    def _emit_pynq_terminal_log(
        self, board: dict[str, Any], message: str, *, stderr: bool = False
    ) -> None:
        self._pynq_remote.emit_log(board, message, stderr=stderr)

    def _prepare_ssh_invocation(
        self,
        board: dict[str, Any],
        *,
        copy_mode: bool = False,
    ) -> tuple[list[str], dict[str, str] | None, Callable[[], None] | None]:
        return self._pynq_remote.prepare_ssh_invocation(board, copy_mode=copy_mode)

    def _run_ssh(self, board: dict[str, Any], remote_command: str) -> str:
        return self._pynq_remote.run_ssh(board, remote_command)

    def _run_ssh_sudo(
        self,
        board: dict[str, Any],
        remote_command: str,
        *,
        timeout: float = 60.0,
    ) -> str:
        return self._pynq_remote.run_ssh_sudo(board, remote_command, timeout=timeout)

    def _run_scp(
        self,
        board: dict[str, Any],
        local_path: Path,
        remote_path: str,
        *,
        recursive: bool = False,
    ) -> None:
        self._pynq_remote.run_scp(board, local_path, remote_path, recursive=recursive)

    def _runtime_json_request(
        self,
        board: dict[str, Any],
        method: str,
        path: str,
        payload: dict[str, Any] | None = None,
        *,
        timeout: float = 15.0,
    ) -> dict[str, Any]:
        return self._pynq_remote.json_request(
            board, method, path, payload, timeout=timeout
        )

    def _ensure_pynq_device_group_access(self, board: dict[str, Any]) -> None:
        self._pynq_provisioning._ensure_pynq_device_group_access(board)

    def _remote_pynq_install_status_path(self, board: dict[str, Any]) -> str:
        return self._pynq_provisioning._remote_pynq_install_status_path(board)

    def _read_remote_pynq_install_status(self, board: dict[str, Any]) -> dict[str, Any]:
        return self._pynq_provisioning._read_remote_pynq_install_status(board)

    def _wait_for_board_agent_health(
        self,
        board: dict[str, Any],
        timeout: float | None = None,
    ) -> None:
        self._pynq_provisioning._wait_for_board_agent_health(board, timeout)

    def _emit_runtime_log_tail(
        self,
        board: dict[str, Any],
        install_status: dict[str, Any],
        *,
        lines: int = PYNQ_RUNTIME_LOG_TAIL_LINES,
    ) -> None:
        self._pynq_provisioning._emit_runtime_log_tail(
            board, install_status, lines=lines
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
        return self._pynq_provisioning._build_remote_pynq_user_space_launch_command(
            agent_venv_path=agent_venv_path,
            pynq_python_path=pynq_python_path,
            install_status_path=install_status_path,
            overlay_dir=overlay_dir,
            runtime_log_path=runtime_log_path,
            agent_executable_name=agent_executable_name,
        )

    def _run_ssh_detached(
        self,
        board: dict[str, Any],
        remote_command: str,
        *,
        ssh_timeout: float = 15.0,
    ) -> None:
        self._pynq_provisioning._run_ssh_detached(
            board, remote_command, ssh_timeout=ssh_timeout
        )

    def _restart_user_space_agent(
        self, board: dict[str, Any], install_status: dict[str, Any]
    ) -> None:
        self._pynq_provisioning._restart_user_space_agent(board, install_status)

    def _run_ssh_privileged(
        self,
        board: dict[str, Any],
        remote_command: str,
        *,
        timeout: float = 60.0,
    ) -> str:
        return self._pynq_provisioning._run_ssh_privileged(
            board, remote_command, timeout=timeout
        )

    def _promote_pynq_install_to_systemd(
        self,
        board: dict[str, Any],
        remote_bundle_dir: str,
        install_status: dict[str, Any],
    ) -> dict[str, Any]:
        return self._pynq_provisioning._promote_pynq_install_to_systemd(
            board, remote_bundle_dir, install_status
        )

    def _write_remote_pynq_install_mode(
        self, board: dict[str, Any], install_mode: str, message: str
    ) -> None:
        self._pynq_provisioning._write_remote_pynq_install_mode(
            board, install_mode, message
        )

    def _confirm_remote_pynq_agent_process(
        self, board: dict[str, Any], agent_executable: str
    ) -> None:
        self._pynq_provisioning._confirm_remote_pynq_agent_process(
            board, agent_executable
        )

    def _apply_preflight_to_board(
        self,
        board_id: str,
        preflight: dict[str, Any],
        *,
        fallback_error_state: PynqBoardState = "error",
    ) -> dict[str, Any]:
        return self._pynq_provisioning._apply_preflight_to_board(
            board_id, preflight, fallback_error_state=fallback_error_state
        )

    def test_pynq_board_connection(self, board_id: str) -> dict[str, Any]:
        return self._pynq_provisioning.test_pynq_board_connection(board_id)

    def fetch_pynq_board_preflight(
        self,
        board_id: str,
        *,
        request_timeout: float | None = None,
    ) -> dict[str, Any]:
        return self._pynq_provisioning.fetch_pynq_board_preflight(
            board_id, request_timeout=request_timeout
        )

    def _refresh_pynq_board_preflight(
        self, board_id: str, *, stage: str
    ) -> dict[str, Any]:
        return self._pynq_provisioning._refresh_pynq_board_preflight(
            board_id, stage=stage
        )

    def fetch_pynq_board_status(self, board_id: str) -> dict[str, Any]:
        return self._pynq_provisioning.fetch_pynq_board_status(board_id)

    def _build_local_pynq_bundle(
        self, board: dict[str, Any], bundle_dir: Path
    ) -> dict[str, Any]:
        return self._pynq_provisioning._build_local_pynq_bundle(board, bundle_dir)

    def _inspect_local_pynq_overlay_package(self) -> dict[str, Any]:
        return self._pynq_provisioning._inspect_local_pynq_overlay_package()

    def provision_pynq_board(self, board_id: str) -> dict[str, Any]:
        return self._pynq_provisioning.provision_pynq_board(board_id)

    def install_pynq_overlay_assets(self, board_id: str) -> dict[str, Any]:
        return self._pynq_provisioning.install_pynq_overlay_assets(board_id)

    def restart_pynq_runtime(self, board_id: str) -> dict[str, Any]:
        return self._pynq_provisioning.restart_pynq_runtime(board_id)

    def proxy_pynq_deploy(
        self, board_id: str, payload: dict[str, Any]
    ) -> dict[str, Any]:
        return self._pynq_proxy.deploy(board_id, payload)

    def proxy_pynq_verify(
        self, board_id: str, payload: dict[str, Any]
    ) -> dict[str, Any]:
        return self._pynq_proxy.verify(board_id, payload)

    def proxy_pynq_run(self, board_id: str, payload: dict[str, Any]) -> dict[str, Any]:
        return self._pynq_proxy.run(board_id, payload)

    def proxy_pynq_runtime_status(self, board_id: str) -> dict[str, Any]:
        return self._pynq_proxy.status(board_id)


__all__ = ["PYNQ_DEVICE_GROUPS", "PynqServiceMixin"]
