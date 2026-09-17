from typing import Any

from fastapi import APIRouter, HTTPException, Request, Response
from pydantic import BaseModel

from app.runners.pynq_runner import PYNQBenchmarkRunner
from app.schemas.common import PowerTraceResponse
from app.schemas.results import BenchmarkResult

router = APIRouter()
runner = PYNQBenchmarkRunner()


class PYNQRunRequest(BaseModel):
    """Request schema for running a PYNQ benchmark."""

    benchmark_id: str
    network_path: str
    params: dict[str, Any] | None = None
    seed: int | None = None
    target: str = "pynq"


@router.post("/run", response_model=BenchmarkResult)
def run_pynq_benchmark(
    request: Request, response: Response, request_body: PYNQRunRequest
) -> BenchmarkResult:
    """Submit a benchmark job to a connected PYNQ Z2 or simulation fallback."""
    _ = (request, response)
    try:
        result = runner.run_benchmark(
            benchmark_id=request_body.benchmark_id,
            network_path=request_body.network_path,
            params=request_body.params,
            seed=request_body.seed,
            target=request_body.target,
        )
        return result
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e)) from e


@router.get("/results/{run_id}", response_model=BenchmarkResult)
def get_pynq_result(request: Request, response: Response, run_id: str) -> BenchmarkResult:
    """Retrieves standard benchmark metrics for a completed PYNQ run."""
    _ = (request, response)
    # In a full implementation, this would retrieve from a result_store using run_id
    # For now, since the actual integration is synchronous and stateless in the runner,
    # we return a placeholder error or we'd integrate it via JobManager in the future.
    raise HTTPException(status_code=404, detail="Result retrieval by run_id not yet implemented")


@router.get("/power_trace/{run_id}", response_model=PowerTraceResponse)
def get_power_trace(request: Request, response: Response, run_id: str) -> PowerTraceResponse:
    """Retrieves the raw power rail time-series data for visualization."""
    _ = (request, response)
    # Returns a mock trace
    return PowerTraceResponse(
        run_id=run_id,
        timestamps=[0.0, 0.1, 0.2, 0.3],
        vcc_int=[1.0, 1.01, 0.99, 1.0],
        vcc_aux=[1.8, 1.8, 1.8, 1.8],
        ps=[3.3, 3.2, 3.4, 3.3],
    )
