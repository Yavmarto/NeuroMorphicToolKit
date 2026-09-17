"""Recording router -- start, stop, and marker insertion for live sessions."""

from typing import Any

from fastapi import APIRouter, HTTPException, Request, Response
from pydantic import BaseModel, Field

from ..schemas.encoding import EncodingConfig
from ..schemas.runtime import RecordingStartResponse
from ..schemas.sessions import EventMarker, RecordingSession
from ..services.recording_service import recording_service

router = APIRouter()


class StartRecordingRequest(BaseModel):
    """Request body to start a recording session."""

    device_type: str = Field(..., description="Type of connected device (e.g., 'ganglion').")
    preset_id: str = Field(..., description="Active preset ID.")
    channels: int = Field(..., description="Number of channels to record.")
    sampling_rate_hz: int = Field(default=250, description="Sampling rate in Hz.")
    encoding_config: EncodingConfig = Field(
        ..., description="Encoding configuration for the session."
    )
    subject_id: str | None = Field(default=None, description="Optional subject identifier.")
    signal_type: str = Field(default="emg", description="Primary signal type for the session.")
    channel_labels: list[str] = Field(
        default_factory=list,
        description="Ordered labels aligned to the recorded channels.",
    )
    hardware_provenance: dict[str, Any] | None = Field(
        default=None,
        description="Optional hardware provenance details to persist with the artifact.",
    )


class MarkerRequest(BaseModel):
    """Request body to insert an event marker."""

    label: str = Field(..., description="Event label (e.g., 'wrist_flexion').")


@router.post("/start", response_model=RecordingStartResponse)
async def start_recording(
    request: Request, response: Response, recording_request: StartRecordingRequest
) -> RecordingStartResponse:
    """Start recording a new session.

    Begins capturing raw, filtered, and spike-encoded data to an HDF5
    file.  Only one recording may be active at a time.
    """
    try:
        result = await recording_service.start(
            device_type=recording_request.device_type,
            preset_id=recording_request.preset_id,
            channels=recording_request.channels,
            sampling_rate_hz=recording_request.sampling_rate_hz,
            encoding_config=recording_request.encoding_config,
            subject_id=recording_request.subject_id,
            signal_type=recording_request.signal_type,
            channel_labels=recording_request.channel_labels,
            hardware_provenance=recording_request.hardware_provenance,
        )
        return RecordingStartResponse(**result)
    except RuntimeError as exc:
        raise HTTPException(status_code=409, detail=str(exc))


@router.post("/stop", response_model=RecordingSession)
async def stop_recording(request: Request, response: Response) -> RecordingSession:
    """Stop the active recording and persist to disk.

    Returns the completed RecordingSession metadata including file
    path, duration, and event markers.
    """
    try:
        session = await recording_service.stop()
        return session
    except RuntimeError as exc:
        raise HTTPException(status_code=409, detail=str(exc))


@router.post("/marker", response_model=EventMarker)
async def insert_marker(
    request: Request, response: Response, marker_request: MarkerRequest
) -> EventMarker:
    """Insert a timestamped event marker into the active recording.

    Markers are stored with their offset from the recording start time.
    """
    try:
        marker = await recording_service.insert_marker(label=marker_request.label)
        return marker
    except RuntimeError as exc:
        raise HTTPException(status_code=409, detail=str(exc))
