"""Pydantic schemas for health monitoring in NeuroHub."""

from typing import Literal

from nmtk_contracts.schemas.health import (  # noqa: F401  re-exported for app.main
    HealthResponse,
    healthy_response,
)
from pydantic import BaseModel, Field

__all__ = ["HealthResponse", "healthy_response"]


class ServiceStatus(BaseModel):
    """Model for an individual service health status."""

    name: str
    status: Literal["online", "offline", "degraded"]
    last_checked: str


class ServiceHealth(BaseModel):
    """Model for aggregated health status."""

    services: list[ServiceStatus] = Field(default_factory=list)


class SelfHealthResponse(BaseModel):
    """Model for NeuroHub's self-only health check response."""

    status: Literal["ok", "degraded", "offline"]
    database: str  # "connected" or "unreachable"
    version: str | None = None
