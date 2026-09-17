"""Pydantic models for the /api/simulate endpoint."""

from typing import Any

from pydantic import BaseModel, Field

from backend.app.schemas.common import BackendSupport, GeneratorFidelitySummary


class ProbeData(BaseModel):
    type: str
    times: list[float]
    neuron_indices: list[int] | None = None
    values: list[float] | None = None


class SimulationSummary(BaseModel):
    sensory_spike_count: int = 0
    motor_spike_count: int = 0
    sensory_mean_rate: float = 0.0
    motor_mean_rate: float = 0.0
    first_output_spike: float | None = None
    input_to_output_latency: float | None = None


class SimulateRequest(BaseModel):
    spec: str
    params: dict[str, Any] = Field(default_factory=dict)
    duration: float = 1.0
    dt: float = 0.001
    backend: str = "nir"


class SimulateResponse(BaseModel):
    duration: float
    dt: float
    timesteps: int
    probes: dict[str, ProbeData]
    summary: SimulationSummary
    wall_time_seconds: float
    backend_support: BackendSupport | None = None
    generator_fidelity: GeneratorFidelitySummary | None = None
