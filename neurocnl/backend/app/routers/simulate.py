"""POST /api/simulate — simulation is unsupported on the NIR-only surface."""

from fastapi import APIRouter, HTTPException, Request

from backend.app.middleware.rate_limit import limiter
from backend.app.schemas.simulate import SimulateRequest
from backend.app.utils.cnl_errors import (
    build_backend_failure_detail,
    build_validation_failure_detail,
)

router = APIRouter()

MAX_DURATION = 10.0


@router.post(
    "/simulate",
    status_code=410,
    responses={
        410: {
            "description": "Simulation is deprecated on the supported NIR-only NeuroCNL surface."
        },
        422: {"description": "Simulation request validation failed."},
    },
)
@limiter.limit("10/minute")
async def simulate_network(request: Request, body: SimulateRequest) -> None:
    if body.duration > MAX_DURATION:
        raise HTTPException(
            status_code=422,
            detail=build_validation_failure_detail(
                f"Duration must be at most {MAX_DURATION}s.",
                code="duration_too_large",
            ),
        )

    raise HTTPException(
        status_code=410,
        detail=build_backend_failure_detail(
            "nir_simulation_unsupported",
            "Simulation is no longer supported on the NIR-only NeuroCNL surface.",
            source="simulate",
            hint=(
                "Use /api/generate to inspect the compiled topology or /api/export with "
                "format='nir' to download the NIR artifact."
            ),
            examples=[
                "POST /api/generate",
                'POST /api/export {"format": "nir"}',
            ],
        ),
    )
