"""Domain contracts for NeuroHub suite orchestration.

Converts neurohub_spec.md into enforceable contracts.

Source: Neurohub/neurohub_spec.md (NH-D1 through NH-TC2)
"""

from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, ConfigDict, field_validator, model_validator


class SuitePortContract(BaseModel):
    """Contract for suite port assignments."""

    model_config = ConfigDict(frozen=True)

    neurocnl: int = 8000
    neurosim: int = 8001
    neurochip: int = 8002
    neurobench: int = 8003
    neurosense: int = 8004
    neurohub: int = 8005

    @model_validator(mode="after")
    def no_port_conflicts(self) -> SuitePortContract:
        ports = [
            self.neurocnl, self.neurosim, self.neurochip,
            self.neurobench, self.neurosense, self.neurohub,
        ]
        if len(set(ports)) != len(ports):
            raise ValueError(f"Port conflict detected: {ports}")
        return self


class HealthCheckContract(BaseModel):
    """Contract for service health check (NH-H1)."""

    model_config = ConfigDict(frozen=True)

    service_name: str
    status: Literal["online", "offline", "degraded"]
    response_time_ms: float | None = None
    version: str | None = None


class ProjectContract(BaseModel):
    """Contract for cross-app project (NH-P1)."""

    model_config = ConfigDict(frozen=True)

    id: str
    name: str
    owner: str
    members: list[dict]
    neurosim_project_id: str | None = None
    neurochip_target_id: str | None = None
    neurobench_benchmark_ids: list[str] = []
    neurosense_session_ids: list[str] = []
    cnl_spec_hash: str | None = None

    @field_validator("name")
    @classmethod
    def non_empty_name(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("Project name must not be empty.")
        return v


class WorkflowStepContract(BaseModel):
    """Contract for pipeline workflow step (NH-W1)."""

    model_config = ConfigDict(frozen=True)

    id: str
    name: str
    app: str
    endpoint: str
    method: Literal["GET", "POST", "PUT", "DELETE"] = "POST"
    success_criteria: str | None = None
    on_failure: Literal["halt", "warn", "skip"] = "halt"
    timeout_seconds: int = 300

    @field_validator("timeout_seconds")
    @classmethod
    def reasonable_timeout(cls, v: int) -> int:
        if v < 1 or v > 3600:
            raise ValueError(f"Timeout {v}s outside range [1, 3600].")
        return v


class WorkflowTemplateContract(BaseModel):
    """Contract for workflow template (NH-W2)."""

    model_config = ConfigDict(frozen=True)

    id: str
    name: str
    steps: list[WorkflowStepContract]
    builtin: bool = False

    @field_validator("steps")
    @classmethod
    def at_least_one_step(cls, v: list) -> list:
        if len(v) < 1:
            raise ValueError("Workflow must have at least 1 step.")
        return v


class MemberRoleContract(BaseModel):
    """Contract for project member role (NH-TC1)."""

    model_config = ConfigDict(frozen=True)

    user_id: str
    name: str
    role: Literal["admin", "engineer", "viewer"]


class ActivityEntryContract(BaseModel):
    """Contract for cross-app activity feed entry (NH-D2).

    Every suite app must expose:
    GET /api/{app}/activity?since={iso_timestamp}&limit={int}
    """

    model_config = ConfigDict(frozen=True)

    timestamp: str
    user: str
    action: str
    app: str
    project_id: str | None = None
    deep_link: str | None = None
