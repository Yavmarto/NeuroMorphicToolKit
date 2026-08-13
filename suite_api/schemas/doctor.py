"""Typed whole-system health contracts shared by Suite API doctor routes."""

from enum import StrEnum

from pydantic import BaseModel, Field


class DoctorStatus(StrEnum):
    """Machine-readable status for one diagnostic check."""

    OK = "ok"
    DEGRADED = "degraded"
    FAILED = "failed"
    NOT_CONFIGURED = "notConfigured"


class DoctorCheck(BaseModel):
    """One actionable diagnostic result."""

    id: str
    label: str
    status: DoctorStatus
    detail: str
    recovery: str = ""
    repairable: bool = False
    required: bool = True


class DoctorRequest(BaseModel):
    """Capabilities configured for the current server/workflow."""

    capabilities: list[str] = Field(default_factory=lambda: ["snntorch"])


class DoctorReport(BaseModel):
    """Whole-system health report returned to the launcher."""

    overall: DoctorStatus
    checked_at: str = Field(alias="checkedAt")
    checks: list[DoctorCheck]

    model_config = {"populate_by_name": True}
