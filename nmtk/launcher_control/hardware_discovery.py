"""Local hardware discovery independent of launcher server construction."""

from __future__ import annotations

import json
import logging
import os
import subprocess
import threading
import urllib.error
import urllib.request
from collections.abc import Callable
from contextlib import AbstractContextManager
from typing import Any

from .hardware_models import _load_neurochip_launcher_runtime_contract
from .module_environment import _module_run_dir, _module_venv_python
from .state_contracts import LauncherSettingsRecord

LOGGER = logging.getLogger(__name__)


class HardwareDiscoveryMixin:
    """Discover local runtimes using state supplied by the composed launcher."""

    _lock: AbstractContextManager[Any]
    _hardware_discovery_lock: AbstractContextManager[Any]
    _hardware_discovery_done: bool
    _settings: LauncherSettingsRecord
    _modules: dict[str, dict[str, Any]]
    _external_probe_host: str
    _shutdown: threading.Event
    _akida_runtime_process: subprocess.Popen[bytes] | None
    _persist_settings: Callable[[], None]
    create_akida_host: Callable[[dict[str, Any]], dict[str, Any]]

    # ------------------------------------------------------------------
    # Hardware auto-discovery
    # ------------------------------------------------------------------

    def _purge_auto_discovered_hosts(self) -> None:
        """Remove auto-discovered host entries so stale entries from a previous session
        never appear as failures before the current session's discovery has run."""
        with self._lock:
            before = self._settings.get("akidaHosts", [])
            after = [h for h in before if not h.get("autoDiscovered")]
            if len(after) != len(before):
                self._settings["akidaHosts"] = after
                self._persist_settings()

    def _auto_discover_local_hardware(self) -> None:
        """Probe local hardware runtime services and auto-register detected hosts.

        Probes each hardware type's runtime service directly on its well-known port
        (e.g. Akida on port 8002) without routing through the Neurochip FastAPI layer.
        Retries for up to ~30 s to allow services that start concurrently with the
        launcher to become ready.  Called from a daemon thread at startup and from
        POST /api/launcher/hardware/discover.
        """
        with self._hardware_discovery_lock:
            if self._hardware_discovery_done:
                return
            self._hardware_discovery_done = True

        try:
            self._auto_discover_local_hardware_impl()
        except Exception:  # noqa: BLE001
            LOGGER.exception(
                "hardware_discovery_failed external_probe_host=%s",
                self._external_probe_host,
            )

    def _auto_discover_local_hardware_impl(self) -> None:
        """Implementation body for _auto_discover_local_hardware."""
        # Purge stale auto-discovered entries from a previous session first so
        # they never show as "connection refused" before re-validation completes.
        self._purge_auto_discovered_hosts()

        contract = _load_neurochip_launcher_runtime_contract()
        probe_host = self._external_probe_host

        # --- Akida: probe the neurochip-akida-host runtime service on its own port ---
        akida_runtime_port = contract.akida.runtime_port  # 8002

        # Prefer the Docker-internal service URL when NEUROCHIP_HW_WORKER_URL is
        # configured. This may point at either the containerized stub worker
        # (no Akida SDK, always simulator-absent) or, on boxes with a real card,
        # the native neurochip.service via host.docker.internal (see
        # docker-compose.akida-native.yml) — either way it may legitimately be
        # hardware or the SDK's own AKD1000() simulator fallback, so both should
        # register (require_hardware=False below).
        # When the env var is absent we are in local-dev mode: construct the URL
        # from external_probe_host and try to auto-start the venv if present.
        _docker_worker_url = os.environ.get("NEUROCHIP_HW_WORKER_URL", "").strip()
        _worker_api_key = os.environ.get("NEUROCHIP_HW_WORKER_API_KEY", "").strip()
        if _docker_worker_url:
            akida_base_url = _docker_worker_url.rstrip("/")
            # Lava-backend has a 120 s start_period that gates neurochip-hw-worker;
            # allow up to 2 min of retries so Docker mode always survives a cold start.
            _probe_attempts = 24
        else:
            akida_base_url = f"http://{probe_host}:{akida_runtime_port}"
            _probe_attempts = 6  # 30 s — sufficient for local dev
            # Auto-start the local venv only when no Docker worker URL is configured.
            with self._lock:
                runtime_already_managed = self._akida_runtime_process is not None
            neurochip_module = self._modules.get("Neurochip")
            if neurochip_module is not None and not runtime_already_managed:
                self._start_local_akida_runtime(neurochip_module, akida_runtime_port)

        akida_status_url = f"{akida_base_url}/api/neurochip/akida/status"

        for _attempt in range(_probe_attempts):
            if self._shutdown.is_set():
                return
            try:
                _req = urllib.request.Request(
                    akida_status_url,
                    headers={"X-API-Key": _worker_api_key} if _worker_api_key else {},
                )
                with urllib.request.urlopen(_req, timeout=5) as resp:
                    body: dict[str, Any] = json.loads(
                        resp.read().decode("utf-8", errors="replace")
                    )
                    self._maybe_register_local_akida(
                        akida_base_url,
                        body,
                        require_hardware=not bool(_docker_worker_url),
                    )
                    break
            except urllib.error.HTTPError:
                # Service is up but returned an error — hardware likely unavailable.
                break
            except (urllib.error.URLError, OSError, TimeoutError):
                # Service not yet up — wait and retry.
                self._shutdown.wait(5.0)

    def _start_local_akida_runtime(
        self, neurochip_module: dict[str, Any], runtime_port: int
    ) -> None:
        """Spawn the Neurochip Akida runtime service locally on *runtime_port*.

        Called during hardware auto-discovery when Neurochip is installed and
        the runtime is not yet listening.  The process is stored in
        self._akida_runtime_process and terminated by shutdown().

        stdout/stderr are discarded to prevent pipe-buffer stalls; uvicorn
        writes its own structured logs internally.
        """
        python_path = _module_venv_python(neurochip_module)
        if not python_path.exists():
            LOGGER.info("akida_runtime_autostart_skipped reason=environment_missing")
            return
        run_dir = _module_run_dir(neurochip_module)
        log_level = str(self._settings.get("logLevel", "info"))
        command = [
            str(python_path),
            "-m",
            "uvicorn",
            "neurochip.app.main:app",
            "--host",
            "127.0.0.1",
            "--port",
            str(runtime_port),
            "--log-level",
            log_level,
        ]
        try:
            process = subprocess.Popen(
                command,
                cwd=str(run_dir),
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                stdin=subprocess.DEVNULL,
            )
            with self._lock:
                self._akida_runtime_process = process
            LOGGER.info(
                "akida_runtime_started port=%s pid=%s",
                runtime_port,
                process.pid,
            )
        except OSError:
            LOGGER.exception("akida_runtime_start_failed port=%s", runtime_port)

    def _maybe_register_local_akida(
        self,
        runtime_base_url: str,
        status: dict[str, Any],
        require_hardware: bool = True,
    ) -> None:
        """Auto-register a local Akida host entry.

        Uses the runtime service URL directly so that preflight checks hit the
        same service that was probed. The Akida host control service remains on
        its manifest-backed port, independently of launcher-control's host port.

        *require_hardware* — when True (local-dev default) only registers if
        the runtime reports physical hardware.  Set to False in Docker mode so
        that simulator containers are also registered as connectable hosts.
        """
        if require_hardware and status.get("runtimeTarget") != "hardware":
            return

        auto_id = "local-akida-auto"
        with self._lock:
            existing = self._settings.get("akidaHosts", [])
            if any(h["id"] == auto_id for h in existing):
                return
            is_first = len(existing) == 0

        device_info = str(status.get("deviceInfo") or "BrainChip Akida").strip()
        try:
            self.create_akida_host(
                {
                    "id": auto_id,
                    "displayName": f"Local Akida — {device_info}",
                    "runtimeApiUrl": runtime_base_url,
                    "controlApiUrl": "",
                    "autoDiscovered": True,
                    "isDefault": is_first,
                }
            )
            LOGGER.info(
                "hardware_discovery_registered kind=akida device=%s",
                device_info,
            )
        except ValueError as exc:
            LOGGER.debug(
                "hardware_discovery_registration_skipped kind=akida reason=%s",
                exc,
            )
