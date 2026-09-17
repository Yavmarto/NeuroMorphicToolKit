from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from app.schemas.robustness import RobustnessCurve
from app.services.fault_sweeper import fault_sweeper

router = APIRouter()


class SweepFaultsRequest(BaseModel):
    """Request schema for fault injection sweep."""

    cnl_spec_path: str
    benchmark_id: str
    fault_type: str = "dead_neuron"
    fault_rates: list[float] | None = None


@router.post("/sweep", response_model=RobustnessCurve)
def sweep_faults(request_body: SweepFaultsRequest) -> RobustnessCurve:
    """Run fault injection sweep.

    Returns:
        RobustnessCurve: The results of the fault sweep, represented as a robustness curve.
    """
    try:
        return fault_sweeper.sweep_faults(
            cnl_spec_path=request_body.cnl_spec_path,
            benchmark_id=request_body.benchmark_id,
            fault_type=request_body.fault_type,
            fault_rates=request_body.fault_rates,
        )
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e)) from e
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e)) from e
