"""PYNQ Deployment Contract — shared spec for NeuroCNL-to-PYNQ exportability.

Defines:
- Hardware limits for PYNQ Z2 (Zynq-7000)
- Supported neuron/topology subset
- Quantization constraints (int8)
- Two-tier verdict model: Exportable vs Deployable
- Fail-closed exportability verdicts with documented rejection reasons

This contract is the authoritative source of truth referenced by:
- NeuroCNL planner (plan_pynq_exportability)
- NeuroCNL PYNQ exporter (export/pynq_exporter.py)
- Neurochip PYNQ backend (issue 11)
- Toolkit UI readiness verdicts (issue 05)

Cross-reference: Neurochip/neurochip/targets/pynq_z2.json
mirrors these limits for defense-in-depth validation.

Semantic distinction:
- **Exportable**: toolkit can quantize weights and produce overlay_config.json +
  weights.bin offline.  No board required.
- **Deployable**: overlay artifacts can be loaded and run on real PYNQ hardware.
  Requires runtime board connectivity (resolved by issue #11).
"""

from __future__ import annotations

import json
from enum import StrEnum
from pathlib import Path
from typing import Any

from pydantic import BaseModel, ConfigDict, Field, model_validator

#: Fallback used only when the Neurochip hardware manifest is not on disk (for
#: example a neurocnl-only checkout).  It must stay in step with
#: ``Neurochip/hardware/pynq_z2/overlay_manifest.json``, which is the real
#: source of truth and is loaded in preference to this.
DEFAULT_OVERLAY_MANIFEST: dict[str, Any] = {
    "overlay_id": "snn_overlay_v2",
    "overlay_version": "2.0.0",
    "target_part": "xc7z020clg400-1",
    "supported_neuron_models": ["LIF"],
    "supported_weight_bit_widths": [8],
    "max_neurons": 4096,
    "max_neurons_per_layer": 1024,
    "max_synapses": 262144,
    "max_populations": 4,
    "max_layers": 4,
    "dma_ip_name": "axi_dma_0",
    "snn_ip_name": "snn_engine_0",
    # Offsets are assigned by Vitis HLS and read back out of the built `.hwh`;
    # overlay-v1's hand-written map disagreed with its own bitstream on every
    # scalar argument, so there are deliberately no guesses here.
    "register_map": {
        "resolved_from_hwh": False,
        "base_address": None,
        "control_reg_offset": None,
        "global_interrupt_enable_offset": None,
        "interrupt_enable_offset": None,
        "interrupt_status_offset": None,
        "weights_ptr_offset": None,
        "layer_config_ptr_offset": None,
        "layer_count_offset": None,
        "weight_count_offset": None,
        "timestep_count_offset": None,
    },
    "weight_layout": {
        "format": "int8_dense_row_major_ddr",
        "storage": "dma_ddr",
        "element_bytes": 1,
        "max_entries": 262144,
        "matrix_order": "post_by_pre",
    },
    "layer_config_layout": {
        "format": "uint32_words",
        "storage": "dma_ddr",
        "words_per_layer": 8,
        "max_layers": 4,
        "fields": {
            "input_size": 0,
            "output_size": 1,
            "weight_offset": 2,
            "threshold": 3,
            "leak_shift": 4,
            "refractory": 5,
        },
    },
}


def _overlay_manifest_path() -> Path:
    return (
        Path(__file__).resolve().parents[3]
        / "Neurochip"
        / "hardware"
        / "pynq_z2"
        / "overlay_manifest.json"
    )


def _load_overlay_manifest() -> dict[str, Any]:
    path = _overlay_manifest_path()
    if not path.exists():
        return dict(DEFAULT_OVERLAY_MANIFEST)
    payload = json.loads(path.read_text(encoding="utf-8"))
    return payload if isinstance(payload, dict) else dict(DEFAULT_OVERLAY_MANIFEST)


_OVERLAY = _load_overlay_manifest()

# ---------------------------------------------------------------------------
# Hardware limits — derived from Neurochip/neurochip/targets/pynq_z2.json
# ---------------------------------------------------------------------------


