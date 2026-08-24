"""Module install/update/repair/start/stop orchestration, health polling, and
the doctor report.

Imported by ``server.py`` right before ``LauncherControlState`` is defined, so
the ``from .server import ...`` below resolves against the partially
initialized module rather than re-entering it — the names it pulls in must
already be bound in ``server.py`` above that import line.
"""

from __future__ import annotations

import subprocess
import time
from typing import Any
from urllib.parse import urlparse

from .config import STATE_FILE, MODULES_MANIFEST
from .preflight_types import PreflightResult
from .process_supervision import ManagedProcess, _status_for_health_response
from .runtime_shared import _module_root, _read_json_file, _write_json_file
from .module_environment import (
    _effective_port,
    _is_externally_managed_service,
    _missing_python_message,
    _module_environment_exists,
    _module_install_extras,
    _module_install_strategy,
    _module_optional_imports,
    _module_python_path,
    _module_required_imports,
    _module_run_dir,
    _module_start_strategy,
    _normalize_akida_runtime_config,
    _normalize_akida_runtime_state,
    _normalized_import_list,
    _uvicorn_host,
)
from .suite_api_service import (
    SUITE_API_STATUS_PREFLIGHT_FAILED,
    SUITE_API_STATUS_READY,
    _suite_api_health_probe,
)
from .doctor_service import _global_preflight_checks
from .module_registry import _coerce_remote_update_version, _is_newer_version
from .server import (
    HEALTH_POLL_SECONDS,
    PREFLIGHT_DEGRADED,
    PREFLIGHT_FAILED,
    PREFLIGHT_OK,
    STARTUP_GRACE_SECONDS,
    STATUS_INDEX,
    SUPPORTED_START_STRATEGIES,
    _load_neurochip_launcher_runtime_contract,
    _normalize_akida_host_state,
    _normalize_akida_runtime_mode,
    _normalize_pynq_board_state,
    _resolved_akida_base_url,
    _resolved_akida_control_api_url,
    _resolved_pynq_runtime_api_url,
    _status_name,
)


