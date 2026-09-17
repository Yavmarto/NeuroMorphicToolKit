"""Akida deployment and inference endpoints for Neurochip.

Provides stateful backend management following the PYNQ router pattern:
a module-level ``backend_instance`` holds the current Akida backend state.

Endpoints:
- POST /deploy          — deploy from NetworkInput (backward-compatible)
- POST /deploy/mapped   — deploy from pre-mapped AkidaMappedNetwork (preferred)
- POST /map             — construct and map a runtime-ready Akida model
- POST /inference       — run inference on the mapped model
- GET  /status          — query current backend/SDK status
- POST /verify          — deprecated compatibility alias for status-or-map behavior
- WS   /stream          — bidirectional spike stream for real-time inference

Deployment modes (``deployment_mode`` query param):
- ``scaffold``      – Generate and return the ZIP package; SDK not required (default).
- ``on_device``     – Require successful SDK mapping; fail with 502 if unavailable.
- ``remote_server`` – POST the generated ZIP to ``target_url``; return remote response.
"""

import asyncio
import functools
import logging
from typing import Any

from fastapi import (
    APIRouter,
    Body,
    HTTPException,
    Query,
    Request,
    Response,
    WebSocket,
    WebSocketDisconnect,
)
from pydantic import ValidationError

from ...contracts.akida_model_bundle_contract import (
    AkidaModelInferenceRequest,
    AkidaModelInferenceResult,
    AkidaModelJobRequest,
    AkidaModelJobStatus,
    AkidaModelVisualizationRequest,
    AkidaModelVisualizationResult,
)
from ...contracts.akida_runtime_contract import AkidaDeploymentMode, AkidaRuntimeStatusContract
from ..schemas.estimation import NetworkInput
from ..services.akida_backend import AKIDA_AVAILABLE, AkidaBackend, build_akida_runtime_status
from ..services.akida_errors import AkidaRuntimeError
from ..services.akida_model_jobs import (
    AkidaModelJobError as AkidaModelJobError,
)
from ..services.akida_model_jobs import (
    akida_model_job_service as akida_model_job_service,
)
from ..services.akida_router_support import (
    _deploy_error_to_http,
    akida_error_to_http,
    deploy_from_mapped,
    deploy_from_network,
    map_backend,
)

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/neurochip/akida", tags=["akida"])

# Module-level backend instance (following PYNQ router pattern)
backend_instance: AkidaBackend | None = None


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _map_backend_and_build_status(
    mapped_network: dict[str, Any],
    *,
    bit_width: int,
) -> AkidaRuntimeStatusContract:
    """Construct and map a backend, returning a structured runtime status."""
    global backend_instance

    try:
        backend, status_kwargs = map_backend(mapped_network, bit_width=bit_width)
    except AkidaRuntimeError as exc:
        raise akida_error_to_http(exc) from exc

    if backend is not None:
        backend_instance = backend
    return AkidaRuntimeStatusContract(**status_kwargs)


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------


@router.post("/deploy")
def deploy_akida(
    request: Request,
    response: Response,
    network: NetworkInput = Body(..., embed=True),
    bit_width: int = Query(4),
    deployment_mode: AkidaDeploymentMode = Query(
        "scaffold",
        description=(
            "How to handle the generated artifact. "
            "'scaffold' (default) returns the ZIP for download. "
            "'on_device' requires a successful SDK mapping to hardware or the AKD1000 simulator. "
            "'remote_server' POSTs the ZIP to target_url and returns the remote response."
        ),
    ),
    target_url: str | None = Query(
        None,
        description="Required when deployment_mode=remote_server. "
        "Absolute HTTP/HTTPS URL of the target Akida runtime server.",
    ),
    quantized_weights: list[float] | None = Body(None),
) -> Response:
    """Generate an Akida deployment artifact from a NetworkInput (legacy path).

    Use ``deployment_mode`` to control where the artifact goes:

    - **scaffold** (default) — Returns a ``.zip`` download; SDK not required.
    - **on_device** — Requires SDK mapping; fails with 502 if SDK is unavailable.
    - **remote_server** — POSTs the ZIP to ``target_url``; returns the remote
      server's response as JSON.

    Runtime SDK status is always available via ``GET /api/neurochip/akida/status``.
    Explicit runtime mapping uses ``POST /api/neurochip/akida/map``.
    """
    global backend_instance

    def _set_backend(backend: AkidaBackend) -> None:
        global backend_instance
        backend_instance = backend

    try:
        return deploy_from_network(
            network,
            bit_width=bit_width,
            deployment_mode=deployment_mode,
            target_url=target_url,
            quantized_weights=quantized_weights,
            set_backend=_set_backend,
        )
    except HTTPException:
        raise
    except AkidaRuntimeError as exc:
        raise akida_error_to_http(exc) from exc
    except ValidationError as exc:
        logger.warning("Validation error during deploy: %s", exc)
        raise HTTPException(status_code=422, detail="Invalid network configuration.") from exc
    except Exception as exc:
        raise _deploy_error_to_http(
            exc,
            validation_detail="Invalid network configuration.",
        ) from exc


