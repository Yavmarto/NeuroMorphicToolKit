"""PYNQ hardware router — compile, deploy, run, and query the PYNQ backend."""

import asyncio
import functools
import logging
from typing import Any

from fastapi import (
    APIRouter,
    File,
    Form,
    HTTPException,
    Request,
    Response,
    UploadFile,
    WebSocket,
    WebSocketDisconnect,
)
from pydantic import BaseModel, ConfigDict, Field

from ..schemas.runtime import PynqDeployResponse, PynqRunResponse
from ..services.pynq_backend import PYNQBackend, default_runtime_mode
from ..services.pynq_compiler import PynqCompileError, PynqCompilerService
from ..services.pynq_errors import PynqRuntimeError
from ..services.pynq_install_status import read_install_status
from ..services.pynq_loop_manager import (
    LoopProcessError,
    LoopState,
    is_loop_alive,
    start_loop_local,
    start_loop_ssh,
    stop_loop_local,
    stop_loop_ssh,
)
from ..services.pynq_overlay_assets import DEFAULT_PYNQ_BITSTREAM_NAME
from ..services.pynq_router_support import (
    HardwareProbeCache,
    build_preflight_status,
    current_overlay_assets,
    pynq_compile_error_to_http,
    validate_overlay_request,
)
from ..services.pynq_router_support import (
    pynq_error_to_http as pynq_error_to_http,
)
from ..services.pynq_sitl_verifier import (
    SITLStimulusCase as _SITLStimulusCase,
)
from ..services.pynq_sitl_verifier import (
    SITLVerificationConfig,
    run_sitl_verification,
)

router = APIRouter(prefix="/hardware/pynq", tags=["Hardware", "PYNQ"])
logger = logging.getLogger(__name__)

DEFAULT_BITSTREAM = DEFAULT_PYNQ_BITSTREAM_NAME
backend_instance: PYNQBackend | None = None
compile_service = PynqCompilerService()
_loop_state: LoopState | None = None
_hardware_probe_cache = HardwareProbeCache()


# ---------------------------------------------------------------------------
# Request / response models
# ---------------------------------------------------------------------------


class DeployRequest(BaseModel):
    """Payload for the ``/deploy`` endpoint."""

    model_config = ConfigDict(strict=True)

    weights: list[float]
    #: One descriptor per layer: input_size, output_size, weight_offset,
    #: threshold, leak_shift, refractory. Overlay-v1 held a single weight
    #: matrix and one global threshold, so it needed none of this.
    layers: list[dict[str, Any]] = Field(default_factory=list)
    config: dict[str, Any] | None = None
    bitstream_path: str | None = DEFAULT_BITSTREAM
    overlay_id: str | None = None
    overlay_version: str | None = None
    weight_bit_width: int | None = None
    max_supported_neurons: int | None = None
    max_supported_synapses: int | None = None
    dma_ip_name: str | None = None
    snn_ip_name: str | None = None
    require_hardware: bool = False
    register_map: dict[str, Any] | None = Field(
        default=None,
        description="Optional manifest-derived Zynq-7000 register map override.",
    )


class RunRequest(BaseModel):
    """Payload for the ``/run`` endpoint."""

    model_config = ConfigDict(strict=True)

    input_spikes: list[int]
    timesteps: int = Field(default=1, ge=1, description="Number of simulation timesteps.")


class ErrorResponse(BaseModel):
    """Structured error body returned by PYNQ endpoints."""

    detail: str
    error_code: str


class LoopStartRequest(BaseModel):
    """Payload for ``POST /loop/start``."""

    model_config = ConfigDict(strict=True)

    zmq_port: int = Field(default=5555, ge=1024, le=65535)
    bitstream_path: str = DEFAULT_BITSTREAM
    ssh_host: str | None = None
    ssh_user: str = "xilinx"
    ssh_password: str | None = Field(default=None, exclude=True)
    ssh_key_path: str | None = None
    ssh_port: int = Field(default=22, ge=1, le=65535)
    install_root: str = "/opt/neurochip-pynq-agent"


