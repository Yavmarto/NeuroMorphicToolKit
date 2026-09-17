from typing import ClassVar

from pydantic import BaseModel, Field, model_validator

from .deployment_contracts import TargetDevice

__all__ = ["QuantizationConfig", "QuantizationResult", "TargetDevice"]


class QuantizationConfig(BaseModel):
    """
    Contract for quantization configurations, including bit-width, scaling factor, and rounding mode.
    Enforces target-specific bit-width invariants.
    """

    target_device: TargetDevice
    bit_width: int = Field(
        ..., ge=1, le=32, description="Quantization bit-width, must be between 1 and 32."
    )
    scaling_factor: float = Field(
        ..., gt=0, description="Scaling factor used for quantization, must be positive."
    )
    rounding_mode: str = Field(
        ..., description="Mode used for rounding (e.g., 'floor', 'ceil', 'nearest')."
    )
    layer_configs: dict[str, int] | None = Field(
        default=None, description="Optional per-layer bit-width overrides."
    )

    SUPPORTED_BIT_WIDTHS: ClassVar[dict[TargetDevice, list[int]]] = {
        TargetDevice.TEENSY_41: [8, 16, 32],
        TargetDevice.LOIHI_2: [1, 2, 4, 8],
        TargetDevice.AKIDA: [1, 2, 4],
        TargetDevice.SPINNAKER: [16, 32],
        TargetDevice.BRAINSCALES: [4, 6],
        TargetDevice.LAVA: [8, 16, 32],
        TargetDevice.NEUROML: [8, 16, 32],
        TargetDevice.PYNQ_Z2: [4, 8],
    }

    @model_validator(mode="after")
    def validate_bit_width_compatibility(self) -> "QuantizationConfig":
        """
        Enforce invariant: bit_width must be supported by the target device.
        """
        supported = self.SUPPORTED_BIT_WIDTHS.get(self.target_device)
        if supported and self.bit_width not in supported:
            raise ValueError(
                f"Bit-width {self.bit_width} is not supported by {self.target_device.value}. "
                f"Supported bit-widths: {supported}"
            )
        return self


class QuantizationResult(BaseModel):
    """
    Contract for quantization results, enforcing accuracy loss invariants.
    """

    target_device: TargetDevice
    bit_width: int
    accuracy: float
    accuracy_loss_pct: float = Field(
        ..., le=25.0, description="Accuracy loss percentage vs float32, must be <= 25%."
    )
    memory_size_kb: float
    memory_reduction_factor: float
    spike_fidelity: float
    power_estimate_pj: float
    method: str | None = None
    is_estimate: bool = False
    accuracy_note: str | None = None

    @model_validator(mode="after")
    def validate_bit_width_compatibility(self) -> "QuantizationResult":
        """
        Enforce invariant: bit_width must be supported by the target device.
        """
        supported = QuantizationConfig.SUPPORTED_BIT_WIDTHS.get(self.target_device)
        if supported and self.bit_width not in supported:
            raise ValueError(
                f"Resulting bit-width {self.bit_width} is not supported by {self.target_device.value}."
            )
        return self
