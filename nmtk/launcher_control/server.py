"""Host-side launcher control service for desktop and web launcher clients."""

from __future__ import annotations

import argparse
import collections
import json
import os
import shutil  # noqa: F401 - one-release monkeypatch compatibility
import subprocess
import threading
from collections.abc import Callable
from http.server import ThreadingHTTPServer
from typing import Any

from .akida_host_service import AkidaServiceMixin
from .akida_runtime_update_jobs import AkidaRuntimeUpdateJobsMixin
from .config import (  # noqa: F401
    DEPLOYMENT_SECRET_FILE,
    DEPLOYMENT_STATE_FILE,
    MODULES_MANIFEST,
    REPO_ROOT,
    SETTINGS_FILE,
    STATE_FILE,
    SUITE_API_ENV_ROOT,
    WORKSPACE_FILE,
)
from .deployment_service import DeploymentService
from .deployment_store import DeploymentStore, FileBackedSecretStore
from .doctor_service import _render_doctor_report
from .hardware_discovery import HardwareDiscoveryMixin
from .hardware_models import (  # noqa: F401
    DEFAULT_LAVA_BACKEND_PORT,
    EXPECTED_PYNQ_OVERLAY_MANIFEST,
    KNOWN_UNUSABLE_PYNQ_OVERLAYS,
    AkidaLauncherRuntimeContract,
    NeurochipLauncherRuntimeContract,
    PynqLauncherRuntimeContract,
    RuntimeRequestError,
    _akida_hardware_runtime_ready,
    _akida_host_state_for_status,
    _akida_user_space_upgrade_message,
    _default_akida_base_url,
    _default_akida_control_url,
    _default_pynq_remote_install_root,
    _default_runtime_api_url,
    _default_user_data_dir,
    _describe_akida_preflight,
    _describe_pynq_preflight,
    _effective_runtime_api_url,
    _extract_install_status_from_output,
    _inspect_staged_pynq_overlay_package,
    _is_benign_ssh_warning_line,
    _lava_backend_base_url,
    _lava_backend_reachable,
    _load_neurochip_launcher_runtime_contract,
    _mujoco_available,
    _normalize_akida_capability_snapshot,
    _normalize_akida_host,
    _normalize_akida_host_auth_mode,
    _normalize_akida_host_state,
    _normalize_akida_runtime_mode,
    _normalize_auth_mode,
    _normalize_base_url,
    _normalize_pynq_board,
    _normalize_pynq_board_state,
    _normalize_runtime_api_url_override,
    _preflight_status_for_akida_verification,
    _pynq_user_space_upgrade_message,
    _resolve_pynq_agent_health_timeout,
    _resolve_pynq_preflight_timeout,
    _resolve_pynq_run_timeout,
    _resolved_akida_base_url,
    _resolved_akida_control_api_url,
    _resolved_lava_worker_url,
    _resolved_pynq_runtime_api_url,
    _running_in_bundled_mode,
    _serialize_akida_host,
    _serialize_pynq_board,
    _ssh_failure_message,
    _status_name,
    _validate_pynq_overlay_manifest,
)
from .http_server import LauncherControlHandler
from .module_environment import (  # noqa: F401
    _candidate_environment_files,
    _current_platform_key,
    _effective_port,
    _external_service_health_url,
    _is_externally_managed_service,
    _missing_python_message,
    _module_environment_exists,
    _module_install_dir,
    _module_install_extras,
    _module_install_strategy,
    _module_optional_imports,
    _module_pyproject_path,
    _module_python_path,
    _module_required_imports,
    _module_run_dir,
    _module_start_strategy,
    _module_uses_poetry,
    _module_venv_pip,
    _module_venv_python,
    _normalize_akida_runtime_config,
    _normalize_akida_runtime_state,
    _normalized_import_list,
    _poetry_command,
    _poetry_env_python,
    _poetry_fallback_env_root,
    _uvicorn_host,
    _version_matches_range,
)
from .module_install import ModuleInstallMixin
from .module_lifecycle import ModuleLifecycleMixin
from .module_registry import ModuleRegistryMixin, _resolve_remote_module_version
from .preflight_types import PreflightResult  # noqa: F401
from .process_supervision import (  # noqa: F401
    ManagedProcess,
    ProcessSupervisionMixin,
    _dedupe_messages,
    _message_from_probe_outcome,
    _status_for_health_response,
)
from .pynq_service import PynqServiceMixin
from .runtime_shared import (  # noqa: F401
    _build_password_askpass_env,
    _module_root,
    _neurochip_module_root,
    _read_json_file,
    _runtime_request_error_kind,
    _write_json_file,
)
from .settings_service import SettingsServiceMixin
from .state_contracts import (  # noqa: F401
    AKIDA_HOST_AUTH_MODES,
    AKIDA_HOST_STATES,
    AKIDA_RUNTIME_MODES,
    BENIGN_SSH_WARNING_PREFIXES,
    DEFAULT_AKIDA_AUTH_MODE,
    DEFAULT_AKIDA_CONTROL_PORT,
    DEFAULT_AKIDA_CONTROL_SERVICE_NAME,
    DEFAULT_AKIDA_HOST_PORT,
    DEFAULT_AKIDA_HOST_SSH_PORT,
    DEFAULT_AKIDA_HOST_STATE,
    DEFAULT_AKIDA_REMOTE_INSTALL_ROOT,
    DEFAULT_AKIDA_REMOTE_VENV_PATH,
    DEFAULT_AKIDA_RUNTIME_SERVICE_NAME,
    DEFAULT_AKIDA_SERVICE_USER,
    DEFAULT_AKIDA_TOKEN_PATH,
    DEFAULT_CONTROL_LOG_LEVEL,
    DEFAULT_PYNQ_AGENT_HEALTH_TIMEOUT_SECONDS,
    DEFAULT_PYNQ_AUTH_MODE,
    DEFAULT_PYNQ_BOARD_PORT,
    DEFAULT_PYNQ_BOARD_SSH_PORT,
    DEFAULT_PYNQ_BOARD_STATE,
    DEFAULT_PYNQ_PREFLIGHT_TIMEOUT_SECONDS,
    DEFAULT_PYNQ_REMOTE_PYNQ_VENV_DIRNAME,
    DEFAULT_PYNQ_RUN_TIMEOUT_SECONDS,
    DEFAULT_STAGED_OVERLAY_DIRNAME,
    DEFAULT_STAGED_OVERLAY_MANIFEST,
    DEFAULT_STAGED_OVERLAY_TARGET,
    DEFAULT_STAGED_PYNQ_BITSTREAM_NAME,
    DEFAULT_STAGED_PYNQ_HWH_NAME,
    HEALTH_POLL_SECONDS,
    IMPORT_PROBE_SCRIPT,
    INSTALL_STATUS_SENTINEL,
    LEGACY_PYNQ_REMOTE_INSTALL_ROOT,
    LEGACY_PYNQ_REMOTE_OVERLAY_DIR,
    LEGACY_PYNQ_REMOTE_VENV_PATH,
    LOG_LINE_LIMIT,
    PREFLIGHT_DEGRADED,
    PREFLIGHT_FAILED,
    PREFLIGHT_OK,
    PREFLIGHT_SENTINEL,
    PYNQ_AGENT_HEALTH_HEARTBEAT_AFTER_SECONDS,
    PYNQ_AGENT_HEALTH_TIMEOUT_BOUNDS,
    PYNQ_BOARD_STATES,
    PYNQ_OVERLAY_UPLOAD_RECOVERY_MESSAGE,
    PYNQ_PREFLIGHT_RETRY_COUNT,
    PYNQ_PREFLIGHT_RETRY_DELAY_SECONDS,
    PYNQ_PREFLIGHT_TIMEOUT_BOUNDS,
    PYNQ_RUN_TIMEOUT_BOUNDS,
    PYNQ_RUNTIME_LOG_TAIL_LINES,
    STARTUP_GRACE_SECONDS,
    STATUS_INDEX,
    SUPPORTED_INSTALL_STRATEGIES,
    SUPPORTED_START_STRATEGIES,
    LauncherSettingsRecord,
)
from .state_protocols import DeploymentServiceProtocol
from .suite_api_service import (  # noqa: F401
    DEFAULT_SUITE_API_PORT,
    SUITE_API_STARTUP_TIMEOUT_SECONDS,
    SUITE_API_STATUS_DISABLED,
    SUITE_API_STATUS_PREFLIGHT_FAILED,
    SUITE_API_STATUS_READY,
    SUITE_API_STATUS_STARTING,
    SuiteApiServiceMixin,
    _suite_api_dev_install_paths,
    _suite_api_env_dir,
    _suite_api_env_fingerprint,
    _suite_api_env_python,
    _suite_api_env_stamp,
    _suite_api_pythonpath,
)
from .workspace_service import WorkspaceStateMixin


