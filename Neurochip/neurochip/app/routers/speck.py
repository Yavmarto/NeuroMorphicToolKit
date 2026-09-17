"""Speck 2 Execution Router."""

import logging
from typing import Any

from fastapi import APIRouter, Body, HTTPException

from ...contracts.speck_runtime_contract import SpeckMappedNetworkPayloadContract
from ..services.speck_backend import SpeckBackend
from ..services.speck_errors import SpeckRuntimeError

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/neurochip/hardware/speck", tags=["speck-hardware"])

# Initialize the backend service
backend = SpeckBackend()


@router.get("/status")
def get_status() -> dict[str, Any]:
    """Return the current status of the Speck backend."""
    return backend.get_status()


@router.post("/configure")
def configure_network(
    mapped_network: SpeckMappedNetworkPayloadContract = Body(...),
) -> dict[str, Any]:
    """Configures a network on the Speck backend."""
    try:
        backend.construct_model(mapped_network.model_dump())
        backend.map_to_device()
        return {"status": "configured", "state": backend.current_state}
    except SpeckRuntimeError as e:
        logger.error("Speck backend error during configuration: %s", e)
        raise HTTPException(status_code=400, detail={"error_code": e.error_code, "message": str(e)})
    except Exception:
        logger.exception("Unexpected error during Speck configuration")
        raise HTTPException(status_code=500, detail="An internal server error occurred.")


@router.post("/run")
def run_inference(
    inputs: list[float] = Body(..., embed=True),
) -> dict[str, Any]:
    """Runs inference on the configured Speck network."""
    try:
        results = backend.run_inference(inputs)
        return results
    except SpeckRuntimeError as e:
        logger.error("Speck backend error during inference: %s", e)
        raise HTTPException(status_code=400, detail={"error_code": e.error_code, "message": str(e)})
    except Exception:
        logger.exception("Unexpected error during Speck inference")
        raise HTTPException(status_code=500, detail="An internal server error occurred.")


@router.post("/reset")
def reset_backend() -> dict[str, Any]:
    """Resets the Speck backend state."""
    try:
        backend.reset()
        return {"status": "reset", "state": backend.current_state}
    except SpeckRuntimeError as e:
        logger.error("Speck backend error during reset: %s", e)
        raise HTTPException(status_code=400, detail={"error_code": e.error_code, "message": str(e)})
    except Exception:
        logger.exception("Unexpected error during Speck reset")
        raise HTTPException(status_code=500, detail="An internal server error occurred.")
