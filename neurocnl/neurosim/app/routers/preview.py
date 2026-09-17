"""Router for simulation preview."""

import io
import zipfile
from typing import Any

import numpy as np
from fastapi import APIRouter, BackgroundTasks, HTTPException, Query, Request, Response

from neurosim.contracts.design_contracts import SimulationStatus

from ..limiter import rate_limit
from ..schemas.preview import PreviewRequest, PreviewResponse
from ..schemas.runtime import CancelSimulationResponse
from ..schemas.sweep import SweepResponse
from ..services.job_store import job_store
from ..services.nir_support import assess_preview_support
from ..services.preview_runner import run_preview_sync

router = APIRouter(prefix="/api/neurosim", tags=["preview"])


@router.post("/preview", response_model=PreviewResponse)
@rate_limit("20/minute")
def preview(
    request: Request,
    response: Response,
    payload: PreviewRequest,
    background_tasks: BackgroundTasks,
) -> PreviewResponse:
    """Run a short simulation for real-time preview (<=500ms sim time).

    Args:
        request (Request): The FastAPI request object.
        response (Response): The FastAPI response used by SlowAPI for rate-limit headers.
        payload (PreviewRequest): The preview request including graph and parameters.
        background_tasks (BackgroundTasks): FastAPI background tasks.

    Returns:
        PreviewResponse: Initial job info.
    """
    backend_support, generator_fidelity = assess_preview_support(payload.graph)
    if backend_support.verdict == "unsupported":
        return PreviewResponse(
            status=SimulationStatus.FAILED,
            error="Preview is unsupported for the selected backend.",
            results={},
            playback=None,
            backend_support=backend_support,
            generator_fidelity=generator_fidelity,
        )

    job_id = job_store.create_job("preview")
    job = job_store.get_job(job_id)
    if job is not None:
        job.backend_support = backend_support
        job.generator_fidelity = generator_fidelity

    background_tasks.add_task(run_preview_sync, payload, job_id)

    return PreviewResponse(
        job_id=job_id,
        status=job.status if job is not None else SimulationStatus.QUEUED,
        results={},
        backend_support=backend_support,
        generator_fidelity=generator_fidelity,
    )


@router.get(
    "/simulations/{job_id}",
    response_model=PreviewResponse | SweepResponse,
)
@rate_limit("20/minute")
def get_simulation_status(
    request: Request,
    response: Response,
    job_id: str,
) -> PreviewResponse | SweepResponse:
    """Get the status and results of a simulation job."""
    job = job_store.get_job(job_id)
    if not job:
        raise HTTPException(status_code=404, detail="Job not found")

    if job.type == "sweep":
        return SweepResponse(
            job_id=job.job_id,
            status=job.status,
            error=job.error,
            parameter_path=getattr(job, "parameter_path", ""),
            steps=job.results,
            backend_support=getattr(job, "backend_support", None),
            generator_fidelity=getattr(job, "generator_fidelity", None),
        )

    return PreviewResponse(
        job_id=job.job_id,
        status=job.status,
        results=job.results or {},
        playback=getattr(job, "playback", None),
        error=job.error,
        metrics=getattr(job, "metrics", None),
        backend_support=getattr(job, "backend_support", None),
        generator_fidelity=getattr(job, "generator_fidelity", None),
    )


@router.post("/simulations/{job_id}/cancel", response_model=CancelSimulationResponse)
@rate_limit("20/minute")
def cancel_simulation(
    request: Request,
    response: Response,
    job_id: str,
) -> CancelSimulationResponse:
    """Cancel a simulation job."""
    success = job_store.cancel_job(job_id)
    if not success:
        raise HTTPException(
            status_code=404, detail="Job not found or already completed/cancelled"
        )
    return CancelSimulationResponse(message="Job cancelled")


@router.get("/simulations/{job_id}/activity.npy")
@rate_limit("20/minute")
def export_activity_npy(
    request: Request,
    response: Response,
    job_id: str,
    node_id: str | None = Query(
        default=None, description="Node ID to export; omit for all nodes (returns .zip)"
    ),
    probe: str = Query(
        default="spikes", description="Probe type: 'spikes' or 'voltage'"
    ),
) -> Response:
    """Export simulation probe data as numpy .npy (single node) or .zip (all nodes).

    Returns a dense (T, N) float32 array for voltage probes, or a 1-D spike-time
    array for spike probes.  When *node_id* is omitted, all probes are packed into
    a zip archive with filenames ``{node_id}_{probe}.npy``.
    """
    job = job_store.get_job(job_id)
    if not job:
        raise HTTPException(status_code=404, detail="Simulation job not found")
    if not job.results:
        raise HTTPException(
            status_code=404,
            detail="No results available yet — simulation may still be running",
        )
    if not isinstance(job.results, dict):
        raise HTTPException(
            status_code=400,
            detail="Probe export is not available for sweep jobs",
        )

    if node_id is not None:
        node_data = job.results.get(node_id)
        if node_data is None:
            raise HTTPException(
                status_code=404, detail=f"Node '{node_id}' not found in results"
            )
        arr = _probe_to_ndarray(node_data, probe)
        buf = io.BytesIO()
        np.save(buf, arr)
        return Response(
            content=buf.getvalue(),
            media_type="application/octet-stream",
            headers={
                "Content-Disposition": f'attachment; filename="{node_id}_{probe}.npy"'
            },
        )

    # All nodes → zip
    zipped = io.BytesIO()
    with zipfile.ZipFile(zipped, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        for nid, node_data in job.results.items():
            for probe_type in ("spikes", "voltage"):
                raw = node_data.get(probe_type)
                if raw is None:
                    continue
                arr = _probe_to_ndarray(node_data, probe_type)
                buf = io.BytesIO()
                np.save(buf, arr)
                zf.writestr(f"{nid}_{probe_type}.npy", buf.getvalue())
    return Response(
        content=zipped.getvalue(),
        media_type="application/zip",
        headers={
            "Content-Disposition": f'attachment; filename="activity_{job_id}.zip"'
        },
    )


def _probe_to_ndarray(node_data: dict[str, Any], probe: str) -> np.ndarray[Any, Any]:
    """Convert raw probe data from job results into a dense numpy array.

    - ``spikes``: list of spike-time floats → 1-D float32 array shape (n_spikes,)
    - ``voltage``: list of per-timestep neuron voltage lists → 2-D float32 (T, N)
    """
    raw = node_data.get(probe)
    if raw is None:
        return np.empty(0, dtype=np.float32)
    if probe == "spikes":
        return np.asarray(raw, dtype=np.float32).ravel()
    # voltage: list[list[float]]  shape (T, N)
    return np.asarray(raw, dtype=np.float32)