class PynqHardwareLimits(BaseModel):
    """Frozen hardware limits for PYNQ Z2 (Zynq-7000).

    Constants are sourced from the Neurochip hardware profile
    ``Neurochip/neurochip/targets/pynq_z2.json``.  Any drift between
    this contract and the JSON profile should be caught by property-based
    tests.
    """

    model_config = ConfigDict(frozen=True)

    OVERLAY_ID: str = str(_OVERLAY["overlay_id"])
    OVERLAY_VERSION: str = str(_OVERLAY["overlay_version"])
    TARGET_PART: str = str(_OVERLAY["target_part"])
    MAX_NEURONS: int = int(_OVERLAY["max_neurons"])
    MAX_NEURONS_PER_LAYER: int = int(_OVERLAY.get("max_neurons_per_layer", 1024))
    MAX_SYNAPSES: int = int(_OVERLAY["max_synapses"])
    MAX_POPULATIONS: int = int(_OVERLAY["max_populations"])
    MAX_LAYERS: int = int(_OVERLAY.get("max_layers", _OVERLAY["max_populations"]))
    #: The on-chip weight cache plus per-neuron state.
    MEMORY_BUDGET_KB: int = 320
    #: Per-neuron on-chip state: int32 membrane + uint8 refractory counter.
    NEURON_STATE_BYTES: int = 5
    CORE_COUNT: int = 2
    CLOCK_SPEED_MHZ: float = 650.0
    POWER_ENVELOPE_MW: float = 3000.0
    PJ_PER_SPIKE_OP: float = 50.0
    TIMESTEP_SECONDS: float = 0.001
    SUPPORTED_NEURON_MODELS: tuple[str, ...] = tuple(_OVERLAY["supported_neuron_models"])
    SUPPORTED_WEIGHT_BIT_WIDTHS: tuple[int, ...] = tuple(_OVERLAY["supported_weight_bit_widths"])
    IO_PINS: int = 40

    def estimate_memory_kb(self, *, num_neurons: int, num_synapses: int, bit_width: int) -> float:
        """Estimate on-chip memory for a network, in KB.

        A dense row-major matrix stores no pre/post index pairs, so — unlike
        the v1 estimate — nothing is charged for them.
        """
        weight_bytes = num_synapses * (bit_width / 8)
        neuron_bytes = num_neurons * self.NEURON_STATE_BYTES
        return (weight_bytes + neuron_bytes) / 1024

    def max_synapses_for_bit_width(self, bit_width: int) -> int:
        """Return how many weights of this width fit in the weight cache.

        The cache is sized in bytes, so a narrower weight genuinely buys more
        synapses. v1's version carried this docstring but returned the same
        constant whatever width it was asked about.
        """
        if bit_width not in self.SUPPORTED_WEIGHT_BIT_WIDTHS:
            return 0
        return (self.MAX_SYNAPSES * 8) // bit_width

    @property
    def MAX_SYNAPSES_INT4(self) -> int:
        """Synapse limit for unsupported 4-bit weights."""
        return self.max_synapses_for_bit_width(4)

    @property
    def MAX_SYNAPSES_INT8(self) -> int:
        """Synapse limit for 8-bit weights."""
        return self.max_synapses_for_bit_width(8)

    @property
    def MAX_SYNAPSES_INT16(self) -> int:
        """Synapse limit for unsupported 16-bit weights."""
        return self.max_synapses_for_bit_width(16)


# Singleton instance for convenient import
PYNQ_LIMITS = PynqHardwareLimits()


# ---------------------------------------------------------------------------
# Topology constraints
# ---------------------------------------------------------------------------


class PynqTopologyConstraints(BaseModel):
    """Frozen set of topology restrictions for PYNQ Z2 deployment.

    The current PYNQ overlay uses a fixed feedforward LIF engine
    with static quantized weights.  It does not support:
    - Recurrent (feedback) connections
    - Lateral inhibition / spatial connectivity
    - On-chip learning rules (STDP, PES, BCM, Oja)
    - Axonal delays (no delay buffer in overlay)
    - Multi-compartment neurons
    """

    model_config = ConfigDict(frozen=True)

    allow_recurrent: bool = False
    allow_lateral_inhibition: bool = False
    allow_learning_rules: bool = False
    allow_axonal_delays: bool = False
    allow_multi_compartment: bool = False
    max_populations: int = int(_OVERLAY["max_populations"])
    allowed_neuron_models: tuple[str, ...] = tuple(_OVERLAY["supported_neuron_models"])


PYNQ_TOPOLOGY = PynqTopologyConstraints()


# ---------------------------------------------------------------------------
# Support state and rejection reasons
# ---------------------------------------------------------------------------


class PynqSupportState(StrEnum):
    """Two-tier support state for PYNQ target.

    Export-time verdicts (deterministic at planning time):
    - EXPORTABLE: all constraints met; overlay artifacts can be generated
    - EXPORTABLE_WITH_WARNINGS: constraints met but near thresholds (>80%)
    - NOT_EXPORTABLE: one or more export-blocking rejections present

    Deploy-time verdicts (runtime, resolved by issue #11):
    - DEPLOYABLE: export succeeded AND overlay loaded on real PYNQ board
    - NOT_DEPLOYABLE: export OK but board unreachable or overlay load failed
    """

    EXPORTABLE = "exportable"
    EXPORTABLE_WITH_WARNINGS = "exportable_with_warnings"
    NOT_EXPORTABLE = "not_exportable"
    DEPLOYABLE = "deployable"
    NOT_DEPLOYABLE = "not_deployable"


