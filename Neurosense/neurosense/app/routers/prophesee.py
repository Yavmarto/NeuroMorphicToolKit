"""Prophesee router -- handle device discovery and streaming for event cameras."""

from fastapi import APIRouter, HTTPException, Request, Response
from pydantic import BaseModel

from ..schemas.runtime import (
    PropheseeDeviceInfo,
    PropheseeDevicesResponse,
    StreamStartResponse,
    StreamStopResponse,
)
from ..services.event_encoder import event_encoder
from ..sources.prophesee_source import METAVISION_AVAILABLE, PropheseeSource

router = APIRouter()


class _StreamState:
    """Container for the currently active stream source."""

    def __init__(self) -> None:
        self.source: PropheseeSource | None = None


_stream_state = _StreamState()


class StreamStartRequest(BaseModel):
    mode: str = "live"
    path: str | None = None
    delta_t: int = 10000


@router.get("/devices", response_model=PropheseeDevicesResponse)
async def get_devices(request: Request, response: Response) -> PropheseeDevicesResponse:
    """Discover available Prophesee devices.

    Currently assumes a single EVK connected if metavision is available.
    """
    if not METAVISION_AVAILABLE:
        return PropheseeDevicesResponse(devices=[], error="metavision-sdk not installed")

    # In a real implementation, we might use metavision_hal to query device list.
    # For now, we return a generic indicator if the SDK is present.
    return PropheseeDevicesResponse(
        devices=[PropheseeDeviceInfo(id="evk_live", name="Prophesee EVK", type="event_camera")]
    )


@router.post("/stream/start", response_model=StreamStartResponse)
async def start_stream(
    request: Request, response: Response, config: StreamStartRequest
) -> StreamStartResponse:
    """Start streaming from a Prophesee camera or offline file."""
    if not METAVISION_AVAILABLE:
        raise HTTPException(status_code=500, detail="metavision-sdk not installed")

    if _stream_state.source is not None and _stream_state.source.is_open:
        raise HTTPException(status_code=409, detail="Stream is already active.")

    try:
        source = PropheseeSource(mode=config.mode, path=config.path)
        source.open(delta_t=config.delta_t)

        event_encoder.configure(source.width, source.height)

        _stream_state.source = source

        # We don't start an asyncio task for websocket streaming here,
        # but in a real app we'd broadcast to connected websockets.
        # For the integration plan, we just keep the source open.

        return StreamStartResponse(
            status="started",
            mode=config.mode,
            resolution=[source.width, source.height],
        )
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@router.post("/stream/stop", response_model=StreamStopResponse)
async def stop_stream(request: Request, response: Response) -> StreamStopResponse:
    """Stop the active Prophesee stream."""
    source = _stream_state.source
    if source is None or not source.is_open:
        return StreamStopResponse(status="already_stopped")

    try:
        source.close()
        _stream_state.source = None
        return StreamStopResponse(status="stopped")
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))
