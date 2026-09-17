"""Protocols for launcher services owned outside the server façade."""

from __future__ import annotations

from typing import Any, Protocol


class DeploymentServiceProtocol(Protocol):
    """Behavior the launcher state requires from deployment orchestration."""

    def is_ready(self) -> bool: ...

    def selected_target(self) -> dict[str, Any] | None: ...

    def list_targets(self) -> list[dict[str, Any]]: ...

    def create_target(self, payload: dict[str, Any]) -> dict[str, Any]: ...

    def update_target(
        self, target_id: str, payload: dict[str, Any]
    ) -> dict[str, Any]: ...

    def delete_target(self, target_id: str) -> None: ...

    def preflight(self, payload: dict[str, Any]) -> dict[str, Any]: ...

    def bootstrap_remote_user(self, payload: dict[str, Any]) -> dict[str, Any]: ...

    def create_job(self, payload: dict[str, Any]) -> dict[str, Any]: ...

    def get_job(self, job_id: str) -> dict[str, Any]: ...

    def cancel_job(self, job_id: str) -> dict[str, Any]: ...

    def retry_job(self, job_id: str) -> dict[str, Any]: ...

    def job_events(self, job_id: str) -> list[str]: ...


class RuntimeArtifactProtocol(Protocol):
    """Minimum runtime artifact metadata exposed through launcher settings."""

    version: str


__all__ = ["DeploymentServiceProtocol", "RuntimeArtifactProtocol"]
