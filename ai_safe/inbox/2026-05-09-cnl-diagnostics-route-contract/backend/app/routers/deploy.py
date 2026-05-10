"""
Deploy route - validates and deploys CNL specifications.
"""

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from ..services.neurocnl_bridge import parse_spec_text
from ..utils.cnl_errors import (
    build_parse_failure_detail,
    build_validation_failure_detail,
    build_backend_failure_detail,
)


router = APIRouter()


class DeployRequest(BaseModel):
    spec: str
    target: str


class DeployResponse(BaseModel):
    deployment_id: str
    status: str


@router.post("/deploy", response_model=DeployResponse)
async def deploy(request: DeployRequest) -> DeployResponse:
    """
    Deploy CNL specification to target environment.
    
    Raises:
        HTTPException: 422 with structured detail on parse, validation, or deployment failure
    """
    # Parse the specification
    parse_results = parse_spec_text(request.spec)
    
    # Check for parse failures and preserve structured diagnostics
    if any(not r["valid"] for r in parse_results):
        detail = build_parse_failure_detail(parse_results)
        raise HTTPException(status_code=422, detail=detail)
    
    # Extract parsed structures
    parsed_sentences = [r["parsed"] for r in parse_results if r["valid"]]
    
    # Validate for deployment
    validation_errors = validate_for_deployment(parsed_sentences, request.target)
    if validation_errors:
        detail = build_validation_failure_detail(validation_errors)
        raise HTTPException(status_code=422, detail=detail)
    
    # Check deployment target
    if not is_deployment_target_available(request.target):
        detail = build_backend_failure_detail(
            f"Deployment target not available: {request.target}",
            error_type="target_unavailable"
        )
        raise HTTPException(status_code=422, detail=detail)
    
    # Perform deployment
    try:
        deployment_id = perform_deployment(parsed_sentences, request.target)
    except DeploymentError as exc:
        detail = build_backend_failure_detail(str(exc), error_type="deployment_failed")
        raise HTTPException(status_code=422, detail=detail)
    
    return DeployResponse(deployment_id=deployment_id, status="deployed")


class DeploymentError(Exception):
    """Raised when deployment operation fails."""
    pass


def validate_for_deployment(parsed_sentences: list[dict], target: str) -> list[dict]:
    """
    Validate parsed CNL for deployment readiness.
    
    Returns list of structured validation error details, empty if valid.
    """
    raise NotImplementedError("validate_for_deployment must be implemented")


def is_deployment_target_available(target: str) -> bool:
    """Check if deployment target is available."""
    raise NotImplementedError("is_deployment_target_available must be implemented")


def perform_deployment(parsed_sentences: list[dict], target: str) -> str:
    """Perform the actual deployment and return deployment ID."""
    raise NotImplementedError("perform_deployment must be implemented")
