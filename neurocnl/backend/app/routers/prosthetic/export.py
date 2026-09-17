"""POST /api/prosthetic/export/crossbar — quantized weight export."""

from __future__ import annotations

import io

import numpy as np
import structlog
from fastapi import APIRouter, HTTPException, Request, Response
from fastapi.responses import StreamingResponse

from backend.app.middleware.rate_limit import limiter
from backend.app.schemas.prosthetic import CrossbarExportRequest, CrossbarExportResult

router = APIRouter()
logger = structlog.get_logger(__name__)


def _quantize(weights: list[list[float]], bit_width: int) -> dict:
    """Uniform quantization of a weight matrix."""
    arr = np.array(weights, dtype=np.float64)
    n_levels = 2**bit_width
    w_min, w_max = float(arr.min()), float(arr.max())
    if w_max == w_min:
        scale = 1.0
    else:
        scale = (w_max - w_min) / (n_levels - 1)
    zero_point = w_min
    quantized = np.round((arr - zero_point) / scale).astype(int)
    dequantized = (quantized * scale + zero_point).tolist()
    nonzero = int(np.count_nonzero(quantized))
    total = quantized.size
    sparsity = 1.0 - (nonzero / total) if total > 0 else 0.0
    return {
        "quantized_weights": dequantized,
        "scale_factor": scale,
        "zero_point": zero_point,
        "sparsity": sparsity,
    }


@router.post("/export/crossbar", response_model=CrossbarExportResult)
@limiter.limit("20/minute")
def crossbar_export(
    request: Request, response: Response, body: CrossbarExportRequest
) -> CrossbarExportResult | StreamingResponse:
    if not body.learned_weights:
        raise HTTPException(status_code=422, detail="learned_weights cannot be empty")

    qr = _quantize(body.learned_weights, body.bit_width)

    if body.format == "hdf5":
        try:
            import h5py
        except ImportError:
            raise HTTPException(status_code=503, detail="h5py not installed")

        buf = io.BytesIO()
        with h5py.File(buf, "w") as f:
            f.create_dataset("weights", data=np.array(qr["quantized_weights"]))
            f.attrs["bit_width"] = body.bit_width
            f.attrs["scale_factor"] = qr["scale_factor"]
            f.attrs["zero_point"] = qr["zero_point"]
        buf.seek(0)
        return StreamingResponse(
            buf,
            media_type="application/x-hdf5",
            headers={"Content-Disposition": "attachment; filename=crossbar_weights.h5"},
        )

    return CrossbarExportResult(
        quantized_weights=qr["quantized_weights"],
        bit_width=body.bit_width,
        scale_factor=qr["scale_factor"],
        zero_point=qr["zero_point"],
        sparsity=qr["sparsity"],
    )
