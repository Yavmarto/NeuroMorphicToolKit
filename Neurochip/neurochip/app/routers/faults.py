from fastapi import APIRouter, Query, Request, Response

from neurochip.contracts.fault_contracts import FaultSweepResult

from ..schemas.estimation import NetworkInput
from ..services import fault_runner

router = APIRouter(prefix="/api/neurochip/faults", tags=["faults"])


@router.post("", response_model=FaultSweepResult)
def sweep_faults(
    request: Request,
    response: Response,
    network: NetworkInput,
    fault_type: str = "dead_neuron",
    fault_rates: list[float] | None = Query(None),
    baseline_accuracy: float = 0.98,
) -> FaultSweepResult:
    """Sweep injected faults across rates and return estimated robustness metrics."""
    return fault_runner.sweep_faults(network, fault_type, fault_rates, baseline_accuracy)
