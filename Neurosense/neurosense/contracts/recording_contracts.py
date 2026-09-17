from typing import Any, Literal

from pydantic import BaseModel, Field

from neurosense.contracts.encoding_contracts import EncodingConfig


class EventMarker(BaseModel):
    """Event marker contract."""

    timestamp_seconds: float = Field(
        ..., ge=0, description="Offset from recording start in seconds"
    )
    label: str = Field(..., description="Label for the event marker")


class RecordingParams(BaseModel):
    """Recording parameters contract."""

    id: str = Field(..., description="Unique recording identifier")
    timestamp: str = Field(..., description="ISO 8601 timestamp")
    duration_seconds: float = Field(..., ge=0, description="Recording duration in seconds")
    buffer_size: int = Field(..., ge=1, description="Buffer size in samples")
    file_format: Literal["hdf5", "csv"] = Field(..., description="Output file format")
    device_type: str = Field(..., description="Device type (e.g., ganglion, cyton, muse)")
    preset_id: str = Field(..., description="ID of the preset used for recording")
    channels: int = Field(..., ge=1, le=1024, description="Number of analog channels")
    sampling_rate_hz: float = Field(..., ge=100, le=40000, description="Sampling rate in Hz")
    encoding_config: EncodingConfig | None = Field(None, description="Encoding configuration used")
    event_markers: list[EventMarker] = Field(
        default_factory=list, description="List of event markers"
    )
    subject_id: str | None = Field(None, description="Optional subject identifier")
    file_path: str | None = Field(None, description="Path where the file is stored")
    file_size_bytes: int | None = Field(None, ge=0, description="Final file size in bytes")


class RecordingSession(BaseModel):
    """Recording session metadata contract."""

    id: str = Field(..., description="Unique recording identifier")
    timestamp: str = Field(..., description="ISO 8601 timestamp")
    duration_seconds: float = Field(..., ge=0, description="Recording duration in seconds")
    device_type: str = Field(..., description="Device type (e.g., ganglion, cyton, muse)")
    preset_id: str = Field(..., description="ID of the preset used for recording")
    channels: int = Field(..., ge=1, le=1024, description="Number of analog channels")
    sampling_rate_hz: int = Field(..., ge=100, le=40000, description="Native sampling rate in Hz")
    encoding_config: EncodingConfig = Field(..., description="Encoding configuration used")
    event_markers: list[EventMarker] = Field(
        default_factory=list, description="List of event markers"
    )
    file_path: str = Field(..., description="Path where the file is stored")
    file_size_bytes: int = Field(..., ge=0, description="Final file size in bytes")
    subject_id: str | None = Field(None, description="Optional subject identifier")
    artifact_schema_version: str = Field(..., description="Version of the HDF5 artifact schema")
    signal_type: str = Field(..., description="Primary biosignal type for the recording")
    capture_mode: str = Field(..., description="Capture mode used to produce the artifact")
    channel_labels: list[str] = Field(
        default_factory=list,
        description="Canonical channel labels aligned with the stored data arrays",
    )
    hardware_provenance: dict[str, Any] = Field(
        default_factory=dict,
        description="Canonical hardware provenance metadata for the session",
    )
    support_level: str = Field(
        ...,
        description="Truthful support-level label for the acquisition path",
    )
