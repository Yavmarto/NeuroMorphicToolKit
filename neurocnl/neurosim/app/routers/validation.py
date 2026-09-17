"""Router for graph validation against Layer 1 invariants."""

from fastapi import APIRouter, Request, Response

from neurosim.contracts.design_contracts import CanvasGraph, ValidationResult

from ..limiter import rate_limit
from ..services.validation_service import validate_graph

router = APIRouter(prefix="/api/neurosim", tags=["validation"])


@router.post("/validate", response_model=ValidationResult)
@rate_limit("60/minute")
def validate_canvas(request: Request, response: Response, graph: CanvasGraph) -> ValidationResult:
    """Validate a canvas graph against Layer 1 invariants.

    Args:
        request (Request): The incoming request object.
        response (Response): The FastAPI response used by SlowAPI for rate-limit headers.
        graph (CanvasGraph): The graph to validate.

    Returns:
        ValidationResult: The result of the validation.
    """
    return validate_graph(graph)
