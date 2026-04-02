"""Domain contracts for NeuroChip hardware deployment.

Converts neurochip_spec.md into enforceable contracts.

Source: Neurochip/neurochip_spec.md (NC-T1 through NC-DT1)
"""

from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, ConfigDict, field_validator, model_validator


class HardwareTargetContract(BaseModel):
    """Contract for hardware target profile (NC-T1)."""

    model_config = ConfigDict(frozen=True)

    target_id: Literal["teensy41", "loihi2", "akida", "spinnaker", "brainscales"]
    neuron_capacity: int
    supported_models: list[str]
    weight_bit_widths: list[int]
    memory_bytes: int
    power_envelope_mw: float
    io_interfaces: list[str]

    @field_validator("neuron_capacity")
    @classmethod
    def positive_capacity(cls, v: int) -> int:
        if v < 1:
            raise ValueError(f"Neuron capacity must be >= 1, got {v}")
        return v


class QuantizationContract(BaseModel):
    """Contract for weight quantization (NC-Q1, NC-Q2)."""

    model_config = ConfigDict(frozen=True)

    bit_width: int
    accuracy_metric: float  # 0-1 task-specific accuracy
    memory_reduction_factor: float

    @field_validator("bit_width")
    @classmethod
    def supported_widths(cls, v: int) -> int:
        if v not in {2, 4, 6, 8, 16, 32}:
            raise ValueError(
                f"Bit width {v} not in supported set {{2, 4, 6, 8, 16, 32}}."
            )
        return v

    @field_validator("accuracy_metric")
    @classmethod
    def valid_accuracy(cls, v: float) -> float:
        if v < 0 or v > 1:
            raise ValueError(f"Accuracy must be in [0, 1], got {v}")
        return v

    @field_validator("memory_reduction_factor")
    @classmethod
    def positive_reduction(cls, v: float) -> float:
        if v <= 0:
            raise ValueError(f"Memory reduction must be > 0, got {v}")
        return v


class FaultSweepContract(BaseModel):
    """Contract for fault injection analysis (NC-F1)."""

    model_config = ConfigDict(frozen=True)

    fault_type: Literal["dead_neuron", "stuck_at", "weight_noise"]
    max_fault_rate: float = 0.30
    n_seeds: int = 5

    @field_validator("max_fault_rate")
    @classmethod
    def within_range(cls, v: float) -> float:
        if v < 0 or v > 0.30:
            raise ValueError(f"Fault rate {v} outside [0, 0.30].")
        return v

    @field_validator("n_seeds")
    @classmethod
    def enough_seeds(cls, v: int) -> int:
        if v < 1:
            raise ValueError(f"Need >= 1 seed for confidence intervals, got {v}")
        return v


class PowerEstimateContract(BaseModel):
    """Contract for power estimation (NC-P1)."""

    model_config = ConfigDict(frozen=True)

    target_id: str
    total_energy_pj: float
    power_envelope_mw: float
    exceeds_envelope: bool

    @field_validator("total_energy_pj")
    @classmethod
    def positive_energy(cls, v: float) -> float:
        if v < 0:
            raise ValueError(f"Energy must be >= 0, got {v}")
        return v


class LatencyEstimateContract(BaseModel):
    """Contract for latency estimation (NC-P2)."""

    model_config = ConfigDict(frozen=True)

    target_id: str
    network_depth: int
    best_case_us: float
    typical_us: float
    worst_case_us: float

    @model_validator(mode="after")
    def ordered_estimates(self) -> LatencyEstimateContract:
        if not (self.best_case_us <= self.typical_us <= self.worst_case_us):
            raise ValueError(
                f"Latency estimates must be ordered: best ({self.best_case_us}) "
                f"<= typical ({self.typical_us}) <= worst ({self.worst_case_us})."
            )
        return self

    @field_validator("best_case_us", "typical_us", "worst_case_us")
    @classmethod
    def positive_latency(cls, v: float) -> float:
        if v <= 0:
            raise ValueError(f"Latency must be > 0, got {v}")
        return v


class TeensyFirmwareContract(BaseModel):
    """Contract for Teensy firmware generation (NC-FW1)."""

    model_config = ConfigDict(frozen=True)

    has_ino_file: bool
    has_network_params_h: bool
    has_lif_engine_h: bool
    has_readme: bool
    compiles_clean: bool

    @model_validator(mode="after")
    def all_artifacts_present(self) -> TeensyFirmwareContract:
        missing = []
        if not self.has_ino_file:
            missing.append(".ino file")
        if not self.has_network_params_h:
            missing.append("network_params.h")
        if not self.has_lif_engine_h:
            missing.append("lif_engine.h")
        if not self.has_readme:
            missing.append("README")
        if missing:
            raise ValueError(f"Firmware package missing: {', '.join(missing)}")
        return self