class LoopStartResponse(BaseModel):
    """Response body for ``POST /loop/start``."""

    status: str
    pid: int
    zmq_port: int


class LoopStopResponse(BaseModel):
    """Response body for ``POST /loop/stop``."""

    status: str


class StatusResponse(BaseModel):
    """Response body for the ``/status`` endpoint."""

    state: str
    bitstream_path: str | None = None
    runtime_mode: str = "unknown"
    install_mode: str = "unknown"
    overlay_assets: dict[str, Any]
    loop_running: bool = False


class PreflightResponse(BaseModel):
    """Board-readiness assessment for the real PYNQ path."""

    preflight_status: str
    preflight_message: str
    runtime_mode: str
    install_mode: str = "unknown"
    overlay_assets: dict[str, Any]
    resolved_paths: dict[str, str] = Field(default_factory=dict)
    runtime_details: dict[str, Any] = Field(default_factory=dict)


class CompileResponse(BaseModel):
    """Response body for the ``/compile`` endpoint."""

    status: str
    compiler: str
    overlay_id: str
    overlay_version: str
    target_part: str
    network_name: str
    total_neurons: int
    total_synapses: int
    staged_overlay: dict[str, Any]
    compiler_stdout: str = ""
    compiler_stderr: str = ""


# ---------------------------------------------------------------------------
# Verify request / response models
# ---------------------------------------------------------------------------


class VerifyStimulusCase(BaseModel):
    """A single SITL stimulus case for the ``/verify`` endpoint."""

    label: str
    input_spikes: list[int]
    expected_output_spikes: list[int] | None = None
    timesteps: int = Field(default=1, ge=1)


class VerifyStepResult(BaseModel):
    """Per-step result within a ``/verify`` response."""

    label: str
    input_spikes: list[int]
    output_spikes: list[int]
    expected_output_spikes: list[int] | None
    passed: bool
    execution_time_us: float


class PynqVerifyRequest(BaseModel):
    """Payload for the ``/verify`` endpoint.

    If ``weights`` is supplied the endpoint deploys a fresh backend before
    running verification.  Otherwise the existing deployed backend is used.
    """

    model_config = ConfigDict(strict=True)

    weights: list[float] | None = None
    layers: list[dict[str, Any]] = Field(default_factory=list)
    config: dict[str, Any] | None = None
    bitstream_path: str | None = DEFAULT_BITSTREAM
    overlay_id: str | None = None
    overlay_version: str | None = None
    weight_bit_width: int | None = None
    max_supported_neurons: int | None = None
    max_supported_synapses: int | None = None
    dma_ip_name: str | None = None
    snn_ip_name: str | None = None
    register_map: dict[str, Any] | None = None
    stimulus_cases: list[VerifyStimulusCase] | None = None


class VerifyResponse(BaseModel):
    """Response body for the ``/verify`` endpoint."""

    passed: bool
    total_cases: int
    passed_cases: int
    mean_exec_us: float
    max_exec_us: float
    summary: str
    steps: list[VerifyStepResult]


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _build_preflight_response() -> PreflightResponse:
    return PreflightResponse(
        **build_preflight_status(
            backend_instance=backend_instance,
            default_runtime_mode=default_runtime_mode(),
            probe_cache=_hardware_probe_cache,
        )
    )


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------


@router.post("/compile", response_model=CompileResponse)
async def compile_overlay(
    request: Request,
    response: Response,
    artifact: UploadFile = File(...),
    compiler: str = Form("finn"),
) -> dict[str, Any]:
    """Compile a NeuroCNL PYNQ artifact ZIP into board-ready overlay assets."""
    _ = (request, response)
    try:
        artifact_zip_bytes = await artifact.read()
        result = compile_service.compile_artifact(artifact_zip_bytes, compiler=compiler)
        return result.to_dict()
    except PynqCompileError as exc:
        raise pynq_compile_error_to_http(exc) from exc


