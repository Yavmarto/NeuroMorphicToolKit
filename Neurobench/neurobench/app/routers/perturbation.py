from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from app.schemas.robustness import PerturbationCurve
from app.services.perturbation_sweeper import perturbation_sweeper

router = APIRouter()


class SweepPerturbationRequest(BaseModel):
    """Request schema for input perturbation sweep."""

    cnl_spec_path: str
    benchmark_id: str
    dataset_path: str
    noise_type: str = "gaussian"
    noise_levels: list[float] | None = None


@router.post("/sweep", response_model=PerturbationCurve)
def sweep_perturbation(request_body: SweepPerturbationRequest) -> PerturbationCurve:
    """Run input perturbation sweep.

    Returns:
        PerturbationCurve: The results of the input perturbation sweep.
    """
    try:
        return perturbation_sweeper.sweep_perturbation(
            cnl_spec_path=request_body.cnl_spec_path,
            benchmark_id=request_body.benchmark_id,
            dataset_path=request_body.dataset_path,
            noise_type=request_body.noise_type,
            noise_levels=request_body.noise_levels,
        )
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e)) from e
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e)) from e
