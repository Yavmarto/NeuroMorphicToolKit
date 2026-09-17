"""Encoding router -- batch spike encoding of analog data."""

from fastapi import APIRouter, HTTPException, Request, Response
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

from ..schemas.encoding import EncodingConfig
from ..services.spike_encoder import spike_encoder

router = APIRouter()


class EncodeRequest(BaseModel):
    """Request body for the batch encode endpoint."""

    data: list[list[float]] = Field(
        ...,
        description="2-D array of analog data (channels x samples) in uV.",
    )
    encoding_config: EncodingConfig = Field(
        ...,
        description="Spike encoding configuration (method + parameters).",
    )
    sampling_rate_hz: float = Field(
        default=250.0,
        description="Sampling rate of the input data in Hz.",
    )


class EncodeResponse(BaseModel):
    """Response body with spike-encoded results."""

    spike_trains: list[list[float]] = Field(
        ...,
        description="Per-channel spike times in seconds.",
    )
    spike_counts: list[int] = Field(
        ...,
        description="Per-channel spike counts.",
    )
    method: str = Field(
        ...,
        description="Encoding method used.",
    )
    channels: int = Field(
        ...,
        description="Number of channels encoded.",
    )
    samples: int = Field(
        ...,
        description="Number of samples per channel in the input.",
    )


@router.post("", response_model=EncodeResponse)
async def encode_data(
    request: Request, response: Response, encode_request: EncodeRequest
) -> JSONResponse:
    """Encode a batch of analog data to spikes.

    Accepts a 2-D array (channels x samples) and an encoding
    configuration, and returns per-channel spike trains.

    This endpoint is intended for offline / batch encoding.
    For real-time encoding, use the /stream/spikes WebSocket.
    """
    if not encode_request.data or not encode_request.data[0]:
        raise HTTPException(status_code=400, detail="Input data must be non-empty.")

    try:
        result = spike_encoder.encode_batch(
            data=encode_request.data,
            config=encode_request.encoding_config,
            sampling_rate=encode_request.sampling_rate_hz,
        )
        return JSONResponse(
            EncodeResponse(
                spike_trains=result["spike_trains"],
                spike_counts=result["spike_counts"],
                method=result["method"],
                channels=len(encode_request.data),
                samples=len(encode_request.data[0]),
            ).model_dump()
        )
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Encoding failed: {exc}")
