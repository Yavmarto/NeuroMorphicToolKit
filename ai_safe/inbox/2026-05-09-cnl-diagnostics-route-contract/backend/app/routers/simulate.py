"""
Simulate route - simulates CNL specifications.
"""

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from ..services.neurocnl_bridge import parse_spec_text
from ..utils.cnl_errors import (
    build_parse_failure_detail,
    build_validation_failure_detail,
    build_lowering_failure_detail,
)


router = APIRouter()


class SimulateRequest(BaseModel):
    spec: str
    parameters: dict


class SimulateResponse(BaseModel):
    results: dict


@router.post("/simulate", response_model=SimulateResponse)
async def simulate(request: SimulateRequest) -> SimulateResponse:
    """
    Simulate CNL specification with given parameters.
    
    Raises:
        HTTPException: 422 with structured detail on parse, validation, or simulation failure
    """
    # Parse the specification
    parse_results = parse_spec_text(request.spec)
    
    # Check for parse failures and preserve structured diagnostics
    if any(not r["valid"] for r in parse_results):
        detail = build_parse_failure_detail(parse_results)
        raise HTTPException(status_code=422, detail=detail)
    
    # Extract parsed structures
    parsed_sentences = [r["parsed"] for r in parse_results if r["valid"]]
    
    # Validate for simulation
    validation_errors = validate_for_simulation(parsed_sentences, request.parameters)
    if validation_errors:
        detail = build_validation_failure_detail(validation_errors)
        raise HTTPException(status_code=422, detail=detail)
    
    # Lower to simulation model
    try:
        simulation_model = lower_to_simulation_model(parsed_sentences)
    except LoweringError as exc:
        detail = build_lowering_failure_detail(exc)
        raise HTTPException(status_code=422, detail=detail)
    
    # Run simulation
    try:
        results = run_simulation(simulation_model, request.parameters)
    except SimulationError as exc:
        # Simulation runtime errors are backend failures, not lowering failures
        from ..utils.cnl_errors import build_backend_failure_detail
        detail = build_backend_failure_detail(str(exc), error_type="simulation_failed")
        raise HTTPException(status_code=422, detail=detail)
    
    return SimulateResponse(results=results)


class LoweringError(Exception):
    """Raised when lowering CNL to simulation model fails."""
    pass


class SimulationError(Exception):
    """Raised when simulation execution fails."""
    pass


def validate_for_simulation(parsed_sentences: list[dict], parameters: dict) -> list[dict]:
    """
    Validate parsed CNL for simulation readiness.
    
    Returns list of structured validation error details, empty if valid.
    """
    raise NotImplementedError("validate_for_simulation must be implemented")


def lower_to_simulation_model(parsed_sentences: list[dict]) -> dict:
    """Lower parsed CNL to simulation model."""
    raise NotImplementedError("lower_to_simulation_model must be implemented")


def run_simulation(simulation_model: dict, parameters: dict) -> dict:
    """Run the simulation and return results."""
    raise NotImplementedError("run_simulation must be implemented")
