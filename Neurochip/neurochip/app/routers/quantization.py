import json
from json import JSONDecodeError

from fastapi import APIRouter, HTTPException, Query, Request, Response
from pydantic import ValidationError as PydanticValidationError

from neurochip.contracts.quantization_contracts import QuantizationResult

from ...contracts.deployment_contracts import TargetDevice
from ...contracts.quantization_contracts import QuantizationConfig
from ..schemas.estimation import NetworkInput
from ..services import quantizer

router = APIRouter(prefix="/api/neurochip/quantize", tags=["quantization"])


def _resolve_target_device(target_device: str) -> TargetDevice:
    for member in TargetDevice:
        if member.value == target_device or member.name.lower() == target_device.lower():
            return member
    raise HTTPException(
        status_code=422,
        detail={
            "error": "unknown_target",
            "message": f"Target {target_device!r} is not a recognized NeuroChip target.",
            "hint": f"Valid targets: {[member.value for member in TargetDevice]}",
        },
    )


def _check_bit_width(bit_width: int, target_device: str) -> None:
    """Raise HTTP 422 with a clear message if bit_width is unsupported for the device."""
    device_enum = _resolve_target_device(target_device)
    supported = QuantizationConfig.SUPPORTED_BIT_WIDTHS.get(device_enum)
    if supported and bit_width not in supported:
        raise HTTPException(
            status_code=422,
            detail=(
                f"Bit-width {bit_width} is not supported by {device_enum.value}. "
                f"Supported bit-widths for this device: {supported}."
            ),
        )


@router.post("", response_model=QuantizationResult)
def quantize(
    request: Request,
    response: Response,
    network: NetworkInput,
    bit_width: int,
    target_device: str,
    baseline_accuracy: float = 0.98,
    layer_configs: str | None = Query(None),
) -> QuantizationResult:
    """Run quantization for a single bit width and estimate accuracy impact."""
    _check_bit_width(bit_width, target_device)
    _resolve_target_device(target_device)

    configs = None
    if layer_configs:
        try:
            configs = json.loads(layer_configs)
        except JSONDecodeError:
            raise HTTPException(status_code=422, detail="Invalid layer_configs JSON")

    try:
        return quantizer.quantize(network, bit_width, target_device, baseline_accuracy, configs)
    except PydanticValidationError as exc:
        # Safety net: surface any contract violation from the service layer as 422
        raise HTTPException(status_code=422, detail=str(exc)) from exc


@router.post("/batch", response_model=list[QuantizationResult])
def quantize_batch(
    request: Request,
    response: Response,
    network: NetworkInput,
    target_device: str,
    bit_widths: list[int] | None = Query(None),
    baseline_accuracy: float = 0.98,
    layer_configs: str | None = Query(None),
) -> list[QuantizationResult]:
    """Run batch quantization across multiple bit widths."""
    configs = None
    if layer_configs:
        try:
            configs = json.loads(layer_configs)
        except JSONDecodeError:
            raise HTTPException(status_code=422, detail="Invalid layer_configs JSON")

    if bit_widths is None:
        device_enum = _resolve_target_device(target_device)
        bit_widths = QuantizationConfig.SUPPORTED_BIT_WIDTHS.get(device_enum, [8, 16, 32])

    try:
        return quantizer.quantize_batch(
            network, target_device, bit_widths, baseline_accuracy, configs
        )
    except PydanticValidationError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc


@router.post("/configure", response_model=QuantizationConfig)
def configure_quantization(
    request: Request, response: Response, config: QuantizationConfig
) -> QuantizationConfig:
    """Validate and set quantization configuration."""
    return config