class LauncherControlState(
    HardwareDiscoveryMixin,
    AkidaRuntimeUpdateJobsMixin,
    AkidaServiceMixin,
    ModuleInstallMixin,
    ModuleLifecycleMixin,
    ModuleRegistryMixin,
    ProcessSupervisionMixin,
    PynqServiceMixin,
    SettingsServiceMixin,
    SuiteApiServiceMixin,
    WorkspaceStateMixin,
):
    """In-memory state and lifecycle orchestration for module control."""

    def __init__(
        self,
        remote_version_resolver: Callable[[dict[str, Any]], str | None] | None = None,
        *,
        manage_suite_api: bool = False,
        external_probe_host: str | None = None,
        diagnostic: bool = False,
    ) -> None:
        self._lock = threading.RLock()
        self._terminal_lock = threading.Lock()
        self._remote_version_resolver = (
            remote_version_resolver or _resolve_remote_module_version
        )
        self._manage_suite_api = manage_suite_api
        self._external_probe_host = external_probe_host or "127.0.0.1"
        self._diagnostic = diagnostic
        self._suite_api_status = (
            SUITE_API_STATUS_STARTING if manage_suite_api else SUITE_API_STATUS_DISABLED
        )
        self._suite_api_message: str | None = None
        self._suite_api_process: subprocess.Popen[str] | None = None
        self._suite_api_logs: collections.deque[str] = collections.deque(
            maxlen=LOG_LINE_LIMIT
        )
        # Akida runtime process managed separately from module processes so that
        # shutdown() can terminate it without going through stop_module().
        self._akida_runtime_process: subprocess.Popen[bytes] | None = None
        self._modules = self._load_modules()
        self._processes: dict[str, ManagedProcess] = {}
        self._logs: dict[str, collections.deque[str]] = collections.defaultdict(
            lambda: collections.deque(maxlen=LOG_LINE_LIMIT)
        )
        self._tasks: dict[str, threading.Thread] = {}
        self._settings: LauncherSettingsRecord = self._load_settings()
        self._init_akida_components()
        self._init_pynq_components()
        self._workspace_file = WORKSPACE_FILE
        self._workspace = self._load_workspace()
        self._deployment: DeploymentServiceProtocol = DeploymentService(
            store=DeploymentStore(
                DEPLOYMENT_STATE_FILE,
                FileBackedSecretStore(DEPLOYMENT_SECRET_FILE),
            ),
            repo_root=REPO_ROOT,
        )
        self._shutdown = threading.Event()
        self._hardware_discovery_done: bool = False
        self._hardware_discovery_lock = threading.Lock()
        self._health_thread: threading.Thread | None = None
        if not diagnostic:
            self._health_thread = threading.Thread(
                target=self._health_poll_loop,
                name="launcher-control-health",
                daemon=True,
            )
            self._health_thread.start()
            threading.Thread(
                target=self._auto_discover_local_hardware,
                name="launcher-hardware-discovery",
                daemon=True,
            ).start()
        if self._manage_suite_api and not diagnostic:
            threading.Thread(
                target=self._ensure_suite_api_ready,
                name="launcher-control-suite-api",
                daemon=True,
            ).start()

    def shutdown(self) -> None:
        self._shutdown.set()
        with self._lock:
            module_ids = list(self._processes.keys())
        for module_id in module_ids:
            self.stop_module(module_id)
        if (
            self._suite_api_process is not None
            and self._suite_api_process.poll() is None
        ):
            self._suite_api_process.terminate()
            try:
                self._suite_api_process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self._suite_api_process.kill()
                self._suite_api_process.wait(timeout=5)
        if (
            self._akida_runtime_process is not None
            and self._akida_runtime_process.poll() is None
        ):
            self._akida_runtime_process.terminate()
            try:
                self._akida_runtime_process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self._akida_runtime_process.kill()
                self._akida_runtime_process.wait(timeout=5)

    def get_settings(self) -> dict[str, Any]:
        with self._lock:
            artifact = None
            if str(os.getenv("NMTK_NEUROCHIP_ARTIFACT_DIR") or "").strip():
                try:
                    artifact = self._neurochip_runtime_artifact()
                except (FileNotFoundError, RuntimeError, ValueError):
                    artifact = None
            if artifact is not None:
                for host in self._settings["akidaHosts"]:
                    host["availableRuntimeVersion"] = artifact.version
            return {
                "logLevel": self._settings["logLevel"],
                "mujocoAvailable": self._settings["mujocoAvailable"],
                "pythonAvailable": self._settings["pythonAvailable"],
                "suiteApiStatus": self._suite_api_status,
                "suiteApiMessage": self._suite_api_message,
                "backendDeploymentReady": self._deployment.is_ready(),
                "selectedBackendDeploymentTarget": self._deployment.selected_target(),
                "pynqBoards": [
                    _serialize_pynq_board(board)
                    for board in self._settings["pynqBoards"]
                ],
                "akidaHosts": [
                    _serialize_akida_host(host) for host in self._settings["akidaHosts"]
                ],
                "selectedAkidaHostId": self._settings["selectedAkidaHostId"],
                "selectedPynqBoardId": self._settings["selectedPynqBoardId"],
            }

    def list_deployment_targets(self) -> list[dict[str, Any]]:
        return self._deployment.list_targets()

    def create_deployment_target(self, payload: dict[str, Any]) -> dict[str, Any]:
        return self._deployment.create_target(payload)

    def update_deployment_target(
        self, target_id: str, payload: dict[str, Any]
    ) -> dict[str, Any]:
        return self._deployment.update_target(target_id, payload)

    def delete_deployment_target(self, target_id: str) -> None:
        self._deployment.delete_target(target_id)

    def deployment_preflight(self, payload: dict[str, Any]) -> dict[str, Any]:
        return self._deployment.preflight(payload)

    def bootstrap_remote_deploy_user(self, payload: dict[str, Any]) -> dict[str, Any]:
        return self._deployment.bootstrap_remote_user(payload)

    def create_deployment_job(self, payload: dict[str, Any]) -> dict[str, Any]:
        return self._deployment.create_job(payload)

    def get_deployment_job(self, job_id: str) -> dict[str, Any]:
        return self._deployment.get_job(job_id)

    def cancel_deployment_job(self, job_id: str) -> dict[str, Any]:
        return self._deployment.cancel_job(job_id)

    def retry_deployment_job(self, job_id: str) -> dict[str, Any]:
        return self._deployment.retry_job(job_id)

    def deployment_job_events(self, job_id: str) -> list[str]:
        return self._deployment.job_events(job_id)