class PynqRejectionReason(StrEnum):
    """Documented rejection codes for PYNQ export/deploy failures."""

    # Export-time rejections (deterministic)
    EXCEEDS_NEURON_CAPACITY = "exceeds_neuron_capacity"
    EXCEEDS_SYNAPSE_CAPACITY = "exceeds_synapse_capacity"
    EXCEEDS_MEMORY_BUDGET = "exceeds_memory_budget"
    WEIGHT_NOT_QUANTIZABLE = "weight_not_quantizable"
    UNSUPPORTED_NEURON_MODEL = "unsupported_neuron_model"
    UNSUPPORTED_LEARNING_RULE = "unsupported_learning_rule"
    UNSUPPORTED_TOPOLOGY = "unsupported_topology"
    WEIGHT_BIT_WIDTH_UNSUPPORTED = "weight_bit_width_unsupported"

    # Deploy-time rejections (runtime, resolved by issue #11)
    BOARD_UNREACHABLE = "board_unreachable"
    OVERLAY_LOAD_FAILURE = "overlay_load_failure"


# Human-readable messages per rejection reason
REJECTION_MESSAGES: dict[PynqRejectionReason, str] = {
    PynqRejectionReason.EXCEEDS_NEURON_CAPACITY: (
        f"Network requires {{n_neurons}} neurons but PYNQ Z2 supports max {PYNQ_LIMITS.MAX_NEURONS}"
    ),
    PynqRejectionReason.EXCEEDS_SYNAPSE_CAPACITY: (
        "Network requires {n_synapses} synapses but PYNQ Z2 supports max "
        f"{PYNQ_LIMITS.MAX_SYNAPSES}"
        " at {bit_width}-bit quantization"
    ),
    PynqRejectionReason.EXCEEDS_MEMORY_BUDGET: (
        "Estimated memory {memory_kb:.1f} KB exceeds PYNQ Z2 budget of "
        f"{PYNQ_LIMITS.MEMORY_BUDGET_KB} KB"
    ),
    PynqRejectionReason.WEIGHT_NOT_QUANTIZABLE: (
        "One or more weights cannot be mapped to {bit_width}-bit fixed-point "
        "representation; quantization error exceeds tolerance"
    ),
    PynqRejectionReason.UNSUPPORTED_NEURON_MODEL: (
        "Neuron model '{model}' not supported; only "
        f"{', '.join(PYNQ_LIMITS.SUPPORTED_NEURON_MODELS)} allowed"
    ),
    PynqRejectionReason.UNSUPPORTED_LEARNING_RULE: (
        "Learning rule '{rule}' not supported; PYNQ overlay uses static synapses only"
    ),
    PynqRejectionReason.UNSUPPORTED_TOPOLOGY: (
        "Complex topology ({detail}) not supported on PYNQ overlay"
    ),
    PynqRejectionReason.WEIGHT_BIT_WIDTH_UNSUPPORTED: (
        "Weight bit-width {bit_width} not in supported set "
        f"{set(PYNQ_LIMITS.SUPPORTED_WEIGHT_BIT_WIDTHS)}"
    ),
    PynqRejectionReason.BOARD_UNREACHABLE: (
        "PYNQ Z2 board is not reachable at {endpoint}; check network connectivity"
    ),
    PynqRejectionReason.OVERLAY_LOAD_FAILURE: (
        "Failed to load overlay bitstream on PYNQ Z2: {detail}"
    ),
}


# ---------------------------------------------------------------------------
# Export result
# ---------------------------------------------------------------------------


class PynqExportResult(BaseModel):
    """Fail-closed export verdict for a network targeting PYNQ Z2.

    Invariant: support_state is EXPORTABLE (or EXPORTABLE_WITH_WARNINGS)
    if and only if ``rejections`` is empty.  This is enforced by the model
    validator.
    """

    model_config = ConfigDict(frozen=True)

    support_state: PynqSupportState
    rejections: list[PynqRejectionReason] = Field(default_factory=list)
    warnings: list[str] = Field(default_factory=list)
    network_summary: dict[str, Any] = Field(default_factory=dict)

    @model_validator(mode="after")
    def validate_fail_closed(self) -> PynqExportResult:
        """Enforce fail-closed invariant.

        - If any rejections exist → support_state MUST be NOT_EXPORTABLE
          or NOT_DEPLOYABLE.
        - If no rejections exist → support_state MUST NOT be NOT_EXPORTABLE
          or NOT_DEPLOYABLE.
        """
        has_rejections = len(self.rejections) > 0
        negative_states = {
            PynqSupportState.NOT_EXPORTABLE,
            PynqSupportState.NOT_DEPLOYABLE,
        }

        if has_rejections and self.support_state not in negative_states:
            raise ValueError(
                f"Fail-closed violation: {len(self.rejections)} rejection(s) present "
                f"but support_state is '{self.support_state}' instead of "
                "'not_exportable' or 'not_deployable'"
            )
        if not has_rejections and self.support_state in negative_states:
            raise ValueError(
                f"Fail-closed violation: support_state is '{self.support_state}' "
                "but no rejections are listed"
            )
        return self
