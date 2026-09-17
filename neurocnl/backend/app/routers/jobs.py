"""GET /api/jobs/{job_id} — poll for background job results.
GET /api/jobs — list background jobs.
"""

from fastapi import APIRouter, HTTPException, Query
from pydantic import TypeAdapter

from backend.app.schemas.jobs import JobState, PaginatedJobsResponse
from backend.app.services.job_store import job_store

router = APIRouter()


@router.get("/jobs", response_model=PaginatedJobsResponse)
async def list_jobs(
    page: int = Query(1, ge=1),
    size: int = Query(20, ge=1, le=100),
) -> PaginatedJobsResponse:
    """List background jobs with pagination."""
    data = await job_store.list_jobs(page, size)
    return PaginatedJobsResponse(**data)


@router.get("/jobs/{job_id}", response_model=JobState)
async def get_job(job_id: str) -> JobState:
    """Poll for the status of a specific job."""
    job = await job_store.get(job_id)
    if job is None:
        raise HTTPException(status_code=404, detail=f"Job {job_id} not found")
    return TypeAdapter(JobState).validate_python(job)