@router.post("/deploy", response_model=PynqDeployResponse)
def deploy_overlay(
    request: DeployRequest,
    require_hardware: bool = False,
) -> PynqDeployResponse:
    """Load the FPGA overlay, write weights via MMIO, and prepare for run."""
    global backend_instance
    try:
        register_map = validate_overlay_request(request, backend_instance)
        candidate_backend = PYNQBackend(bitstream_path=request.bitstream_path or DEFAULT_BITSTREAM)
        effective_require_hardware = require_hardware or request.require_hardware
        if effective_require_hardware and candidate_backend.runtime_mode == "simulator":
            raise HTTPException(
                status_code=503,
                detail={
                    "error": "hardware_required",
                    "message": "Deployment requires real hardware but no PYNQ board was detected.",
                    "runtime_mode": candidate_backend.runtime_mode,
                    "hint": "Check board power/connectivity or omit require_hardware=true.",
                },
            )
        candidate_backend.load_overlay()
        candidate_backend.configure(
            weights=request.weights,
            config=request.config or {},
            register_map=register_map,
            layers=request.layers,
        )
        backend_instance = candidate_backend
        preflight_result = _build_preflight_response()
        overlay_version = None
        if candidate_backend.overlay_manifest is not None:
            overlay_version = candidate_backend.overlay_manifest.overlay_version
        return PynqDeployResponse(
            status="success",
            message="Overlay loaded and configured successfully.",
            runtime_mode=candidate_backend.runtime_mode,
            preflight_status=preflight_result.preflight_status,
            overlay_version=overlay_version,
        )
    except HTTPException:
        raise
    except PynqRuntimeError as exc:
        logger.exception("PYNQ deploy failed")
        raise pynq_error_to_http(exc, probe_cache=_hardware_probe_cache) from exc
    except Exception as exc:
        logger.exception("Unexpected error during PYNQ deploy")
        raise HTTPException(status_code=500, detail=str(exc)) from exc


@router.post("/run", response_model=PynqRunResponse)
def run_inference(request: RunRequest) -> PynqRunResponse:
    """Stream input spikes to the overlay and read back output spikes."""
    global backend_instance
    if not backend_instance:
        raise HTTPException(status_code=400, detail="Overlay not deployed. Call /deploy first.")

    try:
        result = backend_instance.run(
            input_spikes=request.input_spikes,
            timesteps=request.timesteps,
        )
        return PynqRunResponse(status="success", **result)
    except PynqRuntimeError as exc:
        logger.exception("PYNQ run failed")
        raise pynq_error_to_http(exc, probe_cache=_hardware_probe_cache) from exc
    except Exception as exc:
        logger.exception("Unexpected error during PYNQ run")
        raise HTTPException(status_code=500, detail=str(exc)) from exc


