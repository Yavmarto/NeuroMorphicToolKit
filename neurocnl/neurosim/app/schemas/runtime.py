from typing import Any

from nmtk_contracts.schemas.health import (  # noqa: F401  re-exported for app.main
    HealthResponse,
)
from pydantic import BaseModel, Field


class WelcomeResponse(BaseModel):
    """Root endpoint payload when frontend assets are absent."""

    message: str


class GenericSimulationJobResponse(BaseModel):
    """Simulation job payload for non-preview jobs."""

    job_id: str
    status: str
    results: dict[str, Any] = Field(default_factory=dict)
    metrics: dict[str, Any] | None = None
    error: str | None = None
    parameter_path: str | None = None
    backend_support: dict[str, Any] | None = None
    generator_fidelity: dict[str, Any] | None = None


class CancelSimulationResponse(BaseModel):
    """Simulation cancellation response."""

    message: str
