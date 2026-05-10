import requests
from pydantic import BaseModel, Field
from typing import Any


class ModuleStatusModel(BaseModel):
    id: str
    name: str | None = None
    status: str | None = None
    route: str | None = None
    effective_port: int | None = None
    health_url: str | None = None
    metadata: dict[str, Any] = Field(default_factory=dict)


class ModuleRegistryClientError(RuntimeError):
    """Raised when launcher module status retrieval fails."""


class ModuleRegistryClient:
    def __init__(self, launcher_base_url: str = "http://127.0.0.1:8765") -> None:
        self.launcher_base_url = launcher_base_url.rstrip("/")

    def list_modules(self) -> list[ModuleStatusModel]:
        """GET /api/launcher/modules and return typed module records."""
        url = f"{self.launcher_base_url}/api/launcher/modules"
        try:
            response = requests.get(url, timeout=10)
            response.raise_for_status()
            data = response.json()
            return [ModuleStatusModel(**item) for item in data]
        except requests.RequestException as e:
            raise ModuleRegistryClientError(f"Failed to list modules: {e}") from e
        except (ValueError, TypeError) as e:
            raise ModuleRegistryClientError(f"Invalid JSON response: {e}") from e

    def get_module(self, module_id: str) -> ModuleStatusModel | None:
        """Return one module by id or None if not present."""
        modules = self.list_modules()
        for module in modules:
            if module.id == module_id:
                return module
        return None
