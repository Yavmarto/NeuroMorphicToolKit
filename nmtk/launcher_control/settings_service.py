"""Persisted launcher settings: log level, selected Akida host, hardware lists.

Imported by ``server.py`` right before ``LauncherControlState`` is defined, so
the ``from .server import ...`` below resolves against the partially
initialized module rather than re-entering it — the names it pulls in must
already be bound in ``server.py`` above that import line. ``get_settings``
(which composes this state with live suite_api/deployment status) stays on
``LauncherControlState`` itself since it reaches across multiple mixins.
"""

from __future__ import annotations

from typing import Any

from .config import SETTINGS_FILE
from .runtime_shared import _read_json_file, _write_json_file
from .server import DEFAULT_CONTROL_LOG_LEVEL, _mujoco_available, _normalize_akida_host, _normalize_pynq_board


class SettingsServiceMixin:
    def _load_settings(self) -> dict[str, Any]:
        defaults = {
            "logLevel": DEFAULT_CONTROL_LOG_LEVEL,
            "mujocoAvailable": _mujoco_available(),
            "pythonAvailable": True,
            "akidaHosts": [],
            "pynqBoards": [],
            "selectedAkidaHostId": None,
        }
        stored = _read_json_file(SETTINGS_FILE, {})
        if not isinstance(stored, dict):
            return defaults
        akida_hosts = [
            _normalize_akida_host(host)
            for host in stored.get("akidaHosts", [])
            if isinstance(host, dict)
        ]
        selected_akida_host_id = str(stored.get("selectedAkidaHostId") or "").strip()
        if akida_hosts and not any(
            host["id"] == selected_akida_host_id for host in akida_hosts
        ):
            selected_akida_host_id = akida_hosts[0]["id"]
        if not akida_hosts:
            selected_akida_host_id = ""
        defaults.update(
            {
                "logLevel": stored.get("logLevel", DEFAULT_CONTROL_LOG_LEVEL),
                "mujocoAvailable": _mujoco_available(),
                "pythonAvailable": True,
                "akidaHosts": [
                    _normalize_akida_host(host)
                    for host in stored.get("akidaHosts", [])
                    if isinstance(host, dict)
                ],
                "pynqBoards": [
                    _normalize_pynq_board(board)
                    for board in stored.get("pynqBoards", [])
                    if isinstance(board, dict)
                ],
                "selectedAkidaHostId": selected_akida_host_id or None,
            }
        )
        return defaults

    def update_settings(self, payload: dict[str, Any]) -> dict[str, Any]:
        with self._lock:
            log_level = payload.get("logLevel")
            if isinstance(log_level, str) and log_level:
                self._settings["logLevel"] = log_level.lower()
            if "selectedAkidaHostId" in payload:
                selected_akida_host_id = str(
                    payload.get("selectedAkidaHostId") or ""
                ).strip()
                if not selected_akida_host_id:
                    self._settings["selectedAkidaHostId"] = None
                elif any(
                    host["id"] == selected_akida_host_id
                    for host in self._settings.get("akidaHosts", [])
                ):
                    self._settings["selectedAkidaHostId"] = selected_akida_host_id
                else:
                    raise KeyError(f"Unknown Akida host '{selected_akida_host_id}'")
            self._persist_settings()
            return self.get_settings()

    def _persist_settings(self) -> None:
        _write_json_file(SETTINGS_FILE, self._settings)
