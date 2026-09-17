"""POST /api/validate — validate a CNL spec against L1+L2 invariants."""

import logging

from fastapi import APIRouter, HTTPException

from backend.app.schemas.common import BackendSupport, ErrorDetail
from backend.app.schemas.validate import (
    InvariantResult,
    Layer1Result,
    Layer2Result,
    ValidateRequest,
    ValidateResponse,
)
from backend.app.services.neurocnl_bridge import validate_spec

router = APIRouter()

logger = logging.getLogger(__name__)


@router.post("/validate", response_model=ValidateResponse)
def validate_cnl(request: ValidateRequest) -> ValidateResponse:
    """Validate a spec, and never answer with a bare 500.

    Validation is the step users reach for when something is already wrong, so
    an unhandled exception here is doubly unhelpful: the Validation panel shows
    only ``ApiException(500): {"detail":"Internal Server Error"}``, which names
    neither the spec nor the check that broke. Any unexpected failure is turned
    into a 422 carrying the exception text.
    """
    try:
        return _validate_cnl_inner(request)
    except HTTPException:
        raise
    except Exception as exc:
        logger.exception("Unhandled error validating spec")
        raise HTTPException(
            status_code=422,
            detail=(
                f"Validation could not be completed: {type(exc).__name__}: {exc}. "
                "This is a bug in the validator, not in your spec — please report it."
            ),
        ) from exc


def _validate_cnl_inner(request: ValidateRequest) -> ValidateResponse:
    result = validate_spec(request.spec, request.params, backend=request.backend)

    l1 = result["layer1"]
    layer1 = Layer1Result(
        overall=l1["overall"],
        passed=[InvariantResult(**p) for p in l1["passed"]],
        failed=[InvariantResult(**f) for f in l1["failed"]],
        warnings=[InvariantResult(**w) for w in l1.get("warnings", [])],
    )
    l2 = result["layer2"]
    layer2 = Layer2Result(
        overall=l2["overall"],
        checks_passed=l2["checks_passed"],
        checks_failed=[ErrorDetail(**failure) for failure in l2["checks_failed"]],
        neurons_found=l2["neurons_found"],
    )
    return ValidateResponse(
        layer1=layer1,
        layer2=layer2,
        overall=result["overall"],
        backend_support=(
            BackendSupport(
                backend=result["planner"].backend,
                verdict=result["planner"].verdict,
                supported_concepts=result["planner"].supported_concepts,
                approximated_concepts=result["planner"].approximated_concepts,
                unsupported_concepts=result["planner"].unsupported_concepts,
                warnings=result["planner"].warnings,
            )
            if result.get("planner") is not None
            else BackendSupport(
                backend=request.backend,
                verdict="unsupported",
                warnings=[
                    "Spec could not be analyzed for backend support; deploy path is blocked."
                ],
            )
        ),
    )
