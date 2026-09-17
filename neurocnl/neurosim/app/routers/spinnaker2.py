"""Router for SpiNNaker2 simulation endpoints."""

from fastapi import APIRouter, HTTPException, Query, Request, Response

from neurosim.app.backends.spinnaker2_backend import (
    SPINNAKER2_AVAILABLE,
    SpiNNaker2SimBackend,
)
from neurosim.app.limiter import rate_limit
from neurosim.app.services.spinnaker2_store import spinnaker2_job_store
from neurosim.contracts.design_contracts import (
    PreviewRequest,
    SimulationStatus,
    SpinnakerResponse,
)

router = APIRouter(prefix="/api/sim/spinnaker2", tags=["spinnaker2", "simulation"])


@router.post("/run", response_model=SpinnakerResponse)
@rate_limit("20/minute")
def run_spinnaker2(
    request: Request,
    response: Response,
    payload: PreviewRequest,
    mock_mode: bool = Query(default=False),
) -> SpinnakerResponse:
    """Run a network simulation on the SpiNNaker2 backend.

    Args:
        request (Request): The FastAPI request object.
        response (Response): The FastAPI response used by SlowAPI for rate-limit headers.
        payload (PreviewRequest): The preview request containing the network graph.

    Returns:
        SpinnakerResponse: The result containing spike and voltage data.
    """
    _ = request, response
    try:
        backend = SpiNNaker2SimBackend(mock_mode=mock_mode)
        backend.load(payload.graph)
        run_id = backend.run(payload.duration_ms)
        spinnaker2_job_store.put(run_id, backend)
        results = backend.get_results()

        return SpinnakerResponse(
            job_id=run_id,
            status=SimulationStatus.COMPLETED,
            results=results,
            backend_type="mock" if mock_mode else "hardware",
            metrics={
                "simulation_time_ms": payload.duration_ms,
                "n_neurons": sum(
                    node.parameters.get("n_neurons", 100) for node in payload.graph.nodes
                ),
                "n_connections": len(payload.graph.edges),
            },
        )
    except RuntimeError as exc:
        return SpinnakerResponse(
            status=SimulationStatus.FAILED,
            backend_type="unavailable",
            error=str(exc),
            results=None,
        )
    except Exception as exc:
        return SpinnakerResponse(
            status=SimulationStatus.FAILED,
            backend_type=("mock" if mock_mode or not SPINNAKER2_AVAILABLE else "hardware"),
            error=str(exc),
            results=None,
        )


@router.get("/results/{run_id}", response_model=SpinnakerResponse)
@rate_limit("60/minute")
def get_spinnaker2_results(
    request: Request,
    response: Response,
    run_id: str,
) -> SpinnakerResponse:
    """Retrieve the results for a specific SpiNNaker2 simulation run.

    Args:
        request (Request): The FastAPI request object.
        response (Response): The FastAPI response used by SlowAPI for rate-limit headers.
        run_id (str): The run identifier.

    Returns:
        SpinnakerResponse: The retrieved simulation results.
    """
    _ = request, response
    backend = spinnaker2_job_store.get(run_id)
    if backend is None:
        raise HTTPException(status_code=404, detail="Run not found or expired")

    results = backend.get_results()

    return SpinnakerResponse(
        job_id=run_id,
        status=SimulationStatus.COMPLETED,
        results=results,
        backend_type="mock" if getattr(backend, "_mock_mode", False) else "hardware",
    )
