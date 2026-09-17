from typing import Any

from fastapi import APIRouter, HTTPException, Request, Response
from pydantic import BaseModel

from app.runners.snn_mlir_runner import SnnMlirBenchmarkRunner
from app.schemas.results import BenchmarkResult

router = APIRouter()
runner = SnnMlirBenchmarkRunner()


class SnnMlirRunRequest(BaseModel):
    """Request schema for running an snn-mlir fast-simulation benchmark."""

    benchmark_id: str
    network_path: str
    params: dict[str, Any] | None = None
    seed: int | None = None


@router.post("/run", response_model=BenchmarkResult)
def run_snn_mlir_benchmark(
    request: Request, response: Response, request_body: SnnMlirRunRequest
) -> BenchmarkResult:
    """Compiles a .nir graph via the snn-mlir-compiler worker and benchmarks the native binary."""
    _ = (request, response)
    try:
        return runner.run_benchmark(
            benchmark_id=request_body.benchmark_id,
            network_path=request_body.network_path,
            params=request_body.params,
            seed=request_body.seed,
        )
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e)) from e
    except RuntimeError as e:
        raise HTTPException(status_code=502, detail=str(e)) from e
