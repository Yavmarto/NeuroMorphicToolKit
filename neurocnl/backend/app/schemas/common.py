"""Shared Pydantic types used across multiple schemas."""

from pydantic import BaseModel, Field


class SpecRequest(BaseModel):
    """Base request containing a CNL spec string."""

    spec: str


class ErrorDetail(BaseModel):
    """A single error from parsing or validation."""

    code: str | None = None
    message: str | None = None
    hint: str | None = None
    examples: list[str] = Field(default_factory=list)
    line: int | None = None
    raw: str | None = None
    source: str | None = None
    field: str | None = None
    value: object | None = None
    lines: list[int] = Field(default_factory=list)
    name: str | None = None
    reason: str | None = None
    check: str | None = None
    detail: str | None = None
    result: bool | None = None
    description: str | None = None
    severity: str | None = None


class BackendSupport(BaseModel):
    """Stable summary of backend support planning results."""

    backend: str
    verdict: str
    supported_concepts: list[str] = Field(default_factory=list)
    approximated_concepts: list[str] = Field(default_factory=list)
    unsupported_concepts: list[str] = Field(default_factory=list)
    warnings: list[str] = Field(default_factory=list)


class GeneratorFidelityAnnotation(BaseModel):
    """Single generator fidelity annotation."""

    concept: str
    subject: str
    fidelity: str
    reason: str


class GeneratorFidelitySummary(BaseModel):
    """Generator fidelity metadata surfaced by backend APIs."""

    annotations: list[GeneratorFidelityAnnotation] = Field(default_factory=list)
