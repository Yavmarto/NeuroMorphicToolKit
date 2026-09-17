from nmtk_contracts.schemas.health import (  # noqa: F401  re-exported for app.main
    HealthResponse,
    healthy_response,
)
from pydantic import BaseModel, Field

__all__ = ["HealthResponse", "healthy_response"]


class JobQueuedResponse(BaseModel):
    """Queued benchmark job identifier."""

    job_id: str


class JobCancelledResponse(BaseModel):
    """Benchmark job cancellation status."""

    success: bool


class PowerTraceResponse(BaseModel):
    """Power rail time-series trace for a benchmark run."""

    run_id: str
    timestamps: list[float] = Field(default_factory=list)
    vcc_int: list[float] = Field(default_factory=list)
    vcc_aux: list[float] = Field(default_factory=list)
    ps: list[float] = Field(default_factory=list)
