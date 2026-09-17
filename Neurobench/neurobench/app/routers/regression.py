from fastapi import APIRouter, Request, Response

from app.schemas.results import TrendAnalysisResult
from app.services.regression_service import regression_service

router = APIRouter()


@router.get("/{benchmark_id}/trends", response_model=TrendAnalysisResult)
def get_trends(request: Request, response: Response, benchmark_id: str) -> TrendAnalysisResult:
    """Get historical trend analysis for a benchmark.

    Args:
        request (Request): The incoming request used for rate limiting.
        response (Response): The outgoing response used for rate-limit headers.
        benchmark_id (str): The ID of the benchmark.

    Returns:
        TrendAnalysisResult: Historical trend data.
    """
    # Slowapi requires 'request' and 'response' arguments by name in the signature.
    _ = (request, response)
    return regression_service.get_trends(benchmark_id)