class ModuleLifecycleMixin:
    def _load_modules(self) -> dict[str, dict[str, Any]]:
        manifest = _read_json_file(MODULES_MANIFEST, [])
        saved_states = _read_json_file(STATE_FILE, {})
        module_map: dict[str, dict[str, Any]] = {}
        for raw in manifest:
            if not isinstance(raw, dict) or "id" not in raw:
                continue
            module_id = str(raw["id"])
            saved = saved_states.get(module_id, {})
            module = dict(raw)
            module["directory"] = str(_module_root(module))
            module["version"] = str(
                saved.get("version", module.get("version", "0.0.0"))
            )
            module["versionPinned"] = bool(saved.get("versionPinned", False))
            saved_remote_version = str(
                saved.get(
                    "remoteVersion", module.get("remoteVersion", module["version"])
                )
            )
            module["remoteVersion"] = (
                module["version"]
                if module["versionPinned"]
                else _coerce_remote_update_version(
                    module["version"],
                    saved_remote_version,
                )
            )
            module["isEnabled"] = bool(saved.get("isEnabled", True))
            module["customPort"] = saved.get("customPort")
            module["startOnLaunch"] = bool(saved.get("startOnLaunch", False))
            status_index = saved.get("status", STATUS_INDEX["notInstalled"])
            if status_index in (
                STATUS_INDEX["running"],
                STATUS_INDEX["starting"],
                STATUS_INDEX["stopping"],
                STATUS_INDEX["degraded"],
                STATUS_INDEX["error"],
                STATUS_INDEX["updating"],
            ):
                status_index = STATUS_INDEX["installed"]
            if (
                status_index != STATUS_INDEX["notInstalled"]
                and not _module_environment_exists(module)
                and not saved.get("environmentFingerprint")
            ):
                status_index = STATUS_INDEX["notInstalled"]
                module["installProgress"] = 0.0
            module["status"] = status_index
            module["installProgress"] = float(
                module.get("installProgress", saved.get("installProgress", 0.0))
            )
            module["healthStatus"] = saved.get("healthStatus")
            module["requiredImports"] = _module_required_imports(module)
            module["optionalImports"] = _module_optional_imports(module)
            module["installExtras"] = _module_install_extras(module)
            module["installStrategy"] = _module_install_strategy(module)
            module["startStrategy"] = _module_start_strategy(module)
            module["akidaRuntime"] = _normalize_akida_runtime_config(
                module.get("akidaRuntime")
            )
            module["akidaRuntimeState"] = _normalize_akida_runtime_state(
                saved.get("akidaRuntimeState")
            )
            module["preflightStatus"] = str(saved.get("preflightStatus", PREFLIGHT_OK))
            module["preflightMessage"] = saved.get("preflightMessage")
            module["capabilityWarnings"] = _normalized_import_list(
                saved.get("capabilityWarnings", module.get("capabilityWarnings", []))
            )
            module["environmentFingerprint"] = saved.get("environmentFingerprint")
            module_map[module_id] = module
        return module_map

    def update_module_settings(
        self, module_id: str, payload: dict[str, Any]
    ) -> dict[str, Any]:
        with self._lock:
            module = self._get_module(module_id)
            if "isEnabled" in payload:
                module["isEnabled"] = bool(payload["isEnabled"])
            if "customPort" in payload:
                custom_port = payload["customPort"]
                module["customPort"] = (
                    custom_port if isinstance(custom_port, int) else None
                )
            if "versionPinned" in payload:
                module["versionPinned"] = bool(payload["versionPinned"])
                if module["versionPinned"]:
                    module["remoteVersion"] = str(module.get("version", "0.0.0"))
            if "startOnLaunch" in payload:
                module["startOnLaunch"] = bool(payload["startOnLaunch"])
            self._persist_states()
            return self._serialize_module(module)

    def install_module(self, module_id: str) -> dict[str, Any]:
        with self._lock:
            module = self._get_module(module_id)
            if self._task_running(module_id):
                return self._serialize_module(module)
            module["status"] = STATUS_INDEX["installing"]
            module["installProgress"] = 0.0
            module["healthStatus"] = None
            module["preflightStatus"] = PREFLIGHT_OK
            module["preflightMessage"] = None
            module["capabilityWarnings"] = []
            self._persist_states()
            self._spawn_task(module_id, lambda: self._install_sync(module_id))
            return self._serialize_module(module)

    def update_module(self, module_id: str) -> dict[str, Any]:
        with self._lock:
            module = self._get_module(module_id)
            if self._task_running(module_id):
                return self._serialize_module(module)
            current_version = str(module.get("version", "0.0.0"))
            remote_version = str(module.get("remoteVersion", current_version))
            if bool(module.get("versionPinned", False)) or not _is_newer_version(
                current_version,
                remote_version,
            ):
                return self._serialize_module(module)
            module["status"] = STATUS_INDEX["updating"]
            module["installProgress"] = 0.0
            module["healthStatus"] = None
            module["preflightStatus"] = PREFLIGHT_OK
            module["preflightMessage"] = None
            module["capabilityWarnings"] = []
            self._persist_states()
            self._spawn_task(module_id, lambda: self._update_sync(module_id))
            return self._serialize_module(module)

    def repair_module(self, module_id: str) -> dict[str, Any]:
        """Repair a module by running preflight with allow_repair=True.

        Sets the module to 'installing' state immediately and spawns a background
        thread.  On completion the module lands in 'installed' (ok), 'degraded',
        or 'error' state — but is never started.
        """
        with self._lock:
            module = self._get_module(module_id)
            if self._task_running(module_id):
                return self._serialize_module(module)
            module["status"] = STATUS_INDEX["installing"]
            module["installProgress"] = 0.0
            module["healthStatus"] = None
            module["preflightStatus"] = PREFLIGHT_OK
            module["preflightMessage"] = None
            module["capabilityWarnings"] = []
            self._persist_states()
            self._spawn_task(module_id, lambda: self._repair_sync(module_id))
            return self._serialize_module(module)

    def start_module(self, module_id: str) -> dict[str, Any]:
        with self._lock:
            module = self._get_module(module_id)
            if self._task_running(module_id):
                return self._serialize_module(module)
            module["status"] = STATUS_INDEX["starting"]
            module["healthStatus"] = None
            module["preflightStatus"] = PREFLIGHT_OK
            module["preflightMessage"] = None
            module["capabilityWarnings"] = []
            self._persist_states()
            self._spawn_task(module_id, lambda: self._start_sync(module_id))
            return self._serialize_module(module)

    def stop_module(self, module_id: str) -> dict[str, Any]:
        with self._lock:
            module = self._get_module(module_id)
            module["status"] = STATUS_INDEX["stopping"]
            self._persist_states()
        try:
            self._stop_process(module_id)
            self._update_module_fields(
                module_id,
                status=STATUS_INDEX["installed"],
                healthStatus=None,
                installProgress=1.0,
            )
        except Exception as exc:  # noqa: BLE001
            self._set_error(module_id, f"Stop failed: {exc}")
        return self.serialize_module(module_id)

    def uninstall_module(self, module_id: str) -> dict[str, Any]:
        self.stop_module(module_id)
        self._cleanup_module_environment(module_id)
        self._update_module_fields(
            module_id,
            status=STATUS_INDEX["notInstalled"],
            installProgress=0.0,
            healthStatus=None,
            preflightStatus=PREFLIGHT_OK,
            preflightMessage=None,
            capabilityWarnings=[],
            environmentFingerprint=None,
        )
        return self.serialize_module(module_id)

    def get_logs(self, module_id: str) -> dict[str, Any]:
        with self._lock:
            managed = self._processes.get(module_id)
            lines = managed.logs if managed is not None else self._logs[module_id]
            return {"moduleId": module_id, "lines": list(lines)}

    def get_all_logs(self, *, filter_error: bool = False) -> dict[str, Any]:
        with self._lock:
            lines: list[str] = []
            # Suite API logs first
            for line in self._suite_api_logs:
                if not filter_error or line.startswith("[stderr] "):
                    lines.append(f"[suite_api] {line}")
            # Module logs alphabetically by module ID
            for module_id in sorted(self._logs.keys()):
                for line in self._logs[module_id]:
                    if not filter_error or line.startswith("[stderr] "):
                        lines.append(f"[{module_id}] {line}")
            return {"lines": lines}

    def _start_sync(self, module_id: str) -> None:
        module = self._get_module(module_id)
        if not module.get("isEnabled", True):
            raise RuntimeError("Module is disabled")

        start_strategy = _module_start_strategy(module)
        if start_strategy == "none":
            if _is_externally_managed_service(module):
                # Standalone external service (e.g. Jupyter, lava_backend running in
                # Docker).  Probe its actual health endpoint instead of assuming it is
                # managed by suite_api.
                ok, status_code, health_text = self._probe_health(module)
                if ok:
                    next_status = _status_for_health_response(status_code, PREFLIGHT_OK)
                    self._update_module_fields(
                        module_id,
                        status=next_status,
                        healthStatus=health_text,
                    )
                else:
                    deployment = module.get("deployment") or {}
                    compose_profile = (
                        deployment.get("composeProfile", "")
                        if isinstance(deployment, dict)
                        else ""
                    )
                    hint = (
                        f" Start it with: docker compose --profile {compose_profile} up"
                        if compose_profile
                        else " Start the external service before launching this module."
                    )
                    msg = (
                        f"Waiting for service on port {_effective_port(module)}.{hint}"
                    )
                    self._update_module_fields(module_id, healthStatus=msg)
                    # Status remains 'starting'; health poll will transition to running when available.
                    return
                return

            suite_api_result = self._suite_api_ready_result()
            self._update_module_fields(module_id, **suite_api_result.state_fields())
            if suite_api_result.status == PREFLIGHT_FAILED:
                self._update_module_fields(
                    module_id,
                    status=STATUS_INDEX["error"],
                    healthStatus=suite_api_result.message,
                )
                raise RuntimeError(
                    suite_api_result.message or "suite_api is unavailable"
                )
            self._update_module_fields(
                module_id,
                status=STATUS_INDEX["running"],
                healthStatus="Managed by suite_api",
            )
            return

        preflight = self._preflight_module(module, allow_repair=True)
        self._update_module_fields(module_id, **preflight.state_fields())
        if preflight.status == PREFLIGHT_FAILED:
            self._update_module_fields(
                module_id,
                status=STATUS_INDEX["error"],
                healthStatus=preflight.message,
            )
            raise RuntimeError(preflight.message or "Module preflight failed")

        module = self._get_module(module_id)
        if start_strategy not in SUPPORTED_START_STRATEGIES:
            raise RuntimeError(
                f"Unsupported start strategy '{start_strategy}' for {module_id}"
            )

        port = _effective_port(module)
        if port is None:
            raise RuntimeError("Module has no configured port")

        self._kill_process_on_port(port, module_id=module_id)
        run_dir = _module_run_dir(module)
        python_path = _module_python_path(module)
        if not python_path.exists():
            raise RuntimeError(_missing_python_message(module, python_path))

        command = [
            str(python_path),
            "-m",
            "uvicorn",
            str(module.get("uvicornTarget", "app.main:app")),
            "--host",
            _uvicorn_host(),
            "--port",
            str(port),
            "--log-level",
            str(self._settings["logLevel"]),
        ]
        process = subprocess.Popen(
            command,
            cwd=run_dir,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            stdin=subprocess.DEVNULL,
            text=True,
            bufsize=1,
        )
        managed = ManagedProcess(process=process, logs=self._logs[module_id])
        with self._lock:
            self._processes[module_id] = managed
            self._persist_states()
        self._stream_logs(module_id, managed)
        self._watch_process_exit(module_id, managed)

        deadline = time.monotonic() + STARTUP_GRACE_SECONDS
        while time.monotonic() < deadline:
            ok, status_code, health_text = self._probe_health(module)
            if ok:
                next_status = _status_for_health_response(status_code, preflight.status)
                self._update_module_fields(
                    module_id,
                    status=next_status,
                    installProgress=1.0,
                    healthStatus=health_text,
                )
                return
            if process.poll() is not None:
                raise RuntimeError(f"Process exited with code {process.returncode}")
            time.sleep(0.5)

        self._update_module_fields(
            module_id,
            status=STATUS_INDEX["error"],
            healthStatus="Timed out waiting for /health",
        )

    def _health_poll_loop(self) -> None:
        while not self._shutdown.wait(HEALTH_POLL_SECONDS):
            if self._manage_suite_api:
                ok, message = _suite_api_health_probe()
                if ok:
                    self._set_suite_api_state(
                        SUITE_API_STATUS_READY, "Managed by suite_api"
                    )
                elif self._suite_api_status == SUITE_API_STATUS_READY:
                    self._set_suite_api_state(
                        SUITE_API_STATUS_PREFLIGHT_FAILED,
                        message or "suite_api health probe failed",
                    )
            # Monolithic modules have no dedicated process for the launcher
            # to supervise.  Reconcile their transitional state explicitly so
            # a restart or failed in-container connection cannot strand a
            # workspace on an infinite "starting" screen.
            with self._lock:
                monolith_starting_ids = [
                    module_id
                    for module_id, module in self._modules.items()
                    if module.get("status") == STATUS_INDEX["starting"]
                    and _module_start_strategy(module) == "none"
                    and not _is_externally_managed_service(module)
                ]
            if monolith_starting_ids:
                suite_ready, _message = _suite_api_health_probe()
                for module_id in monolith_starting_ids:
                    if suite_ready:
                        self._update_module_fields(
                            module_id,
                            status=STATUS_INDEX["running"],
                            healthStatus="Managed by suite_api",
                        )
                    else:
                        self._update_module_fields(
                            module_id,
                            status=STATUS_INDEX["error"],
                            healthStatus=(
                                "Suite API is not reachable from launcher "
                                "control. Retry after the backend starts."
                            ),
                        )
            with self._lock:
                module_ids = list(self._processes.keys())
            for module_id in module_ids:
                with self._lock:
                    module = dict(self._get_module(module_id))
                ok, status_code, health_text = self._probe_health(module)
                if ok:
                    next_status = _status_for_health_response(
                        status_code,
                        str(module.get("preflightStatus", PREFLIGHT_OK)),
                    )
                    self._update_module_fields(
                        module_id,
                        status=next_status,
                        healthStatus=health_text
                        if health_text
                        else (
                            "No /health endpoint (server is up)"
                            if status_code == 404
                            else None
                        ),
                    )
                elif module_id in self._processes:
                    self._update_module_fields(
                        module_id,
                        status=STATUS_INDEX["error"],
                        healthStatus="Health probe failed",
                    )

            # Also poll externally managed services (those not in _processes).
            # These are started outside the launcher (e.g. via Docker) and need
            # their own health tracking so the UI can recover when the service
            # comes back up or detect when it goes away.
            with self._lock:
                external_snapshots = [
                    (mid, dict(m))
                    for mid, m in self._modules.items()
                    if _is_externally_managed_service(m)
                    and mid not in self._processes
                    and int(m.get("status", STATUS_INDEX["notInstalled"]))
                    in (
                        STATUS_INDEX["running"],
                        STATUS_INDEX["degraded"],
                        STATUS_INDEX["error"],
                        STATUS_INDEX["starting"],
                    )
                ]
            for module_id, module in external_snapshots:
                ok, status_code, health_text = self._probe_health(module)
                if ok:
                    next_status = _status_for_health_response(
                        status_code, str(module.get("preflightStatus", PREFLIGHT_OK))
                    )
                    self._update_module_fields(
                        module_id,
                        status=next_status,
                        healthStatus=health_text
                        if health_text
                        else (
                            "No /health endpoint (server is up)"
                            if status_code == 404
                            else None
                        ),
                    )
                else:
                    self._update_module_fields(
                        module_id,
                        status=STATUS_INDEX["error"],
                        healthStatus="External service is not reachable",
                    )

    def doctor_report(self) -> dict[str, Any]:
        modules: list[dict[str, Any]] = []
        akida_hosts: list[dict[str, Any]] = []
        pynq_boards: list[dict[str, Any]] = []
        global_checks = _global_preflight_checks()
        fatal_count = 0
        degraded_count = 0
        ok_count = 0

        for check in global_checks:
            status = str(check.get("preflightStatus", PREFLIGHT_OK))
            if status == PREFLIGHT_FAILED:
                fatal_count += 1
            elif status == PREFLIGHT_DEGRADED:
                degraded_count += 1
            else:
                ok_count += 1

        with self._lock:
            snapshot = [dict(module) for module in self._modules.values()]

        for module in snapshot:
            if not module.get("isEnabled", True):
                result = PreflightResult(
                    status=PREFLIGHT_OK,
                    message="Module disabled",
                )
            elif (
                int(module.get("status", STATUS_INDEX["notInstalled"]))
                == STATUS_INDEX["notInstalled"]
            ):
                result = PreflightResult(
                    status=PREFLIGHT_OK,
                    message="Module not installed",
                )
            elif _is_externally_managed_service(module):
                # Probe the external service's own health endpoint.
                ok, status_code, health_text = self._probe_health(module)
                if ok:
                    result = PreflightResult(
                        status=PREFLIGHT_OK,
                        message=health_text or "External service is reachable",
                    )
                else:
                    deployment = module.get("deployment") or {}
                    compose_profile = (
                        deployment.get("composeProfile", "")
                        if isinstance(deployment, dict)
                        else ""
                    )
                    hint = (
                        f"Start it with: docker compose --profile {compose_profile} up"
                        if compose_profile
                        else "Start the external service before launching this module."
                    )
                    result = PreflightResult(
                        status=PREFLIGHT_DEGRADED,
                        message=f"External service not reachable on port {_effective_port(module)}. {hint}",
                        capability_warnings=[
                            f"{module.get('name', module['id'])} is not running."
                        ],
                    )
            elif _module_start_strategy(module) == "none":
                result = (
                    self._suite_api_static_readiness_result()
                    if self._diagnostic
                    else self._suite_api_ready_result()
                )
            else:
                result = self._preflight_module(module, allow_repair=False)

            if result.status == PREFLIGHT_FAILED:
                fatal_count += 1
            elif result.status == PREFLIGHT_DEGRADED:
                degraded_count += 1
            else:
                ok_count += 1

            modules.append(
                {
                    "id": module["id"],
                    "name": module["name"],
                    "status": _status_name(int(module.get("status", 0))),
                    "preflightStatus": result.status,
                    "preflightMessage": result.message,
                    "capabilityWarnings": list(result.capability_warnings),
                    "environmentFingerprint": result.environment_fingerprint,
                    "effectivePort": _effective_port(module),
                }
            )

        with self._lock:
            akida_host_snapshot = [
                dict(host) for host in self._settings.get("akidaHosts", [])
            ]
            board_snapshot = [
                dict(board) for board in self._settings.get("pynqBoards", [])
            ]

        for host in akida_host_snapshot:
            state = _normalize_akida_host_state(
                host.get("state"),
                _load_neurochip_launcher_runtime_contract().akida.default_state,
            )
            if state == "ready":
                ok_count += 1
            elif state in {
                "degraded_optional_capability",
                "degraded",
                "simulator_only",
                "reachable",
                "bootstrapping",
                "installing_runtime",
                "verifying_sdk",
                "unpaired",
            }:
                degraded_count += 1
            elif state in {"preflight_failed", "blocked", "error", "provision_failed"}:
                fatal_count += 1

            akida_hosts.append(
                {
                    "id": host["id"],
                    "displayName": host["displayName"],
                    "host": str(
                        host.get("host")
                        or urlparse(_resolved_akida_base_url(host)).hostname
                        or ""
                    ),
                    "baseUrl": _resolved_akida_base_url(host),
                    "controlApiUrl": _resolved_akida_control_api_url(host),
                    "runtimeApiUrl": str(
                        host.get("runtimeApiUrl") or _resolved_akida_base_url(host)
                    ).strip(),
                    "sshPort": int(
                        host.get("sshPort")
                        or _load_neurochip_launcher_runtime_contract().akida.ssh_port
                    ),
                    "username": str(host.get("username") or "").strip(),
                    "runtimeMode": _normalize_akida_runtime_mode(
                        host.get("runtimeMode")
                    ),
                    "state": state,
                    "hostOs": str(host.get("hostOs") or "").strip(),
                    "pythonVersion": str(host.get("pythonVersion") or "").strip(),
                    "lastPreflightStatus": host.get("lastPreflightStatus"),
                    "lastPreflightMessage": host.get("lastPreflightMessage"),
                    "lastSdkStatus": host.get("lastSdkStatus"),
                    "lastRuntimeTarget": host.get("lastRuntimeTarget"),
                    "lastReadinessMessage": str(
                        host.get("lastReadinessMessage") or ""
                    ).strip(),
                }
            )

        for board in board_snapshot:
            state = _normalize_pynq_board_state(
                board.get("state"),
                _load_neurochip_launcher_runtime_contract().pynq.default_state,
            )
            if state == "ready":
                ok_count += 1
            elif state == "degraded_optional_capability":
                degraded_count += 1
            elif state in {
                "provision_failed",
                "overlay_missing",
                "preflight_failed",
                "error",
            }:
                fatal_count += 1

            pynq_boards.append(
                {
                    "id": board["id"],
                    "displayName": board["displayName"],
                    "host": board["host"],
                    "state": state,
                    "lastPreflightStatus": board.get("lastPreflightStatus"),
                    "lastPreflightMessage": board.get("lastPreflightMessage"),
                    "runtimeApiUrl": _resolved_pynq_runtime_api_url(board),
                    "runtimeApiUrlOverride": str(
                        board.get("runtimeApiUrlOverride") or ""
                    ).strip(),
                }
            )

        return {
            "status": "ok" if fatal_count == 0 else "error",
            "fatalCount": fatal_count,
            "degradedCount": degraded_count,
            "okCount": ok_count,
            "globalChecks": global_checks,
            "modules": modules,
            "backendDeployment": {
                "ready": self._deployment.is_ready(),
                "selectedTarget": self._deployment.selected_target(),
                "targetCount": len(self._deployment.list_targets()),
            },
            "akidaHosts": akida_hosts,
            "pynqBoards": pynq_boards,
        }

    def _set_error(self, module_id: str, message: str) -> None:
        self._update_module_fields(
            module_id,
            status=STATUS_INDEX["error"],
            healthStatus=message,
        )

    def _get_module(self, module_id: str) -> dict[str, Any]:
        try:
            return self._modules[module_id]
        except KeyError as exc:
            raise KeyError(f"Unknown module '{module_id}'") from exc

    def _update_module_fields(self, module_id: str, **fields: Any) -> None:
        with self._lock:
            module = self._get_module(module_id)
            for key, value in fields.items():
                module[key] = value
            self._persist_states()

    def _persist_states(self) -> None:
        payload = {
            module_id: {
                "id": module["id"],
                "version": module.get("version", "0.0.0"),
                "remoteVersion": module.get("remoteVersion", "0.0.0"),
                "versionPinned": bool(module.get("versionPinned", False)),
                "isEnabled": bool(module.get("isEnabled", True)),
                "customPort": module.get("customPort"),
                "startOnLaunch": bool(module.get("startOnLaunch", False)),
                "status": module.get("status", STATUS_INDEX["notInstalled"]),
                "installProgress": float(module.get("installProgress", 0.0)),
                "healthStatus": module.get("healthStatus"),
                "preflightStatus": module.get("preflightStatus", PREFLIGHT_OK),
                "preflightMessage": module.get("preflightMessage"),
                "capabilityWarnings": list(module.get("capabilityWarnings", [])),
                "environmentFingerprint": module.get("environmentFingerprint"),
                "directory": module["directory"],
                "port": module.get("port"),
                "hasFrontend": bool(module.get("hasFrontend", False)),
                "showInLauncherNav": bool(module.get("showInLauncherNav", True)),
                "frontendStatus": module.get("frontendStatus", "No"),
                "requiresMuJoCo": bool(module.get("requiresMuJoCo", False)),
                "sourcePath": module.get("sourcePath", "."),
                "runPath": module.get("runPath", "."),
                "uvicornTarget": module.get("uvicornTarget", "app.main:app"),
                "requiredImports": list(module.get("requiredImports", [])),
                "optionalImports": list(module.get("optionalImports", [])),
                "installExtras": list(module.get("installExtras", [])),
                "installStrategy": module.get("installStrategy", "pip"),
                "startStrategy": module.get("startStrategy", "uvicorn"),
                "akidaRuntimeState": _normalize_akida_runtime_state(
                    module.get("akidaRuntimeState")
                ),
            }
            for module_id, module in self._modules.items()
        }
        _write_json_file(STATE_FILE, payload)
