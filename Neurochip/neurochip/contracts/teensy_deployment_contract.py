"""Teensy Deployment Contract — Neurochip-side defense-in-depth validation.

Mirrors the hardware limits defined in the NeuroCNL contract:
    neurocnl/neurocnl/contracts/teensy_deployment_contract.py

Any NetworkInput payload destined for firmware generation is validated
against these limits before code-gen proceeds, even if the NeuroCNL
planner already approved it (belt-and-suspenders).

Cross-reference: Neurochip/neurochip/targets/teensy41.json is the
hardware profile source of truth.  Constants here must match.
"""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

CONTRACT_VERSION: str = "1.0.0"

# ---------------------------------------------------------------------------
# Hardware limits (mirrored from NeuroCNL TeensyHardwareLimits)
# ---------------------------------------------------------------------------

MAX_NEURONS: int = 4096
MAX_IO_PINS: int = 55
MEMORY_BUDGET_KB: int = 1024
SUPPORTED_NEURON_MODELS: tuple[str, ...] = ("LIF",)
SUPPORTED_WEIGHT_BIT_WIDTHS: tuple[int, ...] = (8, 16, 32)


def max_synapses_for_bit_width(bit_width: int) -> int:
    """Return the maximum synapse count that fits in Teensy 4.1 memory.

    Formula (matches NeuroCNL and constraint_analyzer.py):
        available = MEMORY_BUDGET_KB * 1024 - MAX_NEURONS * 6
        bytes_per_synapse = bit_width/8 + 8
        max_synapses = available // bytes_per_synapse
    """
    budget_bytes = MEMORY_BUDGET_KB * 1024
    neuron_bytes = MAX_NEURONS * 6
    available = budget_bytes - neuron_bytes
    if available <= 0:
        return 0
    bytes_per_synapse = (bit_width / 8) + 8
    return int(available / bytes_per_synapse)


# ---------------------------------------------------------------------------
# Payload validation contract
# ---------------------------------------------------------------------------


class TeensyNetworkPayloadContract(BaseModel):
    """Validates a NetworkInput payload before Teensy firmware generation.

    Enforces the same limits as the NeuroCNL deployment contract to
    ensure no invalid payload reaches the firmware generator.
    """

    model_config = ConfigDict(frozen=True)

    num_neurons: int = Field(..., gt=0)
    num_synapses: int = Field(..., ge=0)
    neuron_model: str = Field(...)
    weight_bit_width: int = Field(..., gt=0)
    network_depth: int = Field(..., ge=1)

    @field_validator("neuron_model")
    @classmethod
    def normalize_neuron_model(cls, v: str) -> str:
        return v.upper()

    @model_validator(mode="after")
    def validate_teensy_limits(self) -> TeensyNetworkPayloadContract:
        """Enforce Teensy 4.1 hardware limits."""
        if self.num_neurons > MAX_NEURONS:
            raise ValueError(
                f"num_neurons ({self.num_neurons}) exceeds Teensy 4.1 max ({MAX_NEURONS})"
            )

        if self.neuron_model not in SUPPORTED_NEURON_MODELS:
            raise ValueError(
                f"neuron_model '{self.neuron_model}' not supported by Teensy 4.1. "
                f"Supported: {', '.join(SUPPORTED_NEURON_MODELS)}"
            )

        if self.weight_bit_width not in SUPPORTED_WEIGHT_BIT_WIDTHS:
            raise ValueError(
                f"weight_bit_width ({self.weight_bit_width}) not in supported set "
                f"{SUPPORTED_WEIGHT_BIT_WIDTHS}"
            )

        max_syn = max_synapses_for_bit_width(self.weight_bit_width)
        if self.num_synapses > max_syn:
            raise ValueError(
                f"num_synapses ({self.num_synapses}) exceeds Teensy 4.1 max "
                f"({max_syn}) at {self.weight_bit_width}-bit weights"
            )

        # Memory check
        weight_bytes = self.num_synapses * (self.weight_bit_width / 8)
        neuron_bytes = self.num_neurons * 6
        index_bytes = self.num_synapses * 8
        memory_kb = (weight_bytes + neuron_bytes + index_bytes) / 1024
        if memory_kb > MEMORY_BUDGET_KB:
            raise ValueError(
                f"Estimated memory ({memory_kb:.1f} KB) exceeds Teensy 4.1 budget "
                f"({MEMORY_BUDGET_KB} KB)"
            )

        return self