@router.websocket("/stream")
async def stream_inference(websocket: WebSocket) -> None:
    """Bidirectional spike stream for real-time inference at loop frequency.

    Each message in both directions is a JSON object.

    Client → server::

        {"input_spikes": [int, ...], "timesteps": int}  # timesteps defaults to 1

    Server → client (success)::

        {"output_spikes": [int, ...], "spike_count": int,
         "execution_time_us": float, "timesteps": int}

    Server → client (error)::

        {"error": str, "error_code": str}

    The connection stays open; the client sends frames at its own pace and
    receives one reply per frame.  Encoding (sensor → spikes) stays
    client-side so this endpoint is target-agnostic.
    """
    await websocket.accept()
    loop = asyncio.get_running_loop()
    try:
        while True:
            data = await websocket.receive_json()

            input_spikes = data.get("input_spikes")
            timesteps = int(data.get("timesteps", 1))

            if not isinstance(input_spikes, list):
                await websocket.send_json(
                    {"error": "input_spikes must be a list of int", "error_code": "INVALID_INPUT"}
                )
                continue

            backend = backend_instance
            if backend is None:
                await websocket.send_json(
                    {
                        "error": "Overlay not deployed. Call /deploy first.",
                        "error_code": "NOT_DEPLOYED",
                    }
                )
                continue

            try:
                result: dict[str, Any] = await loop.run_in_executor(
                    None,
                    functools.partial(backend.run, input_spikes=input_spikes, timesteps=timesteps),
                )
                output_spikes: list[int] = result.get("output_spikes", [])
                await websocket.send_json(
                    {
                        "output_spikes": output_spikes,
                        "spike_count": len(output_spikes),
                        "execution_time_us": result.get("execution_time_us"),
                        "timesteps": result.get("timesteps", timesteps),
                    }
                )
            except PynqRuntimeError as exc:
                await websocket.send_json(
                    {"error": str(exc), "error_code": getattr(exc, "error_code", "PYNQ_ERROR")}
                )
            except Exception as exc:
                logger.exception("Unexpected error in PYNQ stream")
                await websocket.send_json({"error": str(exc), "error_code": "INTERNAL_ERROR"})
    except WebSocketDisconnect:
        logger.debug("PYNQ stream client disconnected")


@router.get("/status", response_model=StatusResponse)
def get_status() -> StatusResponse:
    """Return the current backend lifecycle state."""
    loop_running = _loop_state is not None and is_loop_alive(_loop_state)
    if backend_instance is None:
        install_mode = str(read_install_status().get("installMode") or "unknown")
        return StatusResponse(
            state="not_initialised",
            runtime_mode=default_runtime_mode(),
            install_mode=install_mode,
            overlay_assets=current_overlay_assets(backend_instance),
            loop_running=loop_running,
        )
    install_mode = str(read_install_status().get("installMode") or "unknown")
    return StatusResponse(
        state=backend_instance.current_state,
        bitstream_path=backend_instance.bitstream_path,
        runtime_mode=backend_instance.runtime_mode,
        install_mode=install_mode,
        overlay_assets=backend_instance.overlay_asset_status.to_dict(),
        loop_running=loop_running,
    )


@router.post("/loop/start", response_model=LoopStartResponse)
def start_control_loop(request: LoopStartRequest) -> LoopStartResponse:
    """Start the pynq_zmq_service control loop.

    If ``ssh_host`` is supplied, SSH-execs the service on the remote board and
    returns the remote PID.  Otherwise launches the service as a local
    subprocess (the on-board pynq-agent path).
    """
    global _loop_state

    try:
        if request.ssh_host is not None:
            pid = start_loop_ssh(
                ssh_host=request.ssh_host,
                ssh_user=request.ssh_user,
                zmq_port=request.zmq_port,
                bitstream_path=request.bitstream_path,
                ssh_port=request.ssh_port,
                ssh_password=request.ssh_password,
                ssh_key_path=request.ssh_key_path,
                install_root=request.install_root,
            )
        else:
            pid = start_loop_local(
                zmq_port=request.zmq_port,
                bitstream_path=request.bitstream_path,
                install_root=request.install_root,
            )
    except LoopProcessError as exc:
        raise HTTPException(
            status_code=502,
            detail={"detail": str(exc), "error_code": exc.error_code},
        ) from exc
    except Exception as exc:
        logger.exception("Unexpected error starting control loop")
        raise HTTPException(status_code=500, detail=str(exc)) from exc

    _loop_state = LoopState(
        pid=pid,
        zmq_port=request.zmq_port,
        ssh_host=request.ssh_host,
        ssh_user=request.ssh_user,
        ssh_port=request.ssh_port,
        ssh_password=request.ssh_password,
        ssh_key_path=request.ssh_key_path,
        install_root=request.install_root,
    )
    return LoopStartResponse(status="running", pid=pid, zmq_port=request.zmq_port)


