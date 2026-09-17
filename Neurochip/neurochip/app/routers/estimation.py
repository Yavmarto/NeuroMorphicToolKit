from fastapi import APIRouter, Request, Response

from ..schemas.estimation import LatencyEstimate, NetworkInput, PowerEstimate
from ..services import power_estimator

router = APIRouter(prefix="/api/neurochip/estimate", tags=["estimation"])


@router.post("/power", response_model=PowerEstimate)
def estimate_power(
    request: Request, response: Response, network: NetworkInput, target_id: str
) -> PowerEstimate:
    return power_estimator.estimate_power(network, target_id)


@router.post("/latency", response_model=LatencyEstimate)
def estimate_latency(
    request: Request, response: Response, network: NetworkInput, target_id: str
) -> LatencyEstimate:
    return power_estimator.estimate_latency(network, target_id)
