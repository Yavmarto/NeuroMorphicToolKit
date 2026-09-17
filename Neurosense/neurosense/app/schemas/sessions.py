from typing import Any

from pydantic import BaseModel, Field

from .encoding import EncodingConfig


class EventMarker(BaseModel):
    timestamp_seconds: float = Field(..., description="Offset from recording start in seconds.")
    label: str = Field(..., description="Marker label, for example 'wrist_flexion'.")


class RecordingSession(BaseModel):
    id: str
    timestamp: str  # ISO 8601
    duration_seconds: float
    device_type: str
    preset_id: str
    channels: int
    sampling_rate_hz: int
    encoding_config: EncodingConfig
    event_markers: list[EventMarker]
    file_path: str
    file_size_bytes: int
    subject_id: str | None
    artifact_schema_version: str
    signal_type: str
    capture_mode: str
    channel_labels: list[str]
    hardware_provenance: dict[str, Any]
    support_level: str
