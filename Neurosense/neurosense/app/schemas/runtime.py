from typing import Any

from nmtk_contracts.schemas.health import (  # noqa: F401  re-exported for app.main
    HealthResponse,
    healthy_response,
)
from pydantic import BaseModel, Field

__all__ = ["HealthResponse", "healthy_response"]


class WelcomeResponse(BaseModel):
    """Root endpoint payload when the frontend bundle is absent."""

    message: str


class RecordingStartResponse(BaseModel):
    """Response returned when a recording session starts."""

    session_id: str
    timestamp: str
    status: str


class ReplayStatusResponse(BaseModel):
    """Replay start/stop status payload."""

    session_id: str | None = None
    speed: float | None = None
    status: str


class ImpedanceResult(BaseModel):
    """Impedance check result."""

    device_id: str
    channels: dict[int, float | None]
    status: str
    message: str | None = None


class DeviceConnectionResponse(BaseModel):
    """Connected/disconnected device response with optional warning."""

    id: str
    name: str
    type: str
    serial_port: str | None
    channels: int
    sampling_rate_hz: int
    connected: bool
    battery_pct: int | None
    support_level: str = "experimental"
    warning: str | None = None


class PynqDeviceInfo(BaseModel):
    """Remote PYNQ sensor node metadata."""

    device_id: str
    ip_address: str
    status: str
    sensors: list[str] = Field(default_factory=list)


class PynqDevicesResponse(BaseModel):
    """List of available PYNQ sensor nodes."""

    devices: list[PynqDeviceInfo] = Field(default_factory=list)


class PynqStreamStopResponse(BaseModel):
    """Stop status for a PYNQ sensor stream."""

    status: str
    device_id: str


class PropheseeDeviceInfo(BaseModel):
    """Prophesee camera descriptor."""

    id: str
    name: str
    type: str


class PropheseeDevicesResponse(BaseModel):
    """Discovered Prophesee devices."""

    devices: list[PropheseeDeviceInfo] = Field(default_factory=list)
    error: str | None = None


class StreamStartResponse(BaseModel):
    """Event camera stream start payload."""

    status: str
    mode: str
    resolution: list[int] = Field(default_factory=list)


class StreamStopResponse(BaseModel):
    """Event camera stream stop payload."""

    status: str


class FlexiblePayload(BaseModel):
    """Fallback structured payload for dynamic JSON data."""

    model_config = {"extra": "allow"}

    data: dict[str, Any] = Field(default_factory=dict)
