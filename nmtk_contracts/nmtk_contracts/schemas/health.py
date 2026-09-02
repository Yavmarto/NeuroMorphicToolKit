"""Health-check contracts shared by all NMTK service modules."""

from pydantic import BaseModel


class HealthResponse(BaseModel):
    """Service health response payload."""

    status: str
