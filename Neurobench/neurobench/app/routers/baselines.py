from fastapi import APIRouter, Request, Response

from app.schemas.results import BenchmarkResult
from app.services.result_store import result_store

router = APIRouter()


@router.get("", response_model=list[BenchmarkResult])
def list_baselines(request: Request, response: Response) -> list[BenchmarkResult]:
    """List all saved baselines with their full result data.

    Returns:
        list[BenchmarkResult]: All baseline results stored in the database.
    """
    # Slowapi requires 'request' and 'response' arguments by name in the signature.
    # We use them here to satisfy both slowapi and the ARG001 linter.
    _ = (request, response)
    return result_store.get_all_baselines()


@router.post("", response_model=BenchmarkResult)
def save_baseline(result: BenchmarkResult) -> BenchmarkResult:
    """Save a benchmark result as a baseline.

    Args:
        result (BenchmarkResult): The benchmark result to save.

    Returns:
        BenchmarkResult: The saved baseline result.
    """
    result_store.save_baseline(result)
    return result
