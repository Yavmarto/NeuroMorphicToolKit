"""Akida deployment contracts shared by planning, validation, and handoff.

This module defines the authoritative Akida contract used across NeuroCNL:
- version-aware hardware limits and topology constraints
- parameter-level export contract validation
- fail-closed deployment planning result model

The public support-state model intentionally stays narrow:
- ``unsupported``
- ``exportable_scaffold``
- ``sdk_deployable``

Warnings and future SDK/runtime metadata are modeled separately so we do not
invent parallel public state names for near-capacity or runtime-failure cases.
"""

from __future__ import annotations

from enum import StrEnum
from typing import Any

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator


class AkidaVersion(StrEnum):
    """Canonical Akida hardware generations supported by the toolkit."""

    AKIDA1 = "akida1"
    AKIDA2 = "akida2"


def normalize_akida_version(value: str | None) -> str:
    """Return the canonical Akida version string used across the toolkit."""
    if value is None:
        return AkidaVersion.AKIDA1.value

    normalized = value.strip().lower()
    if normalized in {"akida", "akd1000", "akida1", "akida 1", "akida 1.0"}:
        return AkidaVersion.AKIDA1.value
    if normalized in {"akida2", "akida 2", "akida 2.0"}:
        return AkidaVersion.AKIDA2.value
    raise ValueError(f"Unsupported Akida version {value!r}")


AKIDA_VERSION_LABELS: dict[str, str] = {
    AkidaVersion.AKIDA1.value: "Akida 1 (AKD1000)",
    AkidaVersion.AKIDA2.value: "Akida 2",
}


def akida_version_label(value: str | None) -> str:
    """Human-facing name for an Akida generation, for use in messages."""
    normalized = normalize_akida_version(value)
    return AKIDA_VERSION_LABELS.get(normalized, normalized)


class AkidaHardwareLimits(BaseModel):
    """Frozen hardware limits for BrainChip Akida."""

    model_config = ConfigDict(frozen=True)

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

    def max_synapses_for_bit_width(self, bit_width: int) -> int:
        """Return the maximum number of synapses that fit in the Akida budget."""
        budget_bytes = self.MEMORY_BUDGET_KB * 1024
        neuron_bytes = self.MAX_NEURONS_PER_NP * self.CORE_COUNT * 6
        available = budget_bytes - neuron_bytes
        if available <= 0:
            return 0
        bytes_per_synapse = (bit_width / 8) + 8
        return int(available / bytes_per_synapse)

    @property
    def MAX_SYNAPSES_1BIT(self) -> int:
        return self.max_synapses_for_bit_width(1)

    @property
    def MAX_SYNAPSES_2BIT(self) -> int:
        return self.max_synapses_for_bit_width(2)

    @property
    def MAX_SYNAPSES_4BIT(self) -> int:
        return self.max_synapses_for_bit_width(4)


AKIDA_LIMITS = AkidaHardwareLimits()


class AkidaTopologyConstraints(BaseModel):
    """Documented topology subset accepted by the shared Akida contract."""

    model_config = ConfigDict(frozen=True)

    allow_learning_rules: bool = False
    allow_multi_compartment: bool = False
    allowed_neuron_models: tuple[str, ...] = ("lif",)

    akida1_allow_recurrent: bool = False
    akida1_allow_lateral_inhibition: bool = False
    akida1_allow_branching: bool = False
    akida1_allow_connection_properties: bool = False

    akida2_allow_recurrent: bool = True
    akida2_allow_lateral_inhibition: bool = True
    akida2_allow_branching: bool = True
    akida2_allow_connection_properties: bool = True
    akida2_max_in_edges: int = 10


AKIDA_TOPOLOGY = AkidaTopologyConstraints()


# NOTE: AkidaExportContract (parameter-level contract used by layer1_validator's
# dead backend=="akida" branch) was removed 2026-07-04 as dead code — see
# current tasks/2026-07-04/validation-deploy-readiness/audit.md.


class AkidaSupportState(StrEnum):
    """Public Akida support states the toolkit is allowed to claim."""

    UNSUPPORTED = "unsupported"
    EXPORTABLE_SCAFFOLD = "exportable_scaffold"
    SDK_DEPLOYABLE = "sdk_deployable"


class AkidaSdkStatus(StrEnum):
    """Future-facing SDK/runtime confirmation status."""

    UNKNOWN = "unknown"
    NOT_AVAILABLE = "not_available"
    MAPPING_FAILED = "mapping_failed"
    DEPLOYABLE = "deployable"


