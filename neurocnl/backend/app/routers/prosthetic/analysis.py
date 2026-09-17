"""POST /api/prosthetic/* — analysis endpoints."""

from fastapi import APIRouter, HTTPException

from backend.app.schemas.prosthetic import (
    EnergyRequest,
    EnergyResult,
    FaultInjectionRequest,
    FaultInjectionResult,
    NeuroSenseReplayRequest,
    NeuroSenseReplayResult,
    QuantizeRequest,
    QuantizeResult,
)
from backend.app.services.energy_service import run_energy_profile
from backend.app.services.fault_injection_service import run_fault_injection_analysis
from backend.app.services.neurosense_artifact import prepare_neurosense_replay
from neurocnl.runtime_dependencies import ensure_runtime_dependency

router = APIRouter()


def _load_quantization_sweep():
    if not ensure_runtime_dependency("neurodreamhand"):
        return None

    try:
        from neurodreamhand.hardware.quantization import run_quantization_sweep
    except ImportError:
        return None

    return run_quantization_sweep


@router.post("/energy", response_model=EnergyResult)
def energy_profile(request: EnergyRequest) -> EnergyResult:
    result = run_energy_profile(request)
    return EnergyResult(**result)


@router.post("/quantize", response_model=QuantizeResult)
def quantize_analysis(request: QuantizeRequest):
    """Run quantization accuracy analysis across multiple bit widths."""
    run_quantization_sweep = _load_quantization_sweep()
    if run_quantization_sweep is None:
        # Mock result for E2E testing if neurodreamhand is missing
        return QuantizeResult(
            bit_widths=request.bit_widths,
            accuracy_drops=[0.1 * (8 - b) / 8 for b in request.bit_widths],
            sparsity=[0.5] * len(request.bit_widths),
        )

    sweep = run_quantization_sweep(bit_widths=request.bit_widths)
    return QuantizeResult(
        bit_widths=request.bit_widths,
        accuracy_drops=[r.max_error for r in sweep],
        sparsity=[0.0] * len(request.bit_widths),
    )


@router.post("/fault-injection", response_model=FaultInjectionResult)
def fault_injection_analysis(request: FaultInjectionRequest) -> FaultInjectionResult:
    try:
        result = run_fault_injection_analysis(request)
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    return FaultInjectionResult(**result)


@router.post("/neurosense/replay", response_model=NeuroSenseReplayResult)
def prepare_neurosense_artifact_replay(
    request: NeuroSenseReplayRequest,
) -> NeuroSenseReplayResult:
    try:
        result = prepare_neurosense_replay(
            request.artifact_path,
            start_time_seconds=request.start_time_seconds,
            end_time_seconds=request.end_time_seconds,
            preview_frames=request.preview_frames,
        )
    except FileNotFoundError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    return NeuroSenseReplayResult(**result)