@router.post("/deploy/mapped")
def deploy_akida_mapped(
    request: Request,
    response: Response,
    mapped_network: dict[str, Any] = Body(...),
    bit_width: int = Query(4),
    deployment_mode: AkidaDeploymentMode = Query(
        "scaffold",
        description=(
            "How to handle the generated artifact. "
            "'scaffold' (default) returns the ZIP for download. "
            "'on_device' requires a successful SDK mapping to hardware or the AKD1000 simulator. "
            "'remote_server' POSTs the ZIP to target_url and returns the remote response."
        ),
    ),
    target_url: str | None = Query(
        None,
        description="Required when deployment_mode=remote_server. "
        "Absolute HTTP/HTTPS URL of the target Akida runtime server.",
    ),
) -> Response:
    """Generate an Akida deployment artifact from a pre-mapped network (preferred path).

    Package generation is intentionally decoupled from verified SDK status so
    callers can truthfully distinguish scaffold export from runtime proof.

    Use ``deployment_mode`` to control where the artifact goes:

    - **scaffold** (default) — Returns a ``.zip`` download; SDK not required.
    - **on_device** — Requires SDK mapping; fails with 502 if SDK is unavailable.
    - **remote_server** — POSTs the ZIP to ``target_url``; returns the remote
      server's response as JSON.
    """
    global backend_instance

    def _set_backend(backend: AkidaBackend) -> None:
        global backend_instance
        backend_instance = backend

    try:
        return deploy_from_mapped(
            mapped_network,
            bit_width=bit_width,
            deployment_mode=deployment_mode,
            target_url=target_url,
            set_backend=_set_backend,
        )
    except HTTPException:
        raise
    except AkidaRuntimeError as exc:
        raise akida_error_to_http(exc) from exc
    except ValidationError as exc:
        logger.warning("Validation error during mapped deploy: %s", exc)
        raise HTTPException(status_code=422, detail="Invalid mapped network payload.") from exc
    except Exception as exc:
        raise _deploy_error_to_http(
            exc,
            validation_detail="Invalid mapped network payload.",
        ) from exc


@router.post("/inference")
def inference_akida(
    request: Request,
    response: Response,
    inputs: list[float] = Body(..., embed=True),
) -> dict[str, Any]:
    """Run inference on the currently mapped Akida model."""
    if backend_instance is None:
        raise HTTPException(
            status_code=422,
            detail="No Akida model is deployed. Call /deploy or /deploy/mapped first.",
        )
    try:
        return backend_instance.run_inference(inputs)
    except AkidaRuntimeError as exc:
        raise akida_error_to_http(exc) from exc
    except Exception:
        logger.exception("Unexpected error during Akida inference")
        raise HTTPException(
            status_code=500,
            detail="An internal server error occurred during inference.",
        )


@router.post("/model-jobs", response_model=AkidaModelJobStatus, status_code=202)
def create_akida_model_job(request: AkidaModelJobRequest) -> AkidaModelJobStatus:
    """Validate and asynchronously convert a versioned ONNX model bundle."""
    try:
        return akida_model_job_service.submit(request)
    except AkidaModelJobError as exc:
        raise HTTPException(
            status_code=422,
            detail={"error_code": exc.error_code, "message": str(exc)},
        ) from exc


@router.get("/model-jobs/{job_id}", response_model=AkidaModelJobStatus)
def get_akida_model_job(job_id: str) -> AkidaModelJobStatus:
    """Return conversion, mapping, and evaluation progress for one job."""
    try:
        return akida_model_job_service.get(job_id)
    except KeyError as exc:
        raise HTTPException(
            status_code=404,
            detail={"error_code": "MODEL_JOB_NOT_FOUND", "message": "Model job not found."},
        ) from exc


@router.post(
    "/models/{model_id}/benchmark",
    response_model=AkidaModelJobStatus,
    status_code=202,
)
def benchmark_akida_model(model_id: str) -> AkidaModelJobStatus:
    """Re-score the bundled evaluation set on the card, with timing.

    Returns a job immediately and reports progress through
    ``GET /model-jobs/{job_id}``: a full set can take far longer than any
    request timeout on the path between here and the app.
    """
    try:
        return akida_model_job_service.benchmark(model_id)
    except AkidaModelJobError as exc:
        status_code = 404 if exc.error_code == "MODEL_NOT_LOADED" else 422
        raise HTTPException(
            status_code=status_code,
            detail={"error_code": exc.error_code, "message": str(exc)},
        ) from exc


