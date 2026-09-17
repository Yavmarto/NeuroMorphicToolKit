"""POST /api/prosthetic/simulate — run MuJoCo + Nengo co-simulation drop test."""

from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import JSONResponse

from backend.app.middleware.rate_limit import limiter
from backend.app.middleware.request_id import get_request_id
from backend.app.schemas.jobs import JobQueued, JobState
from backend.app.schemas.prosthetic import ProstheticSimRequest
from backend.app.services.job_store import job_store
from backend.app.services.prosthetic_runner import run_drop_test

# noqa: E402 — safe now (guarded imports)
from neurocnl.runtime_dependencies import ensure_runtime_dependency

router = APIRouter()

MAX_DURATION = 10.0


@router.post("/simulate", response_model=JobState, status_code=202)
@limiter.limit("10/minute")
async def prosthetic_simulate(request: Request, body: ProstheticSimRequest) -> JSONResponse:
    if body.duration > MAX_DURATION:
        raise HTTPException(
            status_code=422,
            detail=f"Duration must be at most {MAX_DURATION}s.",
        )

    if not ensure_runtime_dependency("mujoco"):
        raise HTTPException(
            status_code=503,
            detail=(
                "MuJoCo is not installed and automatic installation failed. "
                "Install with: pip install mujoco"
            ),
        )

    # All simulations run as background jobs
    job_id = await job_store.submit(run_drop_test, body, request_id=get_request_id())
    return JSONResponse(
        status_code=202,
        content=JobQueued(job_id=job_id).model_dump(),
    )
