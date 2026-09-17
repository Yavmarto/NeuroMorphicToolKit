from nmtk_contracts.schemas.health import HealthResponse as BaseHealthResponse
from pydantic import BaseModel, Field

from .prosthetic import SensorFrame


class ModuleAvailability(BaseModel):
    """Availability status for an optional runtime module."""

    available: bool
    version: str | None = None


class DiskStatus(BaseModel):
    """Disk usage summary for the health endpoint."""

    total_gb: float
    used_gb: float
    free_gb: float
    low_space: bool


class HealthResponse(BaseHealthResponse):
    """Structured service health payload.

    Extends the shared :class:`nmtk_contracts.schemas.health.HealthResponse`
    contract with the CNL runtime readiness fields the launcher surfaces
    (module availability, disk usage, canvas store/component state).
    """

    neurocnl_version: str
    timestamp: str
    modules: dict[str, ModuleAvailability] = Field(default_factory=dict)
    disk: DiskStatus
    nengo_version: str | None = None
    nengo_available: bool
    mujoco_available: bool
    mujoco_version: str | None = None
    canvas_store: bool | None = None
    canvas_components: bool | None = None


class SerialPortsResponse(BaseModel):
    """Available prosthetic serial ports."""

    ports: list[str] = Field(default_factory=list)


class HardwareConnectionResponse(BaseModel):
    """Hardware connect/disconnect status."""

    status: str
    port: str | None = None


class WelcomeResponse(BaseModel):
    """Fallback root response when a frontend is not mounted."""

    message: str


class SensorStreamEvent(BaseModel):
    """Server-sent event payload for prosthetic hardware streaming."""

    event: str
    data: SensorFrame
