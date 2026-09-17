"""POST /api/neurosim/handoff — prepare a NeuroSim import payload."""

from fastapi import APIRouter, HTTPException, Request, Response

from backend.app.middleware.rate_limit import limiter
from backend.app.schemas.neurosim_handoff import (
    NeurosimHandoffRequest,
    NeurosimHandoffResponse,
)
from neurocnl.handoff.neurosim_cnl_handoff import (
    NeurosimHandoffRejectedError,
    build_neurosim_handoff_spec,
)

router = APIRouter(prefix="/neurosim")


@router.post("/handoff", response_model=NeurosimHandoffResponse)
@limiter.limit("20/minute")
def prepare_neurosim_handoff(
    request: Request,
    response: Response,
    body: NeurosimHandoffRequest,
) -> NeurosimHandoffResponse:
    """Normalize a NeuroCNL spec into NeuroSim's canonical import contract."""
    try:
        import_contract = build_neurosim_handoff_spec(body.spec)
    except NeurosimHandoffRejectedError as exc:
        raise HTTPException(status_code=exc.status_code, detail=str(exc)) from exc

    return NeurosimHandoffResponse(import_contract=import_contract)