class AkidaSdkIssue(StrEnum):
    """Documented SDK/runtime issues kept separate from contract rejections."""

    SDK_NOT_AVAILABLE = "sdk_not_available"
    DEVICE_MAPPING_FAILURE = "device_mapping_failure"


class AkidaRejectionReason(StrEnum):
    """Documented deterministic contract rejection codes."""

    EXCEEDS_NEURON_CAPACITY = "exceeds_neuron_capacity"
    EXCEEDS_NP_SIZE = "exceeds_np_size"
    EXCEEDS_MEMORY_BUDGET = "exceeds_memory_budget"
    WEIGHT_NOT_QUANTIZABLE = "weight_not_quantizable"
    WEIGHT_EXCEEDS_MAX = "weight_exceeds_max"
    UNSUPPORTED_NEURON_MODEL = "unsupported_neuron_model"
    UNSUPPORTED_LEARNING_RULE = "unsupported_learning_rule"
    UNSUPPORTED_TOPOLOGY = "unsupported_topology"
    WEIGHT_BIT_WIDTH_UNSUPPORTED = "weight_bit_width_unsupported"
    CONNECTION_PROPERTIES_ON_V1 = "akida_connection_properties_on_v1"
    AKIDA_VERSION_MISMATCH = "akida_version_mismatch"


# Every message names the limit that was crossed and the field to change, and
# every number comes from AKIDA_LIMITS so the text cannot drift from the gate.
AKIDA_REJECTION_MESSAGES: dict[AkidaRejectionReason, str] = {
    AkidaRejectionReason.EXCEEDS_NEURON_CAPACITY: (
        "This network needs {n_neurons} neurons but Akida has "
        f"{AKIDA_LIMITS.MAX_NEURONS:,}. Reduce the Neurons on your LIF layers "
        "on the Model canvas."
    ),
    AkidaRejectionReason.EXCEEDS_NP_SIZE: (
        "Layer '{population}' has {pop_size} neurons; Akida maps at most "
        f"{AKIDA_LIMITS.MAX_NEURONS_PER_NP} per neural processor. On the Model "
        f"canvas set that layer's Neurons to {AKIDA_LIMITS.MAX_NEURONS_PER_NP} "
        f"or fewer, and match the Linear node feeding it (Rows) and the next "
        "Linear node (Cols) to the same value."
    ),
    # No numeric format specs in these templates: a placeholder substituted for
    # a missing key is a string, and ":.1f" on a string raises, which would cost
    # the whole sentence. Callers round before populating the details.
    AkidaRejectionReason.EXCEEDS_MEMORY_BUDGET: (
        "This network needs about {memory_kb} KB of on-chip memory but Akida "
        f"has {AKIDA_LIMITS.MEMORY_BUDGET_KB:,} KB. Narrow a layer on the Model "
        "canvas, or lower Weight quantization below."
    ),
    AkidaRejectionReason.WEIGHT_NOT_QUANTIZABLE: (
        "Some weights do not fit {bit_width}-bit fixed point without losing too "
        "much precision. Raise Weight quantization below."
    ),
    AkidaRejectionReason.WEIGHT_EXCEEDS_MAX: (
        "A weight of {weight} is larger than the "
        f"{AKIDA_LIMITS.MAX_WEIGHT} Akida allows. Retrain with weight decay, or "
        "use the trained-model bundle path, which quantizes weights for you."
    ),
    AkidaRejectionReason.UNSUPPORTED_NEURON_MODEL: (
        "Layer '{population}' uses the '{model}' neuron model; Akida only runs "
        f"{', '.join(AKIDA_LIMITS.SUPPORTED_NEURON_MODELS).upper()}. Replace it "
        "with a LIF node on the Model canvas."
    ),
    AkidaRejectionReason.UNSUPPORTED_LEARNING_RULE: (
        "This network learns on-chip via '{rule}'; Akida runs fixed weights "
        "only. Remove the learning rule and train on the Training canvas "
        "instead."
    ),
    AkidaRejectionReason.UNSUPPORTED_TOPOLOGY: (
        "{version} cannot run this network's wiring: {detail}. Change the "
        "connections on the Model canvas."
    ),
    AkidaRejectionReason.WEIGHT_BIT_WIDTH_UNSUPPORTED: (
        "Akida supports "
        f"{', '.join(str(w) for w in AKIDA_LIMITS.SUPPORTED_WEIGHT_BIT_WIDTHS)}"
        "-bit weights; {bit_width}-bit was requested. Pick a supported value "
        "under Weight quantization below."
    ),
    AkidaRejectionReason.CONNECTION_PROPERTIES_ON_V1: (
        "This network uses Akida connection properties, which need Akida 2. "
        "Switch Akida Version below, or remove those properties from the spec."
    ),
    AkidaRejectionReason.AKIDA_VERSION_MISMATCH: (
        "The spec targets {declared_version} but {requested_version} is "
        "selected. Change Akida Version below to match the spec."
    ),
}


