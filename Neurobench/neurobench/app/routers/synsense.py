from typing import Any

from fastapi import APIRouter, HTTPException, Request, Response
from pydantic import BaseModel

from app.runners.synsense_runner import SynSenseBenchmarkRunner
from app.schemas.benchmarks import BenchmarkJob, JobStatus
from app.schemas.common import JobQueuedResponse
from app.schemas.results import BenchmarkResult

router = APIRouter()
synsense_runner = SynSenseBenchmarkRunner()


class SynSenseRunRequest(BaseModel):
    """Request schema for running a SynSense benchmark."""

    benchmark_id: str
    network_path: str
    target: str = "simulation"
    params: dict[str, Any] | None = None
    seed: int | None = None


# Mock job manager for synchronous execution fallback
_mock_jobs: dict[str, BenchmarkResult] = {}


@router.post("/run", response_model=JobQueuedResponse)
def run_benchmark(
    request: Request, response: Response, request_body: SynSenseRunRequest
) -> JobQueuedResponse:
    """Queue a SynSense benchmark for execution.

    Args:
        request (Request): The incoming request used for rate limiting.
        response (Response): The outgoing response used for rate limiting.
        request_body (SynSenseRunRequest): The benchmark request parameters.

    Returns:
        dict[str, str]: A dictionary containing the job ID.
    """
    _ = (request, response)

    try:
        # Run synchronously for now, in a full system this would be queued
        result = synsense_runner.run_benchmark(
            benchmark_id=request_body.benchmark_id,
            network_path=request_body.network_path,
            params=request_body.params,
            seed=request_body.seed,
            target=request_body.target,
        )

        job_id = f"job-{result.id}"
        _mock_jobs[job_id] = result
        return JobQueuedResponse(job_id=job_id)

    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e)) from e
    except RuntimeError as e:
        raise HTTPException(status_code=500, detail=str(e)) from e


@router.get("/results/{run_id}", response_model=BenchmarkJob)
def get_job_status(request: Request, response: Response, run_id: str) -> BenchmarkJob:
    """Poll benchmark job status and retrieve the result ID.

    Args:
        request (Request): The incoming request used for rate limiting.
        response (Response): The outgoing response used for rate limiting.
        run_id (str): The unique ID of the benchmark job.

    Returns:
        BenchmarkJob: The status of the benchmark job containing the result ID if completed.
    """
    _ = (request, response)

    if run_id not in _mock_jobs:
        raise HTTPException(status_code=404, detail="Job not found")

    result = _mock_jobs[run_id]

    # Return a BenchmarkJob object containing the ID to fetch the result via
    # the generic endpoints if required.

    return BenchmarkJob(
        id=run_id,
        benchmark_id=result.benchmark_id,
        network_path=f"synsense-{result.network_spec_hash}",
        status=JobStatus.COMPLETED,
        result_id=result.id,
        created_at=result.timestamp,
        updated_at=result.timestamp,
    )


@router.get("/results/{run_id}/data", response_model=BenchmarkResult)
def get_job_result(request: Request, response: Response, run_id: str) -> BenchmarkResult:
    """Poll benchmark job and get result data.

    Args:
        request (Request): The incoming request used for rate limiting.
        response (Response): The outgoing response used for rate limiting.
        run_id (str): The unique ID of the benchmark job.

    Returns:
        BenchmarkResult: The result of the run.
    """
    _ = (request, response)

    if run_id not in _mock_jobs:
        raise HTTPException(status_code=404, detail="Job not found")

    return _mock_jobs[run_id]
