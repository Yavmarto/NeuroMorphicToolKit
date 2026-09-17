from typing import Any

from fastapi import APIRouter, HTTPException, Request, Response
from pydantic import BaseModel

from app.schemas.benchmarks import BenchmarkJob
from app.schemas.common import JobCancelledResponse, JobQueuedResponse
from app.schemas.results import BenchmarkResult
from app.services.job_manager import job_manager
from app.services.result_store import result_store

router = APIRouter()


class RunBenchmarkRequest(BaseModel):
    """Request schema for running a benchmark.

    Exactly one of network_path or network_content must be provided.
    network_path — server-side file path to a .cnl spec.
    network_content — inline CNL spec content (used by CNL Studio integration).
    """

    benchmark_id: str
    network_path: str | None = None
    network_content: str | None = None
    params: dict[str, Any] | None = None
    seed: int | None = None
    target: str = "simulation"


@router.post("", response_model=JobQueuedResponse)
def run_benchmark(
    request: Request, response: Response, request_body: RunBenchmarkRequest
) -> JobQueuedResponse:
    """Queue a benchmark for execution.

    Returns:
        dict[str, Any]: A dictionary containing the job ID.
    """
    # Slowapi requires 'request' and 'response' arguments by name in the signature.
    _ = (request, response)

    if not request_body.network_path and not request_body.network_content:
        raise HTTPException(
            status_code=422,
            detail="Exactly one of network_path or network_content must be provided.",
        )
    if request_body.network_path and request_body.network_content:
        raise HTTPException(
            status_code=422,
            detail="Provide either network_path or network_content, not both.",
        )

    try:
        job_id = job_manager.submit_job(
            benchmark_id=request_body.benchmark_id,
            network_path=request_body.network_path,
            network_content=request_body.network_content,
            params=request_body.params,
            seed=request_body.seed,
            target=request_body.target,
        )
        return JobQueuedResponse(job_id=job_id)
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e)) from e
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e)) from e


@router.get("/{job_id}", response_model=BenchmarkJob)
def get_job_status(request: Request, response: Response, job_id: str) -> BenchmarkJob:
    """Poll benchmark job status and results.

    Args:
        request (Request): The incoming request used for rate limiting.
        response (Response): The outgoing response used for rate-limit headers.
        job_id (str): The unique ID of the benchmark job.

    Returns:
        BenchmarkJob: The status or results of the benchmark job.

    Raises:
        HTTPException: If the job is not found.
    """
    # Slowapi requires 'request' and 'response' arguments by name in the signature.
    _ = (request, response)
    try:
        return job_manager.get_job_status(job_id)
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e)) from e


@router.get("/{job_id}/result", response_model=BenchmarkResult)
def get_job_result(request: Request, response: Response, job_id: str) -> BenchmarkResult:
    """Get the result of a completed benchmark job.

    Args:
        request (Request): The incoming request used for rate limiting.
        response (Response): The outgoing response used for rate-limit headers.
        job_id (str): The unique ID of the benchmark job.

    Returns:
        BenchmarkResult: The result of the benchmark run.

    Raises:
        HTTPException: If the job is not found, not completed, or result not found.
    """
    # Slowapi requires 'request' and 'response' arguments by name in the signature.
    _ = (request, response)
    try:
        job = job_manager.get_job_status(job_id)
        if (
            job.status == "FAILED"
            and job.error
            and (
                "completely silent" in job.error
                or "fully saturated" in job.error
                or "invalid" in job.error
            )
        ):
            raise HTTPException(status_code=422, detail=job.error)
        if job.status != "COMPLETED":
            raise HTTPException(status_code=400, detail=f"Job status is {job.status}")
        if not job.result_id:
            raise HTTPException(status_code=404, detail="Result ID not found for completed job")

        result = result_store.get_result(job.result_id)
        if not result:
            raise HTTPException(status_code=404, detail="Result not found in store")
        return result
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e)) from e


@router.delete("/{job_id}", response_model=JobCancelledResponse)
def cancel_job(request: Request, response: Response, job_id: str) -> JobCancelledResponse:
    """Cancel a benchmark job.

    Args:
        request (Request): The incoming request used for rate limiting.
        response (Response): The outgoing response used for rate-limit headers.
        job_id (str): The unique ID of the benchmark job.

    Returns:
        dict[str, bool]: Success indicator.
    """
    # Slowapi requires 'request' and 'response' arguments by name in the signature.
    _ = (request, response)
    success = job_manager.cancel_job(job_id)
    return JobCancelledResponse(success=success)
