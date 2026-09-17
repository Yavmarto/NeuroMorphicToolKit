"""Router for parameter sweep simulations."""

from fastapi import APIRouter, BackgroundTasks, HTTPException, Request, Response

from neurosim.contracts.design_contracts import SimulationStatus

from ..limiter import rate_limit
from ..schemas.sweep import SweepRequest, SweepResponse
from ..services.job_store import job_store
from ..services.sweep_runner import (
    assess_sweep_support,
    run_sweep_sync,
    validate_parameter_path,
)

router = APIRouter(prefix="/api/neurosim", tags=["sweep"])


@router.post("/sweep", response_model=SweepResponse)
@rate_limit("20/minute")
def sweep(
    request: Request,
    response: Response,
    payload: SweepRequest,
    background_tasks: BackgroundTasks,
) -> SweepResponse:
    """Run a parameter sweep batch of simulations.

    Args:
        request (Request): The FastAPI request object.
        response (Response): The FastAPI response used by SlowAPI for rate-limit headers.
        payload (SweepRequest): The sweep request including parameter ranges.
        background_tasks (BackgroundTasks): FastAPI background tasks.

    Returns:
        SweepResponse: Initial job info.
    """
    try:
        validate_parameter_path(payload.graph, payload.parameter_path)
    except ValueError as exc:
        raise HTTPException(
            status_code=422,
            detail={
                "error": "invalid_sweep_path",
                "message": str(exc),
                "hint": (
                    "Use 'nodes.<node_id>.<param>' or 'edges.<edge_id>.<param>' with a known "
                    "numeric parameter."
                ),
            },
        ) from exc

    backend_support, generator_fidelity = assess_sweep_support(payload)
    if backend_support.verdict == "unsupported":
        return SweepResponse(
            status=SimulationStatus.FAILED,
            error="Sweep is unsupported for the selected backend.",
            parameter_path=payload.parameter_path,
            steps=None,
            backend_support=backend_support,
            generator_fidelity=generator_fidelity,
        )

    job_id = job_store.create_job("sweep")
    job = job_store.get_job(job_id)
    if job is not None:
        job.backend_support = backend_support
        job.generator_fidelity = generator_fidelity

    # Pass pre-computed support so run_sweep does not re-assess all steps a second time.
    background_tasks.add_task(
        run_sweep_sync,
        payload,
        job_id,
        backend_support,
        generator_fidelity,
    )

    return SweepResponse(
        job_id=job_id,
        status=job.status if job is not None else SimulationStatus.QUEUED,
        parameter_path=payload.parameter_path,
        steps=None,
        backend_support=backend_support,
        generator_fidelity=generator_fidelity,
    )


@router.get("/sweep/{job_id}", response_model=SweepResponse)
@rate_limit("20/minute")
def get_sweep_status(request: Request, response: Response, job_id: str) -> SweepResponse:
    """Get the status and results of a sweep job."""
    job = job_store.get_job(job_id)
    if not job or job.type != "sweep":
        raise HTTPException(status_code=404, detail="Sweep job not found")

    return SweepResponse(
        job_id=job.job_id,
        status=job.status,
        error=job.error,
        parameter_path=getattr(job, "parameter_path", ""),
        steps=job.results,
        backend_support=getattr(job, "backend_support", None),
        generator_fidelity=getattr(job, "generator_fidelity", None),
    )
