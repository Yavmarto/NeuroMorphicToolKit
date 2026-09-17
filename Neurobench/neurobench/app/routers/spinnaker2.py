from typing import Any

from fastapi import APIRouter, HTTPException, Request, Response
from pydantic import BaseModel

from app.runners.spinnaker2_runner import spinnaker2_runner
from app.schemas.results import BenchmarkResult
from app.services.result_store import result_store

router = APIRouter()


class RunSpiNNaker2BenchmarkRequest(BaseModel):
    """Request schema for running a benchmark on SpiNNaker2."""

    benchmark_id: str
    network_path: str
    params: dict[str, Any] | None = None
    seed: int | None = None


@router.post("/run", response_model=BenchmarkResult)
def run_benchmark(
    request: Request, response: Response, request_body: RunSpiNNaker2BenchmarkRequest
) -> BenchmarkResult:
    """Execute a benchmark directly on SpiNNaker2 and return the result.

    Args:
        request (Request): The incoming request used for rate limiting.
        response (Response): The outgoing response used for rate-limit headers.
        request_body (RunSpiNNaker2BenchmarkRequest): The request payload.

    Returns:
        BenchmarkResult: The result of the benchmark run.
    """
    _ = (request, response)
    try:
        result = spinnaker2_runner.run_benchmark(
            benchmark_id=request_body.benchmark_id,
            network_path=request_body.network_path,
            params=request_body.params,
            seed=request_body.seed,
        )
        return result
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e)) from e
    except ImportError as e:
        raise HTTPException(status_code=501, detail=str(e)) from e
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e)) from e


@router.get("/results/{run_id}", response_model=BenchmarkResult)
def get_job_result(request: Request, response: Response, run_id: str) -> BenchmarkResult:
    """Get the result of a completed SpiNNaker2 benchmark job.

    Args:
        request (Request): The incoming request used for rate limiting.
        response (Response): The outgoing response used for rate-limit headers.
        run_id (str): The unique ID of the benchmark run.

    Returns:
        BenchmarkResult: The result of the benchmark run.

    Raises:
        HTTPException: If the result is not found.
    """
    _ = (request, response)
    result = result_store.get_result(run_id)
    if not result:
        raise HTTPException(status_code=404, detail="Result not found in store")
    return result
