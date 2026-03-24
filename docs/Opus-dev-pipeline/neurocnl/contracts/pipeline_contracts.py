"""Contracts for the CNL pipeline stages and API responses.

These enforce the shape and validity of data flowing through
parse → validate → generate → simulate → assert.
"""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict, field_validator


class CNLParseResultContract(BaseModel):
    """Contract for a single parsed CNL sentence."""

    model_config = ConfigDict(frozen=True)

    concept: str
    subject: str
    action: str
    verb: str
    negated: bool
    condition: str | None
    raw: str

    @field_validator("concept")
    @classmethod
    def valid_concept(cls, v: str) -> str:
        valid_concepts = {
            "threshold_firing",
            "refractory_period",
            "membrane_potential_decay",
            "synaptic_weight",
            "axonal_delay",
            "stdp_learning",
            "inhibitory_connection",
            "population_coding",
            "network_topology",
            "lateral_inhibition",
            "homeostatic_plasticity",
            "neuromodulation",
            "population_coding_range",
        }
        if v not in valid_concepts:
            raise ValueError(f"Unknown concept '{v}'. Valid: {valid_concepts}")
        return v


class ValidationResultContract(BaseModel):
    """Contract for pipeline validation response."""

    model_config = ConfigDict(frozen=True)

    layer1_overall: bool
    layer1_passed: list[str]
    layer1_failed: list[str]
    layer2_overall: bool
    layer2_checks_passed: list[str]
    layer2_checks_failed: list[str]
    overall: bool


class SimulationResultContract(BaseModel):
    """Contract for simulation output."""

    model_config = ConfigDict(frozen=True)

    duration: float
    dt: float
    wall_time_seconds: float

    @field_validator("duration")
    @classmethod
    def positive_duration(cls, v: float) -> float:
        if v <= 0:
            raise ValueError(f"Duration must be > 0, got {v}")
        return v

    @field_validator("dt")
    @classmethod
    def valid_timestep(cls, v: float) -> float:
        if v <= 0 or v > 0.1:
            raise ValueError(f"Timestep dt={v} outside valid range (0, 0.1]")
        return v


class SimulationSummaryContract(BaseModel):
    """Contract for simulation summary statistics."""

    model_config = ConfigDict(frozen=True)

    sensory_spike_count: int
    motor_spike_count: int
    sensory_mean_rate: float
    motor_mean_rate: float
    first_output_spike: float | None
    input_to_output_latency: float | None

    @field_validator("sensory_spike_count", "motor_spike_count")
    @classmethod
    def non_negative_counts(cls, v: int) -> int:
        if v < 0:
            raise ValueError(f"Spike count cannot be negative, got {v}")
        return v

    @field_validator("sensory_mean_rate", "motor_mean_rate")
    @classmethod
    def non_negative_rate(cls, v: float) -> float:
        if v < 0:
            raise ValueError(f"Firing rate cannot be negative, got {v}")
        return v


class AssertionResultContract(BaseModel):
    """Contract for Layer 3 assertion execution result."""

    model_config = ConfigDict(frozen=True)

    passed: int
    failed: int
    returncode: int

    @field_validator("passed", "failed")
    @classmethod
    def non_negative(cls, v: int) -> int:
        if v < 0:
            raise ValueError(f"Count cannot be negative, got {v}")
        return v


# === API Response Contracts ===


class ParseAPIResponse(BaseModel):
    """Contract: POST /api/parse response shape."""

    results: list[dict]
    valid_count: int
    error_count: int


class ValidateAPIResponse(BaseModel):
    """Contract: POST /api/validate response shape."""

    layer1: dict
    layer2: dict
    overall: bool


class SimulateAPIResponse(BaseModel):
    """Contract: POST /api/simulate response shape."""

    duration: float
    dt: float
    wall_time_seconds: float
    motor_output: list
    probes: dict | None = None
    summary: dict | None = None
