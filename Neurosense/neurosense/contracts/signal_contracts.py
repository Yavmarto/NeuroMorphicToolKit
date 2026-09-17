import math

from pydantic import BaseModel, Field, model_validator


class FilterConfig(BaseModel):
    """Signal filtering constraints contract."""

    bandpass_low_hz: float | None = Field(
        None, ge=0.1, description="Low cutoff frequency for bandpass filter"
    )
    bandpass_high_hz: float | None = Field(
        None, ge=1.0, description="High cutoff frequency for bandpass filter"
    )
    notch_hz: float | None = Field(
        None, ge=45, le=65, description="Notch filter frequency (50 or 60 Hz)"
    )
    artifact_rejection: bool = Field(False, description="Whether to enable artifact rejection")

    @model_validator(mode="after")
    def validate_bandpass(self) -> "FilterConfig":
        if (
            self.bandpass_low_hz is not None
            and self.bandpass_high_hz is not None
            and self.bandpass_low_hz >= self.bandpass_high_hz
        ):
            raise ValueError("bandpass_low_hz must be less than bandpass_high_hz")
        return self


class FilterOutput(BaseModel):
    """Contract for validated filter pipeline output."""

    data: list[list[float]] = Field(..., description="Filtered signal data (channels x samples)")
    channels: int = Field(..., ge=1, description="Number of channels")
    samples: int = Field(..., ge=1, description="Number of samples per channel")
    artifact_rejection_enabled: bool = Field(
        False, description="Whether artifact rejection was applied"
    )

    @model_validator(mode="after")
    def validate_output_integrity(self) -> "FilterOutput":
        # Check shape consistency
        if len(self.data) != self.channels:
            raise ValueError(
                f"Data channel count ({len(self.data)}) does not match channels field ({self.channels})"
            )

        for i, channel_data in enumerate(self.data):
            if len(channel_data) != self.samples:
                raise ValueError(
                    f"Channel {i} sample count ({len(channel_data)}) does not match samples field ({self.samples})"
                )

            # Check for NaN or Inf values
            if any(not math.isfinite(x) for x in channel_data):
                raise ValueError(f"Channel {i} contains non-finite values (NaN or Inf)")

            # If artifact rejection is enabled, enforce amplitude bounds
            if self.artifact_rejection_enabled:
                # Based on FilterPipeline._reject_artifacts threshold of 500.0 uV
                threshold = 500.0
                if any(abs(x) > threshold for x in channel_data):
                    raise ValueError(
                        f"Channel {i} exceeds artifact rejection threshold of {threshold} uV"
                    )

        return self
