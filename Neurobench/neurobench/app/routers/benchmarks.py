from fastapi import APIRouter, HTTPException, Request, Response

from app.schemas.benchmarks import BenchmarkDefinition
from app.services.benchmark_loader import benchmark_loader

router = APIRouter()


@router.get("", response_model=list[BenchmarkDefinition])
def list_benchmarks(request: Request, response: Response) -> list[BenchmarkDefinition]:
    """List all available benchmarks (built-in + custom).

    Returns:
        list[BenchmarkDefinition]: A list of all benchmark definitions.
    """
    # Slowapi requires 'request' and 'response' arguments by name in the signature.
    _ = (request, response)
    return benchmark_loader.get_all()


@router.get("/{benchmark_id}", response_model=BenchmarkDefinition)
def get_benchmark(request: Request, response: Response, benchmark_id: str) -> BenchmarkDefinition:
    """Get a specific benchmark definition and metadata.

    Args:
        request (Request): The incoming request used for rate limiting.
        response (Response): The outgoing response used for rate-limit headers.
        benchmark_id (str): The unique ID of the benchmark.

    Returns:
        BenchmarkDefinition: The requested benchmark definition.

    Raises:
        HTTPException: If the benchmark is not found.
    """
    # Slowapi requires 'request' and 'response' arguments by name in the signature.
    _ = (request, response)
    benchmark = benchmark_loader.get(benchmark_id)
    if benchmark is None:
        raise HTTPException(status_code=404, detail=f"Benchmark '{benchmark_id}' not found")
    return benchmark


@router.post("", response_model=BenchmarkDefinition)
def create_benchmark(
    request: Request, response: Response, _benchmark: BenchmarkDefinition
) -> BenchmarkDefinition:
    """Create a custom benchmark definition.

    Args:
        request (Request): The incoming request used for rate limiting.
        response (Response): The outgoing response used for rate-limit headers.
        _benchmark (BenchmarkDefinition): The benchmark definition to create.

    Returns:
        BenchmarkDefinition: The created benchmark definition.

    Raises:
        HTTPException: If the benchmark ID already exists.
    """
    # Slowapi requires 'request' and 'response' arguments by name in the signature.
    _ = (request, response)
    try:
        benchmark_loader.add_benchmark(_benchmark)
        return _benchmark
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e)) from e
