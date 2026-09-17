"""POST /api/prosthetic/sleep — offline PES sleep training.

This legacy route delegates to the generic training system via
training_service.submit_training_job_forced() so that the
sleep_pes adapter handles execution (including fallback when
neurodreamhand is unavailable).
"""

from fastapi import APIRouter, Request
from fastapi.responses import JSONResponse

from backend.app.middleware.rate_limit import limiter
from backend.app.middleware.request_id import get_request_id
from backend.app.schemas.jobs import JobQueued, JobState
from backend.app.schemas.prosthetic import SleepTrainRequest
from backend.app.services import training_service

router = APIRouter()


@router.post("/sleep", response_model=JobState, status_code=202)
@limiter.limit("5/minute")
async def prosthetic_sleep(request: Request, body: SleepTrainRequest) -> JSONResponse:
    payload = body.model_dump()
    job_id = await training_service.submit_training_job_forced(
        backend_name="sleep_pes",
        training_mode="offline_sleep",
        payload=payload,
        request_id=get_request_id(),
    )
    return JSONResponse(
        status_code=202,
        content=JobQueued(job_id=job_id).model_dump(),
    )
