"""Teensy Deployment Contract — shared spec for NeuroCNL-to-Teensy deployability.

Defines:
- Hardware limits for Teensy 4.1
- Supported neuron/topology subset
- Timestep and execution assumptions
- I/O mapping shape constraints
- Fail-closed deployability verdicts with documented rejection reasons

This contract is the authoritative source of truth referenced by:
- NeuroCNL planner (plan_teensy_deployability)
- NeuroCNL validators (issue 02)
- Neurochip firmware generator (issue 03-04)
- Toolkit UI readiness verdicts (issue 05)

Cross-reference: Neurochip/neurochip/contracts/teensy_deployment_contract.py
mirrors these limits for defense-in-depth validation.
"""

from __future__ import annotations

from enum import StrEnum
from typing import Any

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

CONTRACT_VERSION: str = "1.0.0"

# ---------------------------------------------------------------------------
# Hardware limits — derived from Neurochip/neurochip/targets/teensy41.json
# ---------------------------------------------------------------------------


class TeensyHardwareLimits(BaseModel):
    """Frozen hardware limits for Teensy 4.1.

    Constants are sourced from the Neurochip hardware profile
    ``Neurochip/neurochip/targets/teensy41.json``.  Any drift between
    this contract and the JSON profile should be caught by property-based
    tests.
    """

    model_config = ConfigDict(frozen=True)

    MAX_NEURONS: int = 4096
    MAX_IO_PINS: int = 55
    MEMORY_BUDGET_KB: int = 1024
    CLOCK_SPEED_MHZ: float = 600.0
    POWER_ENVELOPE_MW: float = 100.0
    PJ_PER_SPIKE_OP: float = 500.0
    TIMESTEP_SECONDS: float = 0.001
    SUPPORTED_NEURON_MODELS: tuple[str, ...] = ("LIF",)
    SUPPORTED_WEIGHT_BIT_WIDTHS: tuple[int, ...] = (8, 16, 32)

    def max_synapses_for_bit_width(self, bit_width: int) -> int:
        """Return the maximum number of synapses that fit in memory.

        Memory formula (matches Neurochip constraint_analyzer.py):
            weight_bytes  = num_synapses * (bit_width / 8)
            neuron_bytes  = MAX_NEURONS * 6          # voltage + refractory
            index_bytes   = num_synapses * 8          # pre + post int indices
            total         = weight_bytes + neuron_bytes + index_bytes

        Solving for num_synapses:
            num_synapses  = (budget_bytes - neuron_bytes) / (bit_width/8 + 8)
        """
        budget_bytes = self.MEMORY_BUDGET_KB * 1024
        neuron_bytes = self.MAX_NEURONS * 6
        available = budget_bytes - neuron_bytes
        if available <= 0:
            return 0
        bytes_per_synapse = (bit_width / 8) + 8
        return int(available / bytes_per_synapse)

    @property
    def MAX_SYNAPSES_FLOAT32(self) -> int:
        """Conservative worst-case synapse limit (32-bit weights)."""
        return self.max_synapses_for_bit_width(32)

    @property
    def MAX_SYNAPSES_INT8(self) -> int:
        """Best-case synapse limit (8-bit weights)."""
        return self.max_synapses_for_bit_width(8)


# Singleton instance for convenient import
TEENSY_LIMITS = TeensyHardwareLimits()


# ---------------------------------------------------------------------------
# Topology constraints
# ---------------------------------------------------------------------------


class TeensyTopologyConstraints(BaseModel):
    """Frozen set of topology restrictions for Teensy deployment.

    Teensy firmware uses a simple feedforward LIF engine with static
    weights.  It does not support:
    - Recurrent (feedback) connections
    - Lateral inhibition / spatial connectivity
    - On-chip learning rules (STDP, PES, BCM, Oja)
    - Axonal delays (no delay buffer in firmware)
    - Multi-compartment neurons
    """

    model_config = ConfigDict(frozen=True)

    allow_recurrent: bool = False
    allow_lateral_inhibition: bool = False
    allow_learning_rules: bool = False
    allow_axonal_delays: bool = False
    allow_multi_compartment: bool = False
    allowed_neuron_models: tuple[str, ...] = ("LIF",)


