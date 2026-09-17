"""Akida Runtime Artifact Contract — Neurochip-side defense-in-depth validation.

Mirrors the hardware limits defined in:
    neurocnl/neurocnl/contracts/akida_deployment_contract.py

Validates payloads against BrainChip Akida limits before artifact generation
proceeds, and defines the expected package structure for the Akida export
pipeline.

Cross-reference: Neurochip/neurochip/targets/akida.json is the hardware
profile source of truth.  Constants here must match.
"""

from __future__ import annotations

from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator

# ---------------------------------------------------------------------------
# Deployment mode
# ---------------------------------------------------------------------------

#: How the caller wants to handle the generated artifact.
#:
#: - ``scaffold``      – Generate and return the ZIP package only; SDK not required.
#: - ``on_device``     – Require SDK mapping to physical/simulator hardware;
#:                       fail with 502 if mapping cannot be established.
#: - ``remote_server`` – POST the generated ZIP to an external Neurochip host or
#:                       Akida runtime server at ``target_url``; return its response.
AkidaDeploymentMode = Literal["scaffold", "on_device", "remote_server"]

# ---------------------------------------------------------------------------
# Hardware limits (mirrored from NeuroCNL AkidaHardwareLimits)
# ---------------------------------------------------------------------------

MAX_NEURONS: int = 1_200_000
MAX_NEURONS_PER_NP: int = 256
CORE_COUNT: int = 80
MEMORY_BUDGET_KB: int = 8192
CLOCK_SPEED_MHZ: float = 100.0
POWER_ENVELOPE_MW: float = 500.0
PJ_PER_SPIKE_OP: float = 10.0
MAX_WEIGHT: float = 15.0
IO_PINS: int = 32
SUPPORTED_NEURON_MODELS: tuple[str, ...] = ("lif",)
SUPPORTED_WEIGHT_BIT_WIDTHS: tuple[int, ...] = (1, 2, 4)


def max_synapses_for_bit_width(bit_width: int) -> int:
    """Return the maximum synapse count that fits in Akida memory.

    Formula (matches NeuroCNL AkidaHardwareLimits.max_synapses_for_bit_width):
        neuron_bytes = MAX_NEURONS_PER_NP * CORE_COUNT * 6
        available    = MEMORY_BUDGET_KB * 1024 - neuron_bytes
        max_synapses = available // (bit_width/8 + 8)
    """
    budget_bytes = MEMORY_BUDGET_KB * 1024
    neuron_bytes = MAX_NEURONS_PER_NP * CORE_COUNT * 6
    available = budget_bytes - neuron_bytes
    if available <= 0:
        return 0
    bytes_per_synapse = (bit_width / 8) + 8
    return int(available / bytes_per_synapse)


# ---------------------------------------------------------------------------
# Payload validation contract (pre-generation gate)
# ---------------------------------------------------------------------------


class AkidaNetworkPayloadContract(BaseModel):
    """Validates a NetworkInput payload before Akida artifact generation.

    Enforces the same limits as the NeuroCNL Akida deployment contract to
    ensure no invalid payload reaches the Akida generator.
    """

    model_config = ConfigDict(frozen=True)

    num_neurons: int = Field(..., gt=0)
    num_synapses: int = Field(..., ge=0)
    neuron_model: str = Field(...)
    weight_bit_width: int = Field(..., gt=0)
    network_depth: int = Field(..., ge=1)

    @model_validator(mode="after")
    def validate_akida_limits(self) -> AkidaNetworkPayloadContract:
        """Enforce BrainChip Akida hardware limits."""
        if self.num_neurons > MAX_NEURONS:
            raise ValueError(
                f"num_neurons ({self.num_neurons}) exceeds Akida max ({MAX_NEURONS:,})"
            )

        if self.neuron_model.lower() not in SUPPORTED_NEURON_MODELS:
            raise ValueError(
                f"neuron_model '{self.neuron_model}' not supported by Akida. "
                f"Supported: {', '.join(SUPPORTED_NEURON_MODELS)}"
            )

        if self.weight_bit_width not in SUPPORTED_WEIGHT_BIT_WIDTHS:
            raise ValueError(
                f"weight_bit_width ({self.weight_bit_width}) not in supported "
                f"set {SUPPORTED_WEIGHT_BIT_WIDTHS}"
            )

        max_syn = max_synapses_for_bit_width(self.weight_bit_width)
        if self.num_synapses > max_syn:
            raise ValueError(
                f"num_synapses ({self.num_synapses}) exceeds Akida max "
                f"({max_syn}) at {self.weight_bit_width}-bit weights"
            )

        # Memory check
        weight_bytes = self.num_synapses * (self.weight_bit_width / 8)
        neuron_bytes = self.num_neurons * 6
        index_bytes = self.num_synapses * 8
        memory_kb = (weight_bytes + neuron_bytes + index_bytes) / 1024
        if memory_kb > MEMORY_BUDGET_KB:
            raise ValueError(
                f"Estimated memory ({memory_kb:.1f} KB) exceeds Akida budget "
                f"({MEMORY_BUDGET_KB:,} KB)"
            )

        return self


