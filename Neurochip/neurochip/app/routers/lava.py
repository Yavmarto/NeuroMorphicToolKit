"""Lava / Loihi 2 Execution Router."""

from __future__ import annotations

import json
import logging
import os
import urllib.error
import urllib.request
from typing import Any, cast

from fastapi import APIRouter, Body, HTTPException

from ..schemas.estimation import NetworkInput
from ..schemas.runtime import HardwareRunResults, SessionStatusResponse
from ..services.lava_backend import LavaBackend, LavaBackendError

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/neurochip/hardware/lava", tags=["lava-hardware"])

# Initialize the backend service
backend = LavaBackend()
REMOTE_LAVA_BACKEND_ENV = "NEUROCHIP_LAVA_BACKEND_URL"


def _lava_error_status_code(error: LavaBackendError) -> int:
    message = str(error).lower()
    # Hardware-specific failure — chip not available
    if "not installed" in message or "hardware" in message or "loihi" in message:
        return 503
    if "session id" in message or "invalid session" in message:
        return 404
    # Runtime / compilation failure — request is well-formed but Lava can't execute it
    return 422


def _remote_lava_backend_url() -> str | None:
    value = os.environ.get(REMOTE_LAVA_BACKEND_ENV, "").strip()
    return value.rstrip("/") if value else None


def _forward_to_remote(path: str, payload: dict[str, object]) -> dict[str, Any]:
    base_url = _remote_lava_backend_url()
    if not base_url:
        raise RuntimeError("Remote Lava backend URL is not configured.")

    request = urllib.request.Request(
        url=f"{base_url}{path}",
        data=json.dumps(payload).encode("utf-8"),
        method="POST",
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:  # noqa: S310
            body = response.read().decode("utf-8")
    except urllib.error.HTTPError as exc:
        detail_text = exc.read().decode("utf-8", errors="replace")
        try:
            detail_payload = json.loads(detail_text)
        except json.JSONDecodeError:
            detail_payload = detail_text or str(exc)
        raise HTTPException(status_code=exc.code, detail=detail_payload) from exc
    except urllib.error.URLError as exc:
        raise HTTPException(
            status_code=503,
            detail=(
                f"Remote Lava backend is unavailable. Could not reach {base_url}: {exc.reason}"
            ),
        ) from exc

    payload_obj = json.loads(body)
    if not isinstance(payload_obj, dict):
        raise HTTPException(
            status_code=502,
            detail="Remote Lava backend returned a non-object JSON response.",
        )
    return cast(dict[str, Any], payload_obj)


@router.post("/compile", response_model=SessionStatusResponse)
def compile_network(
    network: NetworkInput = Body(...),
    run_config: str = Body("sim", embed=True),
) -> SessionStatusResponse:
    """
    Compiles a network using the Lava backend and returns a session ID.
    """
    if _remote_lava_backend_url():
        payload = _forward_to_remote(
            "/api/neurochip/hardware/lava/compile",
            {"network": network.model_dump(mode="json"), "run_config": run_config},
        )
        return SessionStatusResponse(**payload)

    try:
        session_id = backend.compile(network=network, run_config=run_config)
        return SessionStatusResponse(status="compiled", session_id=session_id)
    except LavaBackendError as e:
        logger.error("Lava backend error during compilation: %s", e)
        raise HTTPException(status_code=_lava_error_status_code(e), detail=str(e))
    except Exception:
        logger.exception("Unexpected error during Lava compilation")
        raise HTTPException(status_code=500, detail="An internal server error occurred.")


@router.post("/run", response_model=HardwareRunResults)
def run_network(
    session_id: str = Body(..., embed=True),
    steps: int = Body(100, embed=True),
) -> HardwareRunResults:
    """
    Runs a compiled Lava network session for a specified number of steps.
    """
    if _remote_lava_backend_url():
        payload = _forward_to_remote(
            "/api/neurochip/hardware/lava/run",
            {"session_id": session_id, "steps": steps},
        )
        return HardwareRunResults(**payload)

    try:
        results = backend.run(session_id=session_id, steps=steps)
        return HardwareRunResults(**results)
    except LavaBackendError as e:
        logger.error("Lava backend error during execution: %s", e)
        raise HTTPException(status_code=_lava_error_status_code(e), detail=str(e))
    except Exception:
        logger.exception("Unexpected error during Lava execution")
        raise HTTPException(status_code=500, detail="An internal server error occurred.")


@router.post("/stop", response_model=SessionStatusResponse)
def stop_network(
    session_id: str = Body(..., embed=True),
) -> SessionStatusResponse:
    """
    Stops a Lava network session.
    """
    if _remote_lava_backend_url():
        payload = _forward_to_remote(
            "/api/neurochip/hardware/lava/stop",
            {"session_id": session_id},
        )
        return SessionStatusResponse(**payload)

    try:
        backend.stop(session_id=session_id)
        return SessionStatusResponse(status="stopped", session_id=session_id)
    except LavaBackendError as e:
        logger.error("Lava backend error during stop: %s", e)
        raise HTTPException(status_code=_lava_error_status_code(e), detail=str(e))
    except Exception:
        logger.exception("Unexpected error stopping Lava session")
        raise HTTPException(status_code=500, detail="An internal server error occurred.")
