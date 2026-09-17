"""Sessions router -- list, inspect, download, and replay recorded sessions."""

import logging

from fastapi import APIRouter, HTTPException
from fastapi.responses import FileResponse
from pydantic import BaseModel, Field

from ..schemas.encoding import build_encoding_config, encoding_config_from_mapping
from ..schemas.runtime import ReplayStatusResponse
from ..schemas.sessions import EventMarker, RecordingSession
from ..services.replay_service import replay_service
from ..services.session_artifact import load_artifact_metadata
from ..storage import default_recordings_dir

logger = logging.getLogger("neurosense.sessions")

router = APIRouter()

_RECORDINGS_DIR = default_recordings_dir()


def _load_session_metadata(session_id: str) -> RecordingSession:
    """Load session metadata from an HDF5 file.

    Falls back to minimal metadata when h5py is unavailable.
    """
    # Sanitize session_id to prevent path traversal
    safe_session_id = "".join(c for c in session_id if c.isalnum() or c in ("_", "-"))
    if not safe_session_id or safe_session_id != session_id:
        raise ValueError("Invalid session ID.")
    file_path = _RECORDINGS_DIR / f"{safe_session_id}.hdf5"
    if not file_path.exists():
        raise FileNotFoundError(f"Session file not found: {file_path}")

    try:
        artifact = load_artifact_metadata(file_path)
        return RecordingSession(
            id=session_id,
            timestamp=artifact["timestamp"],
            duration_seconds=artifact["duration_seconds"],
            device_type=artifact["device_type"],
            preset_id=artifact["preset_id"],
            channels=artifact["channels"],
            sampling_rate_hz=artifact["sampling_rate_hz"],
            encoding_config=encoding_config_from_mapping(artifact["encoding_config"]),
            event_markers=[EventMarker(**marker) for marker in artifact["event_markers"]],
            file_path=artifact["file_path"],
            file_size_bytes=artifact["file_size_bytes"],
            subject_id=artifact["subject_id"],
            artifact_schema_version=artifact["artifact_schema_version"],
            signal_type=artifact["signal_type"],
            capture_mode=artifact["capture_mode"],
            channel_labels=artifact["channel_labels"],
            hardware_provenance=artifact["hardware_provenance"],
            support_level=artifact["support_level"],
        )
    except ImportError:
        # h5py not available -- return minimal metadata from file system
        return RecordingSession(
            id=session_id,
            timestamp="",
            duration_seconds=0.0,
            device_type="unknown",
            preset_id="unknown",
            channels=0,
            sampling_rate_hz=250,
            encoding_config=build_encoding_config("rate", rate_max_hz=500.0),
            event_markers=[],
            file_path=str(file_path),
            file_size_bytes=file_path.stat().st_size,
            subject_id=None,
            artifact_schema_version="legacy",
            signal_type="unknown",
            capture_mode="unknown",
            channel_labels=[],
            hardware_provenance={},
            support_level="unknown",
        )


@router.get("", response_model=list[RecordingSession])
async def list_sessions() -> list[RecordingSession]:
    """List all recorded sessions.

    Scans the recordings directory for HDF5 files and returns
    metadata for each.
    """
    sessions: list[RecordingSession] = []
    if not _RECORDINGS_DIR.is_dir():
        return sessions

    for hdf5_file in sorted(_RECORDINGS_DIR.glob("*.hdf5")):
        session_id = hdf5_file.stem
        try:
            sessions.append(_load_session_metadata(session_id))
        except Exception:
            logger.warning("Failed to load session metadata for %s", session_id, exc_info=True)
            continue

    return sessions


@router.get("/{session_id}", response_model=RecordingSession)
async def get_session(session_id: str) -> RecordingSession:
    """Get metadata for a specific recorded session."""
    try:
        return _load_session_metadata(session_id)
    except FileNotFoundError as exc:
        raise HTTPException(status_code=404, detail=str(exc))


@router.get("/{session_id}/download")
async def download_session(session_id: str) -> FileResponse:
    """Download the HDF5 file for a recorded session."""
    # Sanitize session_id to prevent path traversal
    safe_session_id = "".join(c for c in session_id if c.isalnum() or c in ("_", "-"))
    if not safe_session_id or safe_session_id != session_id:
        raise HTTPException(status_code=400, detail="Invalid session ID.")
    file_path = _RECORDINGS_DIR / f"{safe_session_id}.hdf5"
    if not file_path.exists():
        raise HTTPException(status_code=404, detail=f"Session '{session_id}' not found.")

    return FileResponse(
        path=str(file_path),
        filename=f"{session_id}.hdf5",
        media_type="application/x-hdf5",
    )


class ReplayRequest(BaseModel):
    """Request body to start a session replay."""

    speed: float = Field(default=1.0, ge=0.1, le=10.0, description="Playback speed multiplier.")


@router.post("/{session_id}/replay", response_model=ReplayStatusResponse)
async def start_replay(
    session_id: str, request: ReplayRequest = ReplayRequest()
) -> ReplayStatusResponse:
    """Start replaying a recorded session.

    Replays the session at the specified speed (0.1x to 10x).
    Replay data is emitted through the streaming WebSocket endpoints.
    """
    safe_session_id = "".join(c for c in session_id if c.isalnum() or c in ("_", "-"))
    if not safe_session_id or safe_session_id != session_id:
        raise HTTPException(status_code=400, detail="Invalid session ID.")
    try:
        result = await replay_service.start(session_id=safe_session_id, speed=request.speed)
        return ReplayStatusResponse(**result)
    except FileNotFoundError as exc:
        raise HTTPException(status_code=404, detail=str(exc))
    except RuntimeError as exc:
        raise HTTPException(status_code=409, detail=str(exc))


@router.post("/{session_id}/replay/stop", response_model=ReplayStatusResponse)
async def stop_replay(session_id: str) -> ReplayStatusResponse:
    """Stop the currently active replay."""
    try:
        result = await replay_service.stop()
        return ReplayStatusResponse(**result)
    except RuntimeError as exc:
        raise HTTPException(status_code=409, detail=str(exc))
