"""Router for exporting the network graph to various formats."""

import io
import json
from typing import Annotated, Literal

from fastapi import APIRouter, Depends, HTTPException, Path, Query, Request, Response
from pydantic import BaseModel

from backend.app.services.nir_graph_serializer import (
    NirCanvasConversionError,
    deserialize_canvas_graph,
)
from neurocnl.pipeline import generate_cnl_from_nir
from neurosim.contracts.design_contracts import (
    BackendSupport,
    GeneratorFidelitySummary,
    SimulationStatus,
)

from ..limiter import rate_limit
from ..schemas.canvas import CanvasGraph
from ..schemas.sweep import SweepStepResult
from ..services.export_generators import (
    generate_mlir_export,
    generate_neuroml,
    generate_nir,
    generate_python_nengo,
    generate_svg,
)
from ..services.job_store import job_store
from ..services.nir_support import assess_export_support

router = APIRouter(prefix="/api/neurosim", tags=["export"])

FORMAT_CNL = "cnl"
FORMAT_PYTHON = "python"
FORMAT_C = "c"
FORMAT_NEUROML = "neuroml"
FORMAT_SVG = "svg"
FORMAT_NIR = "nir"
FORMAT_MLIR = "mlir"


class ExportResponse(BaseModel):
    """Response model for export requests."""

    format: str
    content: str
    backend_support: BackendSupport | None = None
    generator_fidelity: GeneratorFidelitySummary | None = None


class ExportOptions(BaseModel):
    """Query options for graph export requests."""

    preflight: bool = Query(default=False)
    allow_approximate: bool = Query(default=False)


def _raise_export_support_error(
    *,
    status_code: int,
    message: str,
    format: str,
    backend_support: BackendSupport,
    generator_fidelity: GeneratorFidelitySummary | None,
) -> None:
    raise HTTPException(
        status_code=status_code,
        detail={
            "message": message,
            "format": format,
            "backend_support": backend_support.model_dump(),
            "generator_fidelity": (
                generator_fidelity.model_dump() if generator_fidelity is not None else None
            ),
        },
    )


@router.get("/export/sweep/{job_id}/{format}", response_model=ExportResponse)
@rate_limit("60/minute")
def export_sweep_results(
    request: Request,
    response: Response,
    job_id: str = Path(...),
    format: Literal["json", "csv"] = Path(...),
) -> ExportResponse:
    """Export the results of a completed sweep job.

    Args:
        request (Request): The incoming request.
        response (Response): The FastAPI response used by SlowAPI for rate-limit headers.
        job_id (str): The ID of the completed sweep job.
        format (Literal["json", "csv"]): The target export format.

    Returns:
        ExportResponse: The exported results content.
    """
    job = job_store.get_job(job_id)
    if not job or job.type != "sweep":
        raise HTTPException(status_code=404, detail="Sweep job not found")
    if job.status != SimulationStatus.COMPLETED:
        raise HTTPException(status_code=400, detail="Sweep job is not completed")

    step_list = job.results if isinstance(job.results, list) else []
    if format == "json":
        results = [
            step.model_dump() if isinstance(step, SweepStepResult) else step for step in step_list
        ]
        content = json.dumps(results)
    elif format == "csv":
        output = io.StringIO()
        output.write("parameter_value,n_neurons,n_connections\n")
        for step in step_list:
            val = step.parameter_value
            metrics = step.result.metrics or {}
            output.write(
                f"{val},{metrics.get('n_neurons', 0)},{metrics.get('n_connections', 0)}\n",
            )
        content = output.getvalue()
    else:
        raise HTTPException(status_code=400, detail="Unsupported sweep export format")

    return ExportResponse(format=format, content=content)


@router.post("/export/{format}", response_model=ExportResponse)
@rate_limit("60/minute")
def export_graph(
    request: Request,
    response: Response,
    graph: CanvasGraph,
    options: Annotated[ExportOptions, Depends()],
    format: Literal["cnl", "python", "c", "neuroml", "svg", "nir", "mlir"] = Path(...),
) -> ExportResponse:
    """Export the network graph to the specified format.

    Args:
        request (Request): The incoming request object.
        response (Response): The FastAPI response used by SlowAPI for rate-limit headers.
        graph (CanvasGraph): The network graph to export.
        format (Literal["cnl", "python", "c", "neuroml", "svg", "nir", "mlir"]): The target export format.
        options (ExportOptions): Query options controlling preflight-only checks and
            whether approximate exports are allowed.

    Returns:
        ExportResponse: The exported content and the format used.

    Raises:
        HTTPException: If the requested format is not supported.
    """
    backend_support, generator_fidelity = assess_export_support(graph, format)

    if options.preflight:
        return ExportResponse(
            format=format,
            content="",
            backend_support=backend_support,
            generator_fidelity=generator_fidelity,
        )

    if backend_support.verdict == "unsupported":
        _raise_export_support_error(
            status_code=400,
            message=f"Export target {format!r} is unsupported for this design.",
            format=format,
            backend_support=backend_support,
            generator_fidelity=generator_fidelity,
        )

    if backend_support.verdict == "approximate" and not options.allow_approximate:
        _raise_export_support_error(
            status_code=409,
            message=f"Export target {format!r} is approximate and requires confirmation.",
            format=format,
            backend_support=backend_support,
            generator_fidelity=generator_fidelity,
        )

    if format == FORMAT_CNL:
        try:
            content = generate_cnl_from_nir(deserialize_canvas_graph(graph))
        except NirCanvasConversionError as exc:
            raise HTTPException(
                status_code=422,
                detail={
                    "message": str(exc),
                    "unsupported_concepts": exc.unsupported_types,
                },
            ) from exc
    elif format == FORMAT_PYTHON:
        content = generate_python_nengo(graph)
    elif format == FORMAT_C:
        lines = ["#ifndef NEUROSIM_H", "#define NEUROSIM_H", "", "// Network Structure"]
        for node in graph.nodes:
            name = node.parameters.get("name", node.id)
            n_neurons = node.parameters.get("n_neurons", 100)
            lines.append(f"// Population: {name}, Neurons: {n_neurons}")
        lines.append("")
        lines.append("#endif")
        content = "\n".join(lines)
    elif format == FORMAT_NEUROML:
        content = generate_neuroml(graph)
    elif format == FORMAT_SVG:
        content = generate_svg(graph)
    elif format == FORMAT_NIR:
        content = generate_nir(graph)
    elif format == FORMAT_MLIR:
        content = generate_mlir_export(graph)
    else:
        raise HTTPException(status_code=400, detail="Unsupported format")

    return ExportResponse(
        format=format,
        content=content,
        backend_support=backend_support,
        generator_fidelity=generator_fidelity,
    )
