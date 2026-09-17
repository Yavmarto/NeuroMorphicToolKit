from enum import StrEnum
from typing import ClassVar, Literal

from pydantic import BaseModel, Field, model_validator


class DeviceState(StrEnum):
    """Device connection states."""

    DISCONNECTED = "disconnected"
    CONNECTING = "connecting"
    CONNECTED = "connected"
    DISCONNECTING = "disconnecting"
    ERROR = "error"


class ConnectionTransition(BaseModel):
    """Contract for valid device connection state transitions."""

    from_state: DeviceState
    to_state: DeviceState

    # Valid state transitions matrix
    VALID_TRANSITIONS: ClassVar[dict[DeviceState, set[DeviceState]]] = {
        DeviceState.DISCONNECTED: {DeviceState.CONNECTING},
        DeviceState.CONNECTING: {
            DeviceState.CONNECTED,
            DeviceState.ERROR,
            DeviceState.DISCONNECTED,
        },
        DeviceState.CONNECTED: {DeviceState.DISCONNECTING, DeviceState.ERROR},
        DeviceState.DISCONNECTING: {DeviceState.DISCONNECTED, DeviceState.ERROR},
        DeviceState.ERROR: {DeviceState.DISCONNECTED, DeviceState.CONNECTING},
    }

    @model_validator(mode="after")
    def validate_transition(self) -> "ConnectionTransition":
        if (
            self.to_state not in self.VALID_TRANSITIONS[self.from_state]
            and self.from_state != self.to_state
        ):
            raise ValueError(f"Invalid state transition: {self.from_state} -> {self.to_state}")

        return self


class DeviceConfig(BaseModel):
    """Device configuration contract."""

    channel_count: int = Field(..., ge=1, le=1024, description="Number of analog channels")
    sample_rate_hz: float = Field(..., ge=100, le=40000, description="Native sampling rate in Hz")
    gain: float = Field(..., ge=0.1, le=1000, description="Signal gain factor")


class DeviceInfoContract(BaseModel):
    """Device information contract from spec.

    Distinct from the live API ``DeviceInfo`` in ``app.schemas.devices``:
    this contract adds validation bounds/defaults and is not currently
    consumed by any router or service.
    """

    id: str = Field(..., description="Unique device identifier")
    name: str = Field(..., description="Device name (e.g., OpenBCI Ganglion)")
    type: str = Field(..., description="Device type (e.g., ganglion, cyton, muse)")
    serial_port: str | None = Field(None, description="Serial port if applicable")
    channels: int = Field(..., ge=1, le=1024, description="Number of analog channels")
    sampling_rate_hz: int = Field(..., ge=100, le=40000, description="Native sampling rate")
    connected: bool = Field(..., description="Connection status")
    battery_pct: int | None = Field(None, ge=0, le=100, description="Battery percentage")
    support_level: str = Field(
        "experimental",
        description="Hardware support level: validated, experimental, prototype, or planned",
    )


class ChannelQuality(BaseModel):
    """Channel quality contract for signal integrity."""

    channel: int = Field(..., ge=0, description="Channel index")
    label: str = Field(..., description="Channel label")
    snr_db: float = Field(..., description="Signal-to-noise ratio in dB")
    noise_floor_uv_rms: float = Field(..., description="Noise floor in µV RMS")
    impedance_kohm: float | None = Field(None, description="Impedance in kΩ")
    power_line_interference_db: float = Field(
        ..., description="Power line interference level in dB"
    )
    status: Literal["good", "marginal", "unusable"] = Field(..., description="Quality status")
    suggestion: str | None = Field(None, description="Actionable suggestion for improvement")


class SignalQuality(BaseModel):
    """Signal quality dashboard contract."""

    channels: list[ChannelQuality] = Field(..., description="List of per-channel quality metrics")
