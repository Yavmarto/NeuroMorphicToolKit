"""Workspace persistence and session-normalization behavior."""

from __future__ import annotations

import json
import logging
from pathlib import Path
from typing import Any
from urllib.parse import urlparse, urlunparse

LOGGER = logging.getLogger(__name__)


def _read_workspace(path: Path) -> dict[str, Any]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}
    return payload if isinstance(payload, dict) else {}


def _write_workspace(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")


class WorkspaceStateMixin:
    def _load_workspace(self) -> dict[str, Any]:
        defaults: dict[str, Any] = {
            "sessions": [],
            "focusedModuleId": None,
        }
        stored = _read_workspace(self._workspace_file)
        if not isinstance(stored, dict):
            return defaults
        sessions = [
            self._normalize_workspace_session(session)
            for session in stored.get("sessions", [])
            if isinstance(session, dict)
        ]
        sessions = self._dedupe_workspace_sessions(sessions)
        focused_module_id = str(stored.get("focusedModuleId") or "").strip() or None
        if focused_module_id and not any(
            session["moduleId"] == focused_module_id for session in sessions
        ):
            focused_module_id = sessions[-1]["moduleId"] if sessions else None
        return {
            "sessions": sessions,
            "focusedModuleId": focused_module_id,
        }

    def _normalize_workspace_session(self, payload: dict[str, Any]) -> dict[str, Any]:
        module_id = self._canonicalize_workspace_module_id(
            str(payload.get("moduleId") or "").strip()
        )
        if not module_id:
            raise ValueError("Workspace session moduleId is required")
        if module_id not in self._modules:
            raise KeyError(f"Unknown module '{module_id}'")
        surface_mode = str(payload.get("surfaceMode") or "embedded").strip().lower()
        if surface_mode not in {"embedded", "native"}:
            surface_mode = "embedded"
        readiness_state = (
            str(payload.get("readinessState") or "opening").strip().lower()
        )
        if readiness_state not in {
            "opening",
            "warming_up",
            "ready",
            "degraded",
            "error",
            "restoring_session",
        }:
            readiness_state = "opening"
        deep_link = payload.get("deepLink")
        if deep_link is not None:
            deep_link = str(deep_link).strip() or None
        deep_link = self._canonicalize_workspace_deep_link(module_id, deep_link)
        restore_state = payload.get("restoreState")
        if not isinstance(restore_state, dict):
            restore_state = {}
        return {
            "moduleId": module_id,
            "surfaceMode": surface_mode,
            "deepLink": deep_link,
            "restoreState": restore_state,
            "readinessState": readiness_state,
        }

    def _canonicalize_workspace_module_id(self, module_id: str) -> str:
        if module_id == "Neurosim" and "neurocnl" in self._modules:
            return "neurocnl"
        return module_id

    def _canonicalize_workspace_deep_link(
        self, module_id: str, deep_link: str | None
    ) -> str | None:
        if module_id != "neurocnl":
            return deep_link
        if deep_link is None:
            return deep_link
        uri = urlparse(deep_link)
        if uri.path.startswith("/canvas"):
            return deep_link
        if uri.path in {"/", ""}:
            rewritten_path = "/canvas"
        elif (
            uri.path.startswith("/projects")
            or uri.path.startswith("/sweep")
            or uri.path.startswith("/export")
        ):
            rewritten_path = f"/canvas{uri.path}"
        else:
            return deep_link
        return urlunparse(uri._replace(path=rewritten_path))

    def _dedupe_workspace_sessions(
        self, sessions: list[dict[str, Any]]
    ) -> list[dict[str, Any]]:
        deduped: list[dict[str, Any]] = []
        seen: set[str] = set()
        for session in sessions:
            module_id = session["moduleId"]
            if module_id in seen:
                continue
            deduped.append(session)
            seen.add(module_id)
        return deduped

    def _persist_workspace(self) -> None:
        try:
            _write_workspace(self._workspace_file, self._workspace)
        except OSError:
            # Workspace state only controls launcher tabs and focus. Keep the
            # current in-memory session usable when a mounted state volume is
            # unavailable rather than turning a preference write into a client
            # error that blocks module startup or reload.
            LOGGER.warning(
                "Workspace preference state could not be persisted; "
                "continuing with the in-memory workspace.",
                exc_info=True,
            )

    def get_workspace(self) -> dict[str, Any]:
        with self._lock:
            return {
                "sessions": [dict(session) for session in self._workspace["sessions"]],
                "focusedModuleId": self._workspace["focusedModuleId"],
            }

    def update_workspace(self, payload: dict[str, Any]) -> dict[str, Any]:
        with self._lock:
            sessions = self._workspace["sessions"]
            if "sessions" in payload:
                raw_sessions = payload.get("sessions")
                if not isinstance(raw_sessions, list):
                    raise ValueError("Workspace sessions payload must be a list")
                sessions = self._dedupe_workspace_sessions(
                    [
                        self._normalize_workspace_session(session)
                        for session in raw_sessions
                        if isinstance(session, dict)
                    ]
                )
                self._workspace["sessions"] = sessions
            if "focusedModuleId" in payload:
                focused_module_id = (
                    str(payload.get("focusedModuleId") or "").strip() or None
                )
                if focused_module_id and not any(
                    session["moduleId"] == focused_module_id for session in sessions
                ):
                    raise KeyError(f"Unknown workspace session '{focused_module_id}'")
                self._workspace["focusedModuleId"] = focused_module_id
            elif self._workspace["focusedModuleId"] is not None and not any(
                session["moduleId"] == self._workspace["focusedModuleId"]
                for session in sessions
            ):
                self._workspace["focusedModuleId"] = (
                    sessions[-1]["moduleId"] if sessions else None
                )
            self._persist_workspace()
            return self.get_workspace()

    def create_workspace_session(self, payload: dict[str, Any]) -> dict[str, Any]:
        with self._lock:
            session = self._normalize_workspace_session(payload)
            sessions = [
                existing
                for existing in self._workspace["sessions"]
                if existing["moduleId"] != session["moduleId"]
            ]
            sessions.append(session)
            self._workspace["sessions"] = sessions
            self._workspace["focusedModuleId"] = session["moduleId"]
            self._persist_workspace()
            return self.get_workspace()

    def delete_workspace_session(self, module_id: str) -> dict[str, Any]:
        with self._lock:
            sessions = [
                session
                for session in self._workspace["sessions"]
                if session["moduleId"] != module_id
            ]
            if len(sessions) == len(self._workspace["sessions"]):
                raise KeyError(f"Unknown workspace session '{module_id}'")
            self._workspace["sessions"] = sessions
            if self._workspace["focusedModuleId"] == module_id:
                self._workspace["focusedModuleId"] = (
                    sessions[-1]["moduleId"] if sessions else None
                )
            self._persist_workspace()
            return self.get_workspace()
