from __future__ import annotations

from typing import Any

from pydantic import BaseModel, ConfigDict, Field, model_validator


class ValidateCnlRequest(BaseModel):
    spec: str
    backend: str = "nengo"
    params: dict[str, Any] = Field(default_factory=dict)


class BackendSupportModel(BaseModel):
    backend: str
    verdict: str
    supported_concepts: list[str] = Field(default_factory=list)
    approximated_concepts: list[str] = Field(default_factory=list)
    unsupported_concepts: list[str] = Field(default_factory=list)
    warnings: list[str] = Field(default_factory=list)


class InvariantResultModel(BaseModel):
    name: str | None = None
    description: str | None = None
    reason: str | None = None
    detail: str | None = None
    result: bool | None = None
    code: str | None = None
    message: str | None = None
    hint: str | None = None
    examples: list[str] = Field(default_factory=list)
    line: int | None = None
    lines: list[int] = Field(default_factory=list)
    source: str | None = None
    field: str | None = None
    value: Any | None = None
    raw: str | None = None
    severity: str | None = None

    @model_validator(mode="after")
    def sync_legacy_fields(self) -> InvariantResultModel:
        if self.description is None and self.reason is not None:
            self.description = self.reason
        if self.reason is None and self.description is not None:
            self.reason = self.description
        if self.detail is None and self.message is not None:
            self.detail = self.message
        return self


class ErrorDetailModel(BaseModel):
    model_config = ConfigDict(extra="allow")

    code: str | None = None
    message: str | None = None
    hint: str | None = None
    examples: list[str] = Field(default_factory=list)
    line: int | None = None
    raw: str | None = None
    source: str | None = None
    field: str | None = None
    value: Any | None = None
    lines: list[int] = Field(default_factory=list)
    name: str | None = None
    reason: str | None = None
    check: str | None = None
    detail: str | None = None
    result: bool | None = None
    description: str | None = None
    severity: str | None = None


class Layer1ResultModel(BaseModel):
    overall: bool
    passed: list[InvariantResultModel] = Field(default_factory=list)
    failed: list[InvariantResultModel] = Field(default_factory=list)
    warnings: list[InvariantResultModel] = Field(default_factory=list)


class Layer2ResultModel(BaseModel):
    overall: bool
    checks_passed: list[str] = Field(default_factory=list)
    checks_failed: list[ErrorDetailModel] = Field(default_factory=list)
    neurons_found: list[str] = Field(default_factory=list)


class ValidateCnlResponse(BaseModel):
    layer1: Layer1ResultModel
    layer2: Layer2ResultModel
    overall: bool
    backend_support: BackendSupportModel | None = None
