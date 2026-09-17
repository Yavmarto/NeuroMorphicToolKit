"""Routes for importing/exporting NIR graphs as editable canvas payloads."""

from __future__ import annotations

import base64
import io

import nir
from fastapi import APIRouter, HTTPException, Request, Response
from pydantic import BaseModel, Field

from backend.app.services.nir_graph_serializer import (
    NirCanvasConversionError,
    deserialize_canvas_graph,
    serialize_nir_to_canvas_graph,
)
from backend.app.services.nir_import_store import save_nir_import
from neurosim.contracts.design_contracts import CanvasGraph

from ..limiter import rate_limit

router = APIRouter(prefix="/api/neurosim/nir", tags=["nir-canvas"])


class NirCanvasImportRequest(BaseModel):
    """Base64-encoded NIR payload import request."""

    content_b64: str = Field(..., description="Base64-encoded .nir payload")


class NirCanvasImportResponse(BaseModel):
    """Editable canvas payload derived from a NIR graph."""

    graph: CanvasGraph
    diagnostics: list[str] = Field(default_factory=list)
    # Opaque handle to the original uploaded .nir bytes. The CNL text derived
    # from `graph` only carries shapes, not real tensor values (see
    # nir_cnl/renderer.py) — pass this back on /notebook/generate-v2 so real
    # weights can be recovered instead of shipping placeholder values.
    import_id: str = ""


class NirCanvasExportResponse(BaseModel):
    """Base64-encoded NIR payload exported from the canvas graph."""

    content_b64: str
    diagnostics: list[str] = Field(default_factory=list)


@router.post("/import", response_model=NirCanvasImportResponse)
@rate_limit("30/minute")
def import_nir_graph(
    request: Request,
    response: Response,
    body: NirCanvasImportRequest,
) -> NirCanvasImportResponse:
    """Decode a NIR artifact and convert it into a canvas graph."""
    try:
        raw_bytes = base64.b64decode(body.content_b64)
        graph = nir.read(io.BytesIO(raw_bytes))
        canvas_graph = serialize_nir_to_canvas_graph(graph)
        import_id = save_nir_import(raw_bytes)
    except NirCanvasConversionError as exc:
        raise HTTPException(
            status_code=422,
            detail={
                "message": str(exc),
                "unsupported_concepts": exc.unsupported_types,
            },
        ) from exc
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(
            status_code=422,
            detail={
                "message": f"Invalid NIR import payload: {exc}",
                "unsupported_concepts": [],
            },
        ) from exc

    return NirCanvasImportResponse(graph=canvas_graph, import_id=import_id)


@router.post("/export", response_model=NirCanvasExportResponse)
@rate_limit("30/minute")
def export_nir_graph(
    request: Request,
    response: Response,
    graph: CanvasGraph,
) -> NirCanvasExportResponse:
    """Convert a canvas graph into a base64-encoded NIR artifact."""
    try:
        nir_graph = deserialize_canvas_graph(graph)
        buffer = io.BytesIO()
        nir.write(buffer, nir_graph)
    except NirCanvasConversionError as exc:
        raise HTTPException(
            status_code=422,
            detail={
                "message": str(exc),
                "unsupported_concepts": exc.unsupported_types,
            },
        ) from exc
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(
            status_code=422,
            detail={
                "message": f"Canvas graph could not be exported to NIR: {exc}",
                "unsupported_concepts": [],
            },
        ) from exc

    return NirCanvasExportResponse(content_b64=base64.b64encode(buffer.getvalue()).decode("utf-8"))
