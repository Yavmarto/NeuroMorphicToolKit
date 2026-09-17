from typing import Literal

from pydantic import BaseModel, Field, model_validator


class EncodingConfig(BaseModel):
    """Spike encoding constraints contract."""

    method: Literal["rate", "temporal", "delta"] = Field(..., description="Spike encoding method")
    refractory_period: float = Field(0.001, gt=0, description="Refractory period in seconds")
    temporal_resolution: float = Field(0.001, description="Temporal resolution in seconds")

    # Rate encoding parameters
    rate_max_hz: float | None = Field(
        None, ge=1.0, le=1000.0, description="Maximum spike rate for rate encoding"
    )

    # Temporal encoding parameters
    temporal_phase_bins: int | None = Field(
        None, ge=2, le=32, description="Number of phase bins for temporal encoding"
    )

    # Delta encoding parameters
    delta_threshold: float | None = Field(
        None, ge=0.01, le=100.0, description="Delta threshold for delta modulation (µV)"
    )

    @model_validator(mode="after")
    def validate_method_params(self) -> "EncodingConfig":
        if self.method == "rate" and self.rate_max_hz is None:
            raise ValueError("rate_max_hz is required for rate encoding")
        if self.method == "temporal" and self.temporal_phase_bins is None:
            raise ValueError("temporal_phase_bins is required for temporal encoding")
        if self.method == "delta" and self.delta_threshold is None:
            raise ValueError("delta_threshold is required for delta encoding")
        return self
