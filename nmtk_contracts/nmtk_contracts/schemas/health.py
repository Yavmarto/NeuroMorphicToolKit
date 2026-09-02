"""Health-check contracts shared by all NMTK service modules."""

from pydantic import BaseModel


class HealthResponse(BaseModel):
    """Service health response payload."""

    status: str


def healthy_response(status: str = "ok") -> HealthResponse:
    """Build the shared service-level health payload.

    All simple module health probes return this so the trivial ``/health``
    handlers share one construction path instead of five copies.
    """
    return HealthResponse(status=status)
