import json
import logging

from fastapi import APIRouter, Body, HTTPException, Query
from fastapi.responses import StreamingResponse

from ..schemas.estimation import NetworkInput
from ..schemas.runtime import CompiledNetworkResponse, HardwareRunResponse, HardwareRunResults
from ..services.spinnaker2_backend import SpiNNaker2Backend

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/neurochip/hardware/spinnaker2", tags=["spinnaker2"])
backend = SpiNNaker2Backend()


@router.post("/compile", response_model=CompiledNetworkResponse)
def compile_spinnaker2_network(
    network: NetworkInput = Body(..., embed=True),
) -> CompiledNetworkResponse:
    """
    Compiles a generic NetworkInput into a SpiNNaker2 deployment network.
    """
    try:
        compiled_network = backend.compile_network(network)
        return CompiledNetworkResponse(status="success", compiled_network=compiled_network)
    except Exception as e:
        logger.exception("Failed to compile network for SpiNNaker2")
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/run", response_model=HardwareRunResponse)
def run_spinnaker2_network(
    network: NetworkInput = Body(..., embed=True),
    timesteps: int = Query(100, description="Number of simulation timesteps"),
    board_id: str | None = Query(None, description="Optional board ID or hostname"),
) -> HardwareRunResponse:
    """
    Compiles and executes a network on SpiNNaker2 hardware.
    """
    try:
        compiled_network = backend.compile_network(network)
        results = backend.run_network(compiled_network, timesteps, board_id)
        return HardwareRunResponse(status="success", results=HardwareRunResults(**results))
    except Exception as e:
        logger.exception("Failed to execute network on SpiNNaker2 hardware")
        raise HTTPException(status_code=500, detail=f"Hardware execution failed: {e}")


@router.post("/stream")
def stream_spinnaker2_network(
    network: NetworkInput = Body(..., embed=True),
    timesteps: int = Query(100, description="Number of simulation timesteps"),
    board_id: str | None = Query(None, description="Optional board ID or hostname"),
) -> StreamingResponse:
    """
    Compile, execute and stream execution telemetry as server-sent events for real-time processing.
    """

    async def event_generator():
        try:
            compiled_network = backend.compile_network(network)
            async for event in backend.stream_spikes(compiled_network, timesteps, board_id):
                yield f"data: {json.dumps(event)}\n\n"
        except Exception as e:
            logger.exception("Failed to stream execution telemetry")
            yield f"data: {json.dumps({'error': str(e)})}\n\n"

    return StreamingResponse(event_generator(), media_type="text/event-stream")