class LauncherControlServer(ThreadingHTTPServer):
    """HTTP server bound to a shared launcher state."""

    daemon_threads = True

    def __init__(
        self,
        server_address: tuple[str, int],
        manage_suite_api: bool = True,
        external_probe_host: str | None = None,
    ) -> None:
        self.state = LauncherControlState(
            manage_suite_api=manage_suite_api, external_probe_host=external_probe_host
        )
        super().__init__(server_address, LauncherControlHandler)

    def server_close(self) -> None:
        self.state.shutdown()
        super().server_close()


def create_server(
    host: str,
    port: int,
    manage_suite_api: bool = True,
    external_probe_host: str | None = None,
) -> LauncherControlServer:
    return LauncherControlServer(
        (host, port),
        manage_suite_api=manage_suite_api,
        external_probe_host=external_probe_host,
    )


def _build_cli_parser() -> argparse.ArgumentParser:
    """Build the launcher CLI with a loopback-safe default binding."""
    parser = argparse.ArgumentParser(description="Launcher control service")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8091)
    parser.add_argument(
        "--doctor",
        action="store_true",
        help="Run a non-mutating launcher environment diagnostic and exit",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Emit doctor output as JSON when used with --doctor",
    )
    parser.add_argument(
        "--manage-suite-api",
        action="store_true",
        default=True,
        help="Manage the suite_api lifecycle (default: True)",
    )
    parser.add_argument(
        "--no-manage-suite-api",
        action="store_false",
        dest="manage_suite_api",
        help="Do not manage the suite_api lifecycle",
    )
    parser.add_argument(
        "--external-probe-host",
        default=None,
        help="Hostname or IP to use when probing externally managed services (e.g. Jupyter on a remote host). Defaults to 127.0.0.1.",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _build_cli_parser().parse_args(argv)
    os.environ.setdefault("NMTK_UVICORN_HOST", str(args.host).strip() or "0.0.0.0")

    if args.doctor:
        state = LauncherControlState(diagnostic=True)
        try:
            report = state.doctor_report()
        finally:
            state.shutdown()
        if args.json:
            print(json.dumps(report, indent=2, sort_keys=True))
        else:
            print(_render_doctor_report(report))
        return 1 if report["fatalCount"] else 0

    server = create_server(
        args.host,
        args.port,
        manage_suite_api=args.manage_suite_api,
        external_probe_host=args.external_probe_host,
    )
    print(f"Launcher control service listening on http://{args.host}:{args.port}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