TEENSY_TOPOLOGY = TeensyTopologyConstraints()


# ---------------------------------------------------------------------------
# I/O mapping
# ---------------------------------------------------------------------------


class TeensyIOMapping(BaseModel):
    """Validated I/O pin-to-population mapping for Teensy deployment.

    Convention (matches Neurochip teensy_generator.py):
    - Input population = first population in network ordering
    - Output population = last population in network ordering
    - Pins are Teensy 4.1 GPIO pin numbers [0, 54]
    """

    model_config = ConfigDict(frozen=True)

    input_population: str = Field(..., min_length=1)
    output_population: str = Field(..., min_length=1)
    input_pins: list[int] = Field(default_factory=list)
    output_pins: list[int] = Field(default_factory=list)

    @field_validator("input_pins", "output_pins")
    @classmethod
    def validate_pin_range(cls, pins: list[int]) -> list[int]:
        """All GPIO pins must be in [0, MAX_IO_PINS - 1]."""
        max_pin = TEENSY_LIMITS.MAX_IO_PINS - 1
        for pin in pins:
            if pin < 0 or pin > max_pin:
                raise ValueError(f"GPIO pin {pin} out of range [0, {max_pin}]")
        return pins

    @model_validator(mode="after")
    def validate_pin_constraints(self) -> TeensyIOMapping:
        """Validate pin uniqueness and disjointness."""
        all_pins = self.input_pins + self.output_pins
        if len(all_pins) > TEENSY_LIMITS.MAX_IO_PINS:
            raise ValueError(
                f"Total pin count ({len(all_pins)}) exceeds "
                f"Teensy 4.1 limit of {TEENSY_LIMITS.MAX_IO_PINS}"
            )
        if len(set(self.input_pins)) != len(self.input_pins):
            raise ValueError("Duplicate input pins detected")
        if len(set(self.output_pins)) != len(self.output_pins):
            raise ValueError("Duplicate output pins detected")
        overlap = set(self.input_pins) & set(self.output_pins)
        if overlap:
            raise ValueError(f"Input and output pins overlap: {sorted(overlap)}")
        return self


# ---------------------------------------------------------------------------
# Deployability verdict and rejection reasons
# ---------------------------------------------------------------------------


class TeensyDeployabilityVerdict(StrEnum):
    """Fail-closed deployability status for Teensy target."""

    DEPLOYABLE = "deployable"
    DEPLOYABLE_WITH_WARNINGS = "deployable_with_warnings"
    NOT_DEPLOYABLE = "not_deployable"


class TeensyRejectionReason(StrEnum):
    """Documented rejection codes for Teensy deployment failures."""

    EXCEEDS_NEURON_CAPACITY = "exceeds_neuron_capacity"
    EXCEEDS_SYNAPSE_CAPACITY = "exceeds_synapse_capacity"
    EXCEEDS_MEMORY_BUDGET = "exceeds_memory_budget"
    UNSUPPORTED_NEURON_MODEL = "unsupported_neuron_model"
    UNSUPPORTED_LEARNING_RULE = "unsupported_learning_rule"
    UNSUPPORTED_TOPOLOGY = "unsupported_topology"
    UNSUPPORTED_AXONAL_DELAY = "unsupported_axonal_delay"
    IO_PIN_OVERFLOW = "io_pin_overflow"
    IO_SHAPE_MISMATCH = "io_shape_mismatch"
    TIMESTEP_INCOMPATIBLE = "timestep_incompatible"
    WEIGHT_BIT_WIDTH_UNSUPPORTED = "weight_bit_width_unsupported"


