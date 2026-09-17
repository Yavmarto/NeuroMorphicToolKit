"""Pydantic contracts for the CNL parse -> validate -> simulate pipeline."""

from typing import Any

from pydantic import BaseModel, ConfigDict, Field


class ErrorDetailContract(BaseModel):
    """Contract for a structured parse or validation error."""

    model_config = ConfigDict(extra="ignore")

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


class ParsedSentenceContract(BaseModel):
    """Contract for a single parsed CNL sentence."""

    model_config = ConfigDict(extra="ignore")

    concept: str
    subject: str
    action: str
    verb: str
    negated: bool
    condition: str | None = None
    raw: str
    line: int | None = None


class CNLParseResultContract(BaseModel):
    """Contract for line-by-line CNL parse result."""

    line: int
    raw: str
    parsed: ParsedSentenceContract | None = None
    valid: bool
    error: str | None = None
    error_detail: ErrorDetailContract | None = None


class InvariantResultContract(BaseModel):
    """Contract for a single invariant check result."""

    model_config = ConfigDict(extra="ignore")

    name: str
    description: str = Field(..., alias="reason", validation_alias="reason")
    result: bool
    code: str | None = None
    message: str | None = None
    source: str | None = None
    field: str | None = None
    value: Any | None = None
    lines: list[int] = Field(default_factory=list)


class Layer1ResultContract(BaseModel):
    """Contract for Layer 1 validation result."""

    model_config = ConfigDict(extra="ignore")

    overall: bool
    passed: list[InvariantResultContract]
    failed: list[InvariantResultContract]


class Layer2ResultContract(BaseModel):
    """Contract for Layer 2 validation result."""

    model_config = ConfigDict(extra="ignore")

    overall: bool
    checks_passed: list[str]
    checks_failed: list[ErrorDetailContract]
    neurons_found: list[str]


class ValidationResultContract(BaseModel):
    """Contract for combined Layer 1 + Layer 2 validation."""

    model_config = ConfigDict(extra="ignore")

    layer1: Layer1ResultContract
    layer2: Layer2ResultContract
    overall: bool


class SimulationResultContract(BaseModel):
    """Contract for simulation output and summary."""

    duration: float
    dt: float
    wall_time_seconds: float
    motor_output: list[list[float]]


class AssertionResultContract(BaseModel):
    """Contract for Layer 3 assertion suite results."""

    passed: int
    failed: int
    returncode: int


class PipelineResultContract(BaseModel):
    """Contract for the full pipeline execution result."""

    model_config = ConfigDict(from_attributes=True, extra="ignore")

    parsed: list[ParsedSentenceContract] = Field(default_factory=list)
    validation: ValidationResultContract | None = None
    simulation: SimulationResultContract | None = None
    assertions: AssertionResultContract | None = None
    errors: list[str] = Field(default_factory=list)
    neuron_params: dict[str, Any] = Field(default_factory=dict)
    overall_pass: bool = False

    # Extra data
    probes: dict[str, Any] = Field(default_factory=dict)
    summary: dict[str, Any] = Field(default_factory=dict)
    benchmarks: dict[str, float] = Field(default_factory=dict)
