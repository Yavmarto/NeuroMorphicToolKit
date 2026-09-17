"""Pydantic models for the /api/validate endpoint."""

from typing import Any

from pydantic import BaseModel, Field, model_validator

from backend.app.schemas.common import BackendSupport, ErrorDetail


class InvariantResult(BaseModel):
    name: str
    description: str | None = None
    reason: str | None = None
    result: bool = True
    code: str | None = None
    message: str | None = None
    hint: str | None = None
    examples: list[str] = Field(default_factory=list)
    line: int | None = None
    source: str | None = None
    field: str | None = None
    value: object | None = None
    lines: list[int] = Field(default_factory=list)
    raw: str | None = None
    severity: str | None = None

    @model_validator(mode="after")
    def sync_legacy_fields(self) -> "InvariantResult":
        if self.description is None and self.reason is not None:
            self.description = self.reason
        if self.reason is None and self.description is not None:
            self.reason = self.description
        return self


class Layer1Result(BaseModel):
    overall: bool
    passed: list[InvariantResult]
    failed: list[InvariantResult]
    warnings: list[InvariantResult] = Field(default_factory=list)


class Layer2Result(BaseModel):
    overall: bool
    checks_passed: list[str]
    checks_failed: list[ErrorDetail]
    neurons_found: list[str]


class ValidateRequest(BaseModel):
    spec: str
    params: dict[str, Any] = Field(default_factory=dict)
    backend: str = "nir"


class ValidateResponse(BaseModel):
    layer1: Layer1Result
    layer2: Layer2Result
    overall: bool
    backend_support: BackendSupport | None = None
