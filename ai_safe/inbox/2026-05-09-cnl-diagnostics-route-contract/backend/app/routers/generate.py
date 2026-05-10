"""
Generate route - converts CNL to executable artifacts.
"""

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from ..services.neurocnl_bridge import parse_spec_text
from ..utils.cnl_errors import build_parse_failure_detail, build_lowering_failure_detail


router = APIRouter()


class GenerateRequest(BaseModel):
    spec: str


class GenerateResponse(BaseModel):
    artifact: str


@router.post("/generate", response_model=GenerateResponse)
async def generate(request: GenerateRequest) -> GenerateResponse:
    """
    Generate executable artifact from CNL specification.
    
    Raises:
        HTTPException: 422 with structured detail on parse or lowering failure
    """
    # Parse the specification
    parse_results = parse_spec_text(request.spec)
    
    # Check for parse failures and preserve structured diagnostics
    if any(not r["valid"] for r in parse_results):
        detail = build_parse_failure_detail(parse_results)
        raise HTTPException(status_code=422, detail=detail)
    
    # Extract parsed structures
    parsed_sentences = [r["parsed"] for r in parse_results if r["valid"]]
    
    # Attempt lowering
    try:
        artifact = lower_to_artifact(parsed_sentences)
    except LoweringError as exc:
        detail = build_lowering_failure_detail(exc)
        raise HTTPException(status_code=422, detail=detail)
    
    return GenerateResponse(artifact=artifact)


class LoweringError(Exception):
    """Raised when lowering CNL to executable artifact fails."""
    pass


def lower_to_artifact(parsed_sentences: list[dict]) -> str:
    """
    Lower parsed CNL sentences to executable artifact.
    
    This is a stub - real implementation would perform the lowering.
    """
    raise NotImplementedError("lower_to_artifact must be implemented")