class _MissingDetail(dict[str, Any]):
    """Leaves unknown placeholders visible rather than raising KeyError.

    A rejection whose details were not populated must still produce a readable
    sentence — losing the whole message to a KeyError is how the raw enum
    values ended up in front of users in the first place.
    """

    def __missing__(self, key: str) -> str:
        return f"<{key}>"


def format_akida_rejection(
    reason: AkidaRejectionReason, details: dict[str, Any] | None = None
) -> str:
    """Render one rejection as an actionable sentence.

    Names the limit that was crossed and the parameter to change. Never raises:
    an unrecognised reason falls back to its code, and missing detail keys are
    rendered as ``<key>`` so the rest of the sentence survives.
    """
    template = AKIDA_REJECTION_MESSAGES.get(reason)
    if template is None:
        return f"Akida export rejected ({reason.value})."
    try:
        return template.format_map(_MissingDetail(details or {}))
    except (IndexError, ValueError):
        # Malformed template (stray brace) — the code still beats an exception.
        return f"Akida export rejected ({reason.value})."


AKIDA_SDK_STATUS_MESSAGES: dict[AkidaSdkIssue, str] = {
    AkidaSdkIssue.SDK_NOT_AVAILABLE: (
        "Akida Python SDK is not installed; install via 'pip install akida'."
    ),
    AkidaSdkIssue.DEVICE_MAPPING_FAILURE: "Failed to map the model to an Akida device.",
}


class AkidaExportResult(BaseModel):
    """Fail-closed contract result for a network targeting Akida."""

    model_config = ConfigDict(frozen=True)

    support_state: AkidaSupportState
    akida_version: str = Field(
        default=AkidaVersion.AKIDA1.value,
        description="Canonical Akida generation tested by the contract.",
    )
    rejections: list[AkidaRejectionReason] = Field(default_factory=list)
    warnings: list[str] = Field(default_factory=list)
    topology_verdict: str = Field(
        default="unknown",
        description="Topology classification from the shared capability checker.",
    )
    network_summary: dict[str, Any] = Field(default_factory=dict)
    rejection_details: dict[str, Any] = Field(
        default_factory=dict,
        description=(
            "Values the AKIDA_REJECTION_MESSAGES templates interpolate, so a "
            "rejection can name the offending node and the limit it crossed. "
            "Format with format_akida_rejection()."
        ),
    )
    sdk_status: AkidaSdkStatus = Field(default=AkidaSdkStatus.UNKNOWN)
    sdk_issues: list[AkidaSdkIssue] = Field(default_factory=list)

    def rejection_messages(self) -> list[str]:
        """Return one human-readable, actionable sentence per rejection."""
        return [
            format_akida_rejection(reason, self.rejection_details) for reason in self.rejections
        ]

    @field_validator("akida_version", mode="before")
    @classmethod
    def normalize_version(cls, value: str | None) -> str:
        return normalize_akida_version(value)

    @model_validator(mode="after")
    def validate_fail_closed(self) -> AkidaExportResult:
        """Enforce the contract's fail-closed and SDK-state invariants."""
        has_rejections = len(self.rejections) > 0

        if has_rejections and self.support_state != AkidaSupportState.UNSUPPORTED:
            raise ValueError(
                f"Fail-closed violation: {len(self.rejections)} rejection(s) present "
                f"but support_state is '{self.support_state}'."
            )
        if not has_rejections and self.support_state == AkidaSupportState.UNSUPPORTED:
            raise ValueError(
                "Fail-closed violation: support_state is 'unsupported' but no "
                "rejections are listed."
            )
        if self.support_state == AkidaSupportState.SDK_DEPLOYABLE:
            if self.sdk_status != AkidaSdkStatus.DEPLOYABLE:
                raise ValueError("sdk_deployable requires sdk_status='deployable'.")
            if self.sdk_issues:
                raise ValueError("sdk_deployable cannot include sdk_issues.")
        elif self.sdk_status == AkidaSdkStatus.DEPLOYABLE:
            raise ValueError("sdk_status='deployable' requires support_state='sdk_deployable'.")

        if self.sdk_issues and self.sdk_status not in {
            AkidaSdkStatus.NOT_AVAILABLE,
            AkidaSdkStatus.MAPPING_FAILED,
        }:
            raise ValueError("sdk_issues require sdk_status to describe the failure.")

        return self
