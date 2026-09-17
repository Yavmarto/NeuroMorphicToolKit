from __future__ import annotations

from typing import Any

from pydantic import BaseModel, ConfigDict, Field


class SuiteHealthResponse(BaseModel):
    status: str
    service: str


class DoctorCheckModel(BaseModel):
    model_config = ConfigDict(extra="allow")

    id: str
    preflightStatus: str | None = None
    preflightMessage: str | None = None
    capabilityWarnings: list[str] = Field(default_factory=list)


class DoctorModuleModel(BaseModel):
    model_config = ConfigDict(extra="allow")

    id: str
    name: str | None = None
    status: str | None = None
    preflightStatus: str | None = None
    preflightMessage: str | None = None
    capabilityWarnings: list[str] = Field(default_factory=list)
    effectivePort: int | None = None


class LauncherDoctorResponse(BaseModel):
    model_config = ConfigDict(extra="allow")

    status: str
    fatalCount: int
    degradedCount: int
    okCount: int
    globalChecks: list[DoctorCheckModel] = Field(default_factory=list)
    modules: list[DoctorModuleModel] = Field(default_factory=list)
    backendDeployment: dict[str, Any] | None = None
    akidaHosts: list[dict[str, Any]] = Field(default_factory=list)
    pynqBoards: list[dict[str, Any]] = Field(default_factory=list)


class LauncherDoctorSummary(BaseModel):
    status: str
    blocking: bool
    fatal_count: int
    degraded_count: int
    ok_count: int
    report: LauncherDoctorResponse
