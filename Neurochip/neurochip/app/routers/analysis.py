from fastapi import APIRouter, HTTPException, Request, Response

from ..schemas.analysis import ConstraintReport
from ..schemas.estimation import NetworkInput
from ..schemas.runtime import PartitionCompareResponse, PartitionPlanResponse, PartitionResult
from ..services import constraint_analyzer
from ..services import partitioner as partitioner_service

router = APIRouter(prefix="/api/neurochip", tags=["analysis"])


@router.post("/analyze", response_model=ConstraintReport)
def analyze(
    request: Request, response: Response, network: NetworkInput, target_id: str
) -> ConstraintReport:
    return constraint_analyzer.analyze(network, target_id)


@router.post("/partition", response_model=PartitionResult)
def partition(
    request: Request,
    response: Response,
    network: NetworkInput,
    target_id: str,
) -> PartitionResult:
    """Suggest partitioning strategies for a network that exceeds a target's capacity.

    Returns a :class:`PartitionResult` with ``network_fits_single_chip=True``
    and an empty ``suggestions`` list when the network fits without partitioning.

    All outputs carry ``support_level="heuristic"`` / ``is_estimate=True``
    and must not be used as deploy-readiness gates.
    """
    try:
        profile = constraint_analyzer._load_target(target_id)
    except FileNotFoundError:
        raise HTTPException(status_code=404, detail=f"Hardware target '{target_id}' not found.")
    except Exception as exc:
        raise HTTPException(
            status_code=422,
            detail=f"Could not load target profile '{target_id}': {exc}",
        )

    target_capacity: int = profile.neuron_capacity
    if target_capacity <= 0:
        raise HTTPException(
            status_code=422,
            detail=(
                f"Target '{target_id}' does not declare a positive neuron_capacity "
                "— cannot compute partitions."
            ),
        )

    fits = network.num_neurons <= target_capacity
    plans = partitioner_service.suggest_partitions(network, target_capacity)
    suggestions = [PartitionPlanResponse(**partitioner_service.plan_to_response(p)) for p in plans]

    message: str | None = None
    if not fits:
        message = (
            f"Network has {network.num_neurons} neurons but '{target_id}' supports at most "
            f"{target_capacity}. {len(suggestions)} partition strateg"
            f"{'y' if len(suggestions) == 1 else 'ies'} suggested."
        )

    return PartitionResult(
        status="ok",
        target_id=target_id,
        target_capacity=target_capacity,
        network_fits_single_chip=fits,
        suggestions=suggestions,
        message=message,
    )


@router.post("/compare", response_model=PartitionCompareResponse)
def compare(request: Request, response: Response) -> PartitionCompareResponse:
    return PartitionCompareResponse(
        status="placeholder",
        message="Target comparison is not yet implemented.",
        hint="Use single-target analysis until comparison support lands.",
    )