class AkidaMappedNetworkPayloadContract(BaseModel):
    """Validates an AkidaMappedNetwork-shaped payload on the Neurochip side.

    This is the defense-in-depth contract for payloads arriving from
    the NeuroCNL shared mapper.  Neurochip does not depend on the NeuroCNL
    Python package, so this model duplicates the essential validations.
    """

    model_config = ConfigDict(frozen=True)

    akida_version: str = Field(...)
    populations: list[dict[str, Any]] = Field(...)
    connections: list[dict[str, Any]] = Field(...)

    @model_validator(mode="after")
    def validate_mapped_limits(self) -> AkidaMappedNetworkPayloadContract:
        """Enforce Akida hardware limits on mapped network."""
        # Total neuron count
        total_neurons = 0
        for pop in self.populations:
            size = pop.get("size", 0)
            if size > MAX_NEURONS_PER_NP:
                raise ValueError(
                    f"Population '{pop.get('id', '?')}' has {size} neurons, "
                    f"exceeds Akida NP max ({MAX_NEURONS_PER_NP})"
                )
            total_neurons += size

        if total_neurons > MAX_NEURONS:
            raise ValueError(
                f"Total neurons ({total_neurons:,}) exceeds Akida max ({MAX_NEURONS:,})"
            )

        # Weight bounds
        for conn in self.connections:
            weight = conn.get("weight")
            if weight is not None and abs(weight) > MAX_WEIGHT:
                raise ValueError(f"Connection weight ({weight}) exceeds Akida max ({MAX_WEIGHT})")

        return self


class AkidaEnvironmentChecks(BaseModel):
    """Structured diagnostics for the local Akida runtime environment."""

    model_config = ConfigDict(frozen=True)

    host_supported: bool
    python_supported: bool
    tensorflow_available: bool
    cnn2snn_available: bool
    akida_models_available: bool
    recommended_runtime: Literal["local_sdk", "remote_sdk", "simulator_only"] = Field(
        default="local_sdk"
    )
    # The installed SDK version, or "" when akida is not importable. Every other
    # field here is a boolean, so a version skew between the host and whatever
    # wrote a bundle's `.fbz` was invisible in every diagnostic the app has --
    # and that skew is exactly what makes `akida.Model(path)` refuse a bundle.
    akida_version: str = ""


class AkidaRuntimeStatusContract(BaseModel):
    """Typed status payload shared by the Akida runtime routes."""

    model_config = ConfigDict(frozen=True)

    state: str
    sdk_available: bool
    sdk_status: str
    sdk_issues: list[str] = Field(default_factory=list)
    model_summary: dict[str, Any] | None = None
    runtime_target: str = "unknown"
    device_info: str | None = None
    sdk_issue_detail: str | None = None
    environment_checks: AkidaEnvironmentChecks


# ---------------------------------------------------------------------------
# Required artifact files
# ---------------------------------------------------------------------------

REQUIRED_ARTIFACT_FILES: tuple[str, ...] = (
    "akida_deploy/model.json",
    "akida_deploy/weights.bin",
    "akida_deploy/manifest.json",
    "akida_deploy/README.md",
)