@router.post(
    "/models/{model_id}/inference",
    response_model=AkidaModelInferenceResult,
)
def inference_akida_model(
    model_id: str,
    request: AkidaModelInferenceRequest,
) -> AkidaModelInferenceResult:
    """Run sample inference and report the model's truthful runtime target."""
    try:
        return akida_model_job_service.infer(model_id, request)
    except AkidaModelJobError as exc:
        status_code = 404 if exc.error_code == "MODEL_NOT_LOADED" else 422
        raise HTTPException(
            status_code=status_code,
            detail={"error_code": exc.error_code, "message": str(exc)},
        ) from exc


@router.post(
    "/models/{model_id}/visualization",
    response_model=AkidaModelVisualizationResult,
)
def visualize_akida_model(
    model_id: str,
    request: AkidaModelVisualizationRequest,
) -> AkidaModelVisualizationResult:
    """Replay the exact deployed model in software for companion views."""
    try:
        return akida_model_job_service.visualize(model_id, request)
    except AkidaModelJobError as exc:
        status_code = 404 if exc.error_code == "MODEL_NOT_LOADED" else 422
        raise HTTPException(
            status_code=status_code,
            detail={"error_code": exc.error_code, "message": str(exc)},
        ) from exc


@router.websocket("/stream")
async def stream_inference_akida(websocket: WebSocket) -> None:
    """Bidirectional spike stream for real-time Akida inference at loop frequency.

    Client → server::

        {"inputs": [float, ...]}

    Server → client (success)::

        {"outputs": [float, ...], "spike_count": int,
         "telemetry": dict, "execution_time_us": float | null}

    Server → client (error)::

        {"error": str, "error_code": str}

    The connection stays open; the client sends frames at its own pace and
    receives one reply per frame.  Encoding (sensor → inputs) stays
    client-side so this endpoint is target-agnostic.
    """
    await websocket.accept()
    loop = asyncio.get_running_loop()
    try:
        while True:
            data = await websocket.receive_json()

            inputs = data.get("inputs")

            if not isinstance(inputs, list):
                await websocket.send_json(
                    {"error": "inputs must be a list of float", "error_code": "INVALID_INPUT"}
                )
                continue

            backend = backend_instance
            if backend is None:
                await websocket.send_json(
                    {
                        "error": "No Akida model is deployed. Call /deploy or /deploy/mapped first.",
                        "error_code": "NOT_DEPLOYED",
                    }
                )
                continue

            try:
                result: dict[str, Any] = await loop.run_in_executor(
                    None,
                    functools.partial(backend.run_inference, inputs),
                )
                outputs: list[Any] = result.get("outputs", [])
                await websocket.send_json(
                    {
                        "outputs": outputs,
                        "spike_count": len(outputs),
                        "telemetry": result.get("telemetry", {}),
                        "execution_time_us": result.get("execution_time_us"),
                    }
                )
            except AkidaRuntimeError as exc:
                await websocket.send_json({"error": str(exc), "error_code": exc.error_code})
            except Exception as exc:
                logger.exception("Unexpected error in Akida stream")
                await websocket.send_json({"error": str(exc), "error_code": "INTERNAL_ERROR"})
    except WebSocketDisconnect:
        logger.debug("Akida stream client disconnected")


@router.get("/status")
def status_akida() -> AkidaRuntimeStatusContract:
    """Query the current Akida backend state and SDK availability."""
    if backend_instance is None:
        return AkidaRuntimeStatusContract(
            **build_akida_runtime_status(
                state="not_initialised",
                sdk_available=AKIDA_AVAILABLE,
            )
        )

    status = backend_instance.get_sdk_status()
    return AkidaRuntimeStatusContract(**status)


@router.post("/map")
def map_akida(
    request: Request,
    response: Response,
    mapped_network: dict[str, Any] = Body(...),
    bit_width: int = Query(4),
) -> AkidaRuntimeStatusContract:
    """Construct and map an Akida runtime from a mapped-network payload."""
    return _map_backend_and_build_status(mapped_network, bit_width=bit_width)


@router.post("/verify", deprecated=True)
def verify_akida(
    request: Request,
    response: Response,
    mapped_network: dict[str, Any] | None = Body(None),
    bit_width: int = Query(4),
) -> AkidaRuntimeStatusContract:
    """Compatibility route for status checks and legacy map-on-verify callers.

    Use ``POST /api/neurochip/akida/map`` for canonical mapping and
    ``GET /api/neurochip/akida/status`` for status-only checks.
    """
    global backend_instance
    response.headers["Deprecation"] = "true"
    response.headers["Link"] = '</api/neurochip/akida/map>; rel="successor-version"'

    if mapped_network is not None:
        return _map_backend_and_build_status(mapped_network, bit_width=bit_width)

    if backend_instance is None:
        return AkidaRuntimeStatusContract(
            **build_akida_runtime_status(
                state="not_initialised",
                sdk_available=AKIDA_AVAILABLE,
            )
        )

    status = backend_instance.get_sdk_status()
    return AkidaRuntimeStatusContract(**status)
