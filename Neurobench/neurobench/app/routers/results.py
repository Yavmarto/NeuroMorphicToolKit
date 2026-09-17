from fastapi import APIRouter, HTTPException, Request, Response

from app.schemas.results import BenchmarkResult
from app.services.result_store import result_store

router = APIRouter()


@router.get("", response_model=list[BenchmarkResult])
def list_results(request: Request, response: Response) -> list[BenchmarkResult]:
    """List all benchmark results.

    Returns:
        list[BenchmarkResult]: A list of all benchmark results.
    """
    # Slowapi requires 'request' and 'response' arguments by name in the signature.
    _ = (request, response)
    return result_store.get_all_results()


@router.get("/{result_id}", response_model=BenchmarkResult)
def get_result(request: Request, response: Response, result_id: str) -> BenchmarkResult:
    """Get a specific benchmark result.

    Args:
        request (Request): The incoming request used for rate limiting.
        response (Response): The outgoing response used for rate-limit headers.
        result_id (str): The unique ID of the benchmark result.

    Returns:
        BenchmarkResult: The requested benchmark result.

    Raises:
        HTTPException: If the result is not found.
    """
    # Slowapi requires 'request' and 'response' arguments by name in the signature.
    _ = (request, response)
    result = result_store.get_result(result_id)
    if result is None:
        raise HTTPException(status_code=404, detail=f"Result '{result_id}' not found")
    return result