# Human-readable messages per rejection reason
REJECTION_MESSAGES: dict[TeensyRejectionReason, str] = {
    TeensyRejectionReason.EXCEEDS_NEURON_CAPACITY: (
        f"Network exceeds neuron capacity; Teensy 4.1 supports max {TEENSY_LIMITS.MAX_NEURONS}"
    ),
    TeensyRejectionReason.EXCEEDS_SYNAPSE_CAPACITY: (
        "Network exceeds synapse capacity for the selected weight bit-width"
    ),
    TeensyRejectionReason.EXCEEDS_MEMORY_BUDGET: (
        f"Estimated memory exceeds Teensy 4.1 budget of {TEENSY_LIMITS.MEMORY_BUDGET_KB} KB"
    ),
    TeensyRejectionReason.UNSUPPORTED_NEURON_MODEL: (
        f"Unsupported neuron model; only {', '.join(TEENSY_LIMITS.SUPPORTED_NEURON_MODELS)} allowed"
    ),
    TeensyRejectionReason.UNSUPPORTED_LEARNING_RULE: (
        "Learning rules not supported; Teensy uses static synapses only"
    ),
    TeensyRejectionReason.UNSUPPORTED_TOPOLOGY: (
        "Complex topology not supported on Teensy embedded target"
    ),
    TeensyRejectionReason.UNSUPPORTED_AXONAL_DELAY: (
        "Axonal delays not supported on Teensy embedded target"
    ),
    TeensyRejectionReason.IO_PIN_OVERFLOW: (
        f"I/O mapping exceeds available pins; Teensy 4.1 has {TEENSY_LIMITS.MAX_IO_PINS}"
    ),
    TeensyRejectionReason.IO_SHAPE_MISMATCH: (
        f"Input/output population size exceeds available I/O pins ({TEENSY_LIMITS.MAX_IO_PINS})"
    ),
    TeensyRejectionReason.TIMESTEP_INCOMPATIBLE: (
        f"Declared timestep is finer than Teensy timing resolution "
        f"{TEENSY_LIMITS.TIMESTEP_SECONDS}s"
    ),
    TeensyRejectionReason.WEIGHT_BIT_WIDTH_UNSUPPORTED: (
        f"Weight bit-width not in supported set {set(TEENSY_LIMITS.SUPPORTED_WEIGHT_BIT_WIDTHS)}"
    ),
}


# ---------------------------------------------------------------------------
# Deployment result
# ---------------------------------------------------------------------------


class TeensyDeploymentResult(BaseModel):
    """Fail-closed deployment verdict for a network targeting Teensy 4.1.

    Invariant: verdict is DEPLOYABLE (or DEPLOYABLE_WITH_WARNINGS) if and
    only if ``rejections`` is empty.  This is enforced by the model validator.
    """

    model_config = ConfigDict(frozen=True)

    verdict: TeensyDeployabilityVerdict
    rejections: list[TeensyRejectionReason] = Field(default_factory=list)
    warnings: list[str] = Field(default_factory=list)
    network_summary: dict[str, Any] = Field(default_factory=dict)

    @model_validator(mode="after")
    def validate_fail_closed(self) -> TeensyDeploymentResult:
        """Enforce fail-closed invariant.

        - If any rejections exist → verdict MUST be NOT_DEPLOYABLE.
        - If no rejections exist → verdict MUST NOT be NOT_DEPLOYABLE.
        """
        has_rejections = len(self.rejections) > 0
        if has_rejections and self.verdict != TeensyDeployabilityVerdict.NOT_DEPLOYABLE:
            raise ValueError(
                f"Fail-closed violation: {len(self.rejections)} rejection(s) present "
                f"but verdict is '{self.verdict}' instead of 'not_deployable'"
            )
        if not has_rejections and self.verdict == TeensyDeployabilityVerdict.NOT_DEPLOYABLE:
            raise ValueError(
                "Fail-closed violation: verdict is 'not_deployable' but no rejections are listed"
            )
        return self
