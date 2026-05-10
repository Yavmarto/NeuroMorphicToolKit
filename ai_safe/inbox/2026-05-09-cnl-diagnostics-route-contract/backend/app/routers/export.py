"""
Export route - exports CNL specifications to various formats.
"""

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from ..services.neurocnl_bridge import parse_spec_text
from ..utils.cnl_errors import build_parse_failure_detail, build_backend_failure_detail


router = APIRouter()


class ExportRequest(BaseModel):
    spec: str
    format: str


class ExportResponse(BaseModel):
    exported: str


@router.post("/export", response_model=ExportResponse)
async def export(request: ExportRequest) -> ExportResponse:
    """
    Export CNL specification to requested format.
    
    Raises:
        HTTPException: 422 with structured detail on parse or export failure
    """
    # Parse the specification
    parse_results = parse_spec_text(request.spec)
    
    # Check for parse failures and preserve structured diagnostics
    if any(not r["valid"] for r in parse_results):
        detail = build_parse_failure_detail(parse_results)
        raise HTTPException(status_code=422, detail=detail)
    
    # Extract parsed structures
    parsed_sentences = [r["parsed"] for r in parse_results if r["valid"]]
    
    # Validate export format
    supported_formats = ["json", "yaml", "xml"]
    if request.format not in supported_formats:
        detail = build_backend_failure_detail(
            f"Unsupported export format: {request.format}. Supported: {', '.join(supported_formats)}",
            error_type="unsupported_format"
        )
        raise HTTPException(status_code=422, detail=detail)
    
    # Perform export
    try:
        exported = export_to_format(parsed_sentences, request.format)
    except ExportError as exc:
        detail = build_backend_failure_detail(str(exc), error_type="export_failed")
        raise HTTPException(status_code=422, detail=detail)
    
    return ExportResponse(exported=exported)


class ExportError(Exception):
    """Raised when export operation fails."""
    pass


def export_to_format(parsed_sentences: list[dict], format: str) -> str:
    """
    Export parsed CNL to requested format.
    
    This is a stub - real implementation would perform the export.
    """
    raise NotImplementedError("export_to_format must be implemented")
