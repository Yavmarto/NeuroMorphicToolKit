from typing import Literal

from pydantic import BaseModel


class ChannelQuality(BaseModel):
    channel: int
    label: str  # e.g., "flexor"
    snr_db: float
    noise_floor_uv_rms: float
    impedance_kohm: float | None
    power_line_interference_db: float
    artifact_detected: bool
    signal_quality_score: float  # 0.0 to 1.0
    status: Literal["good", "marginal", "unusable"]
    suggestion: str | None  # e.g., "Check electrode contact"


class SignalQuality(BaseModel):
    channels: list[ChannelQuality]
