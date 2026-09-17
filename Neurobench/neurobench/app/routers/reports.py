from fastapi import APIRouter

from app.schemas.reports import ReportGenerationResult, ReportRequest
from app.services.report_generator import report_generator

router = APIRouter()


@router.post("", response_model=ReportGenerationResult)
def generate_report(request: ReportRequest | None = None) -> ReportGenerationResult:
    """Generate a benchmark report (PDF/HTML/JSON).

    Returns:
        ReportGenerationResult: The response detailing the generated report.
    """
    if request is None:
        return report_generator.generate_report()
    return report_generator.generate_report(
        format=request.format,
        summary=request.summary,
        methodology=request.methodology,
        results=request.results,
        recommendations=request.recommendations,
        result_id=request.result_id,
        new_baseline=request.new_baseline,
    )
