"""Settings-backed persistence boundary for paired Akida hosts."""

from __future__ import annotations

from collections.abc import Callable, Mapping, MutableMapping
from contextlib import AbstractContextManager
from typing import Any, cast

from .hardware_models import (
    _normalize_akida_host,
    _resolved_akida_base_url,
    _serialize_akida_host,
)
from .state_contracts import AkidaHostRecord, LauncherSettingsRecord


class AkidaHostRepository:
    """Own paired-host CRUD without changing the launcher settings layout."""

    def __init__(
        self,
        *,
        settings: LauncherSettingsRecord,
        lock: AbstractContextManager[Any],
        persist: Callable[[], None],
    ) -> None:
        self._settings = settings
        self._lock = lock
        self._persist = persist

    def list(self) -> list[dict[str, Any]]:
        """Return serialized host records with secrets removed."""
        with self._lock:
            return [
                _serialize_akida_host(host) for host in self._settings["akidaHosts"]
            ]

    def get_serialized(self, host_id: str) -> dict[str, Any]:
        """Return one serialized host record."""
        with self._lock:
            return _serialize_akida_host(self.get(host_id))

    def create(self, payload: dict[str, Any]) -> dict[str, Any]:
        """Normalize, persist, and serialize a new host."""
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
            self._persist()
            return _serialize_akida_host(host)

    def update(self, host_id: str, payload: dict[str, Any]) -> dict[str, Any]:
        """Merge and persist user-provided host fields."""
        with self._lock:
            host = self.get(host_id)
            normalized = self.normalize_update(host, {"id": host_id, **payload})
            if normalized.get("isDefault"):
                for existing in self._settings["akidaHosts"]:
                    if existing["id"] != host_id:
                        existing["isDefault"] = False
            mutable_host = self._mutable_record(host)
            mutable_host.clear()
            mutable_host.update(normalized)
            self._persist()
            return _serialize_akida_host(host)

    def delete(self, host_id: str) -> None:
        """Delete one host and repair the selected-host pointer."""
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
            self._persist()

    def get(self, host_id: str) -> AkidaHostRecord:
        """Return the mutable internal record owned by launcher settings."""
        for host in self._settings["akidaHosts"]:
            if host["id"] == host_id:
                return host
        raise KeyError(f"Unknown Akida host '{host_id}'")

    def update_fields(self, host_id: str, **fields: Any) -> AkidaHostRecord:
        """Persist trusted coordinator fields and return an isolated copy."""
        with self._lock:
            host = self.get(host_id)
            normalized = self.normalize_update(host, {"id": host_id, **fields})
            mutable_host = self._mutable_record(host)
            mutable_host.clear()
            mutable_host.update(normalized)
            self._persist()
            return AkidaHostRecord(**host)

    @staticmethod
    def normalize_update(
        host: Mapping[str, Any],
        updates: dict[str, Any],
    ) -> AkidaHostRecord:
        """Apply compatibility merge rules before normalizing a host record."""
        merged: dict[str, Any] = dict(host)
        merged.update(updates)
        if str(merged.get("password") or "") and "authMode" not in updates:
            merged["authMode"] = "password"
        if "baseUrl" in updates and "runtimeApiUrl" not in updates:
            merged.pop("runtimeApiUrl", None)
        if "baseUrl" in updates and "port" not in updates:
            merged.pop("port", None)
        return _normalize_akida_host(merged)

    @staticmethod
    def _mutable_record(host: AkidaHostRecord) -> MutableMapping[str, Any]:
        # TypedDict models key shape but typeshed does not expose dict.clear();
        # persisted host records are ordinary mutable dictionaries at runtime.
        return cast(MutableMapping[str, Any], host)


__all__ = ["AkidaHostRepository"]
