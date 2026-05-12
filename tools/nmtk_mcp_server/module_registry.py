from __future__ import annotations

from typing import Any

import requests
from pydantic import BaseModel, ConfigDict, Field


class ModuleStatusModel(BaseModel):
    model_config = ConfigDict(extra="allow")

    id: str
    name: str | None = None
    status: str | None = None
    preflightStatus: str | None = None
    preflightMessage: str | None = None
    capabilityWarnings: list[str] = Field(default_factory=list)
    environmentFingerprint: str | None = None
    route: str | None = None
    effectivePort: int | None = None
    healthUrl: str | None = None
    metadata: dict[str, Any] = Field(default_factory=dict)


class ModuleRegistryClientError(RuntimeError):
    """Raised when launcher module status retrieval fails."""


class ModuleRegistryClient:
    def __init__(self, launcher_base_url: str = "http://127.0.0.1:8765") -> None:
        self.launcher_base_url = launcher_base_url.rstrip("/")

    def list_modules(self, *, refresh_updates: bool = False) -> list[ModuleStatusModel]:
        """GET /api/launcher/modules and return typed module records."""
        url = f"{self.launcher_base_url}/api/launcher/modules"
        params = {"refreshUpdates": "true"} if refresh_updates else None
        try:
            response = requests.get(url, params=params, timeout=10)
            response.raise_for_status()
        except requests.RequestException as exc:
            raise ModuleRegistryClientError(
                f"Module registry request failed for {url}: {exc}"
            ) from exc

        try:
            data = response.json()
        except ValueError as exc:
            raise ModuleRegistryClientError(
                f"Module registry response was not valid JSON: {exc}"
            ) from exc

        if not isinstance(data, list):
            raise ModuleRegistryClientError(
                f"Module registry response did not return a list: {type(data).__name__}"
            )

        try:
            return [ModuleStatusModel.model_validate(item) for item in data]
        except Exception as exc:
            raise ModuleRegistryClientError(
                f"Module registry response did not match the expected schema: {exc}"
            ) from exc

    def get_module(
        self, module_id: str, *, refresh_updates: bool = False
    ) -> ModuleStatusModel | None:
        """Return one module by id or None if not present."""
        modules = self.list_modules(refresh_updates=refresh_updates)
        for module in modules:
            if module.id == module_id:
                return module
        return None


def shape_module_status(module: ModuleStatusModel) -> dict[str, Any]:
    """Return a transport-neutral module status shape for MCP-facing tools."""
    readiness = _module_readiness(module)
    return {
        "id": module.id,
        "name": module.name,
        "status": module.status,
        "readiness": readiness,
        "blocking": readiness == "preflight_failed",
        "preflightStatus": module.preflightStatus,
        "preflightMessage": module.preflightMessage,
        "capabilityWarnings": list(module.capabilityWarnings),
        "environmentFingerprint": module.environmentFingerprint,
        "route": module.route,
        "effectivePort": module.effectivePort,
        "healthUrl": module.healthUrl,
        "metadata": dict(module.metadata),
    }


def shape_module_statuses(modules: list[ModuleStatusModel]) -> list[dict[str, Any]]:
    """Shape a list of launcher module records without changing semantics."""
    return [shape_module_status(module) for module in modules]


def _module_readiness(module: ModuleStatusModel) -> str:
    preflight_status = module.preflightStatus
    if preflight_status == "preflight_failed":
        return "preflight_failed"
    if preflight_status == "degraded_optional_capability":
        return "degraded_optional_capability"
    if preflight_status == "ok":
        return "ok"
    if module.status == "error":
        return "preflight_failed"
    if module.status == "degraded" or module.capabilityWarnings:
        return "degraded_optional_capability"
    if module.status in {"running", "installed", "starting", "stopping", "updating"}:
        return "ok"
    return "unknown"