@router.post("/loop/stop", response_model=LoopStopResponse)
def stop_control_loop() -> LoopStopResponse:
    """Stop the running pynq_zmq_service control loop.

    Idempotent: returns ``not_running`` if no loop was started.
    """
    global _loop_state

    if _loop_state is None:
        return LoopStopResponse(status="not_running")

    state = _loop_state
    _loop_state = None

    try:
        if state.is_remote:
            stop_loop_ssh(state)
        else:
            stop_loop_local(state.pid)
    except LoopProcessError as exc:
        raise HTTPException(
            status_code=502,
            detail={"detail": str(exc), "error_code": exc.error_code},
        ) from exc
    except Exception as exc:
        logger.exception("Unexpected error stopping control loop")
        raise HTTPException(status_code=500, detail=str(exc)) from exc

    return LoopStopResponse(status="stopped")


@router.get("/preflight", response_model=PreflightResponse)
def get_preflight() -> PreflightResponse:
    """Return board-readiness for the real PYNQ hardware path."""
    return _build_preflight_response()


@router.post("/verify", response_model=VerifyResponse)
def verify_sitl(request: PynqVerifyRequest) -> VerifyResponse:
    """Run an optional Dream-Hand SITL verification pass against the PYNQ backend.

    If ``weights`` is provided in the request, a fresh backend is deployed before
    verification runs.  Otherwise the existing backend instance (from a previous
    ``/deploy`` call) is used.

    Returns a structured :class:`VerifyResponse` with per-step correctness and
    coarse timing signals, suitable for surfacing in the toolkit UX.
    """
    global backend_instance

    target_backend: PYNQBackend | None = None

    # Deploy a fresh backend when weights are supplied
    if request.weights is not None:
        try:
            register_map = validate_overlay_request(request, backend_instance)
            target_backend = PYNQBackend(
                bitstream_path=request.bitstream_path or DEFAULT_BITSTREAM,
            )
            target_backend.load_overlay()
            target_backend.configure(
                weights=request.weights,
                config=request.config or {},
                register_map=register_map,
                layers=request.layers,
            )
            backend_instance = target_backend
        except PynqRuntimeError as exc:
            logger.exception("PYNQ deploy failed during verify")
            raise pynq_error_to_http(exc, probe_cache=_hardware_probe_cache) from exc
        except Exception as exc:
            logger.exception("Unexpected error during verify deploy")
            raise HTTPException(status_code=500, detail=str(exc)) from exc
    else:
        target_backend = backend_instance

    if target_backend is None:
        raise HTTPException(
            status_code=400,
            detail="No backend deployed. Provide 'weights' in the request or call /deploy first.",
        )

    # Build optional custom stimulus cases
    sitl_cases = None
    if request.stimulus_cases:
        sitl_cases = [
            _SITLStimulusCase(
                label=c.label,
                input_spikes=c.input_spikes,
                expected_output_spikes=c.expected_output_spikes,
                timesteps=c.timesteps,
            )
            for c in request.stimulus_cases
        ]

    try:
        report = run_sitl_verification(
            target_backend,
            SITLVerificationConfig(stimulus_cases=sitl_cases),
        )
    except PynqRuntimeError as exc:
        logger.exception("PYNQ SITL verification failed")
        raise pynq_error_to_http(exc, probe_cache=_hardware_probe_cache) from exc
    except RuntimeError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except Exception as exc:
        logger.exception("Unexpected error during SITL verification")
        raise HTTPException(status_code=500, detail=str(exc)) from exc

    return VerifyResponse(
        passed=report.passed,
        total_cases=report.total_cases,
        passed_cases=report.passed_cases,
        mean_exec_us=report.mean_exec_us,
        max_exec_us=report.max_exec_us,
        summary=report.summary,
        steps=[
            VerifyStepResult(
                label=s.label,
                input_spikes=s.input_spikes,
                output_spikes=s.output_spikes,
                expected_output_spikes=s.expected_output_spikes,
                passed=s.passed,
                execution_time_us=s.execution_time_us,
            )
            for s in report.steps
        ],
    )
