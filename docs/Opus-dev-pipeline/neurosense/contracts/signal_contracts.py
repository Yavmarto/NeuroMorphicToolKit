"""Domain contracts for NeuroSense signal processing.

Converts neurosense_spec.md into enforceable contracts.

Source: Neurosense/neurosense_spec.md (NSe-DM1 through NSe-PI2)
"""

from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, ConfigDict, field_validator, model_validator


class DeviceContract(BaseModel):
    """Contract for biosignal device discovery (NSe-DM1)."""

    model_config = ConfigDict(frozen=True)

    device_type: Literal[
        "openbci_ganglion",
        "openbci_cyton",
        "muse_2",
        "muse_s",
        "bitalino",
        "generic_serial",
    ]
    n_channels: int
    sample_rate_hz: int

    @field_validator("n_channels")
    @classmethod
    def valid_channels(cls, v: int) -> int:
        if v < 1 or v > 8:
            raise ValueError(
                f"Channel count {v} outside supported range [1, 8] (NSe-SA1)."
            )
        return v


class SignalQualityContract(BaseModel):
    """Contract for signal quality metrics (NSe-SA2)."""

    model_config = ConfigDict(frozen=True)

    snr_db: float
    noise_floor_uv_rms: float
    impedance_kohm: float | None = None
    power_line_interference: float | None = None

    @property
    def quality_level(self) -> Literal["good", "marginal", "unusable"]:
        if self.snr_db > 20 and self.noise_floor_uv_rms < 5:
            return "good"
        elif self.snr_db > 10:
            return "marginal"
        return "unusable"


class EncodingConfigContract(BaseModel):
    """Contract for spike encoding configuration (NSe-SE1)."""

    model_config = ConfigDict(frozen=True)

    method: Literal["rate", "temporal", "delta"]
    rate_max_hz: float = 200.0
    temporal_phase_bins: int = 8
    delta_threshold: float = 0.5

    @field_validator("rate_max_hz")
    @classmethod
    def positive_rate(cls, v: float) -> float:
        if v <= 0:
            raise ValueError(f"Max rate must be > 0, got {v}")
        return v

    @field_validator("temporal_phase_bins")
    @classmethod
    def positive_bins(cls, v: int) -> int:
        if v < 1:
            raise ValueError(f"Phase bins must be >= 1, got {v}")
        return v


class ApplicationPresetContract(BaseModel):
    """Contract for application presets (NSe-SE2).

    Each preset defines filter, encoding, channel mapping, and placement.
    """

    model_config = ConfigDict(frozen=True)

    name: str
    filter_bandpass_low_hz: float
    filter_bandpass_high_hz: float
    filter_notch_hz: float = 50.0
    encoding_method: Literal["rate", "temporal", "delta"]
    channel_mapping: dict[str, int]  # e.g. {"flexor": 0, "extensor": 1}

    @model_validator(mode="after")
    def valid_bandpass(self) -> ApplicationPresetContract:
        if self.filter_bandpass_low_hz >= self.filter_bandpass_high_hz:
            raise ValueError(
                f"Bandpass low ({self.filter_bandpass_low_hz}) must be "
                f"< high ({self.filter_bandpass_high_hz})."
            )
        return self


class DisplayLatencyContract(BaseModel):
    """Contract for display latency (NSe-SA1)."""

    model_config = ConfigDict(frozen=True)

    acquisition_to_display_ms: float

    @field_validator("acquisition_to_display_ms")
    @classmethod
    def under_50ms(cls, v: float) -> float:
        if v > 50:
            raise ValueError(
                f"Display latency {v}ms exceeds 50ms requirement (NSe-SA1)."
            )
        return v


class PipelineLatencyContract(BaseModel):
    """Contract for end-to-end pipeline latency (NSe-PI1)."""

    model_config = ConfigDict(frozen=True)

    end_to_end_ms: float

    @field_validator("end_to_end_ms")
    @classmethod
    def under_100ms(cls, v: float) -> float:
        if v > 100:
            raise ValueError(
                f"Pipeline latency {v}ms exceeds 100ms requirement (NSe-PI1)."
            )
        return v


class RecordingSessionContract(BaseModel):
    """Contract for recording session metadata (NSe-R1)."""

    model_config = ConfigDict(frozen=True)

    timestamp: str
    duration_s: float
    device_type: str
    preset_name: str
    subject_id: str | None = None
    file_format: Literal["hdf5", "csv"] = "hdf5"

    @field_validator("duration_s")
    @classmethod
    def positive_duration(cls, v: float) -> float:
        if v <= 0:
            raise ValueError(f"Recording duration must be > 0, got {v}")
        return v
