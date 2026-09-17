"""Source of truth for backend capability claims."""

from __future__ import annotations

from collections.abc import Callable, Iterator, MutableMapping
from dataclasses import dataclass


@dataclass(frozen=True, slots=True)
class BackendCapabilityProfile:
    """Conservative capability summary for a backend target."""

    name: str
    neuron_models: frozenset[str]
    learning_rules: frozenset[str]
    synapse_models: frozenset[str]
    timing_resolution_seconds: float | None
    supports_weight_quantization: bool
    concept_support: dict[str, str]
    unsupported_features: tuple[str, ...]
    notes: tuple[str, ...] = ()


_IR_CONCEPT_SUPPORT = {
    "threshold_firing": "faithful",
    "refractory_period": "faithful",
    "membrane_potential_decay": "faithful",
    "synaptic_weight": "faithful",
    "axonal_delay": "faithful",
    "stdp_learning": "unsupported",
    "inhibitory_connection": "faithful",
    "population_coding": "faithful",
    "network_topology": "faithful",
    "timing_declaration": "faithful",
}

_NIR_CONCEPT_SUPPORT = {
    "threshold_firing": "faithful",
    "refractory_period": "approximate",
    "membrane_potential_decay": "faithful",
    "synaptic_weight": "faithful",
    "axonal_delay": "faithful",
    "stdp_learning": "approximate",
    "inhibitory_connection": "faithful",
    "population_coding": "approximate",
    "population_coding_range": "approximate",
    "network_topology": "approximate",
    "timing_declaration": "approximate",
    "adaptive_spiking": "approximate",
    "receptor_dynamics": "approximate",
    "background_noise": "approximate",
    "spatial_connectivity": "approximate",
}

_LAZY_BACKEND_LOADERS: dict[str, Callable[[], BackendCapabilityProfile]]

BACKEND_CAPABILITIES: MutableMapping[str, BackendCapabilityProfile] = {
    "nengo": BackendCapabilityProfile(
        name="nengo",
        neuron_models=frozenset({"lif", "adaptive_lif"}),
        learning_rules=frozenset({"pes", "bcm", "oja", "stdp"}),
        synapse_models=frozenset({"lowpass", "alpha", "static"}),
        timing_resolution_seconds=0.001,
        supports_weight_quantization=False,
        concept_support={**_IR_CONCEPT_SUPPORT, "stdp_learning": "approximate"},
        unsupported_features=("on_chip_learning_constraints",),
        notes=(
            "Legacy execution backend — not part of the active product surface. Retained in the registry for historical reference only.",
        ),
    ),
    "loihi": BackendCapabilityProfile(
        name="loihi",
        neuron_models=frozenset({"lif"}),
        learning_rules=frozenset({"pes", "bcm", "oja", "stdp"}),
        synapse_models=frozenset({"lowpass", "static"}),
        timing_resolution_seconds=0.001,
        supports_weight_quantization=True,
        concept_support={
            **_IR_CONCEPT_SUPPORT,
            "network_topology": "approximate",
            "stdp_learning": "approximate",
        },
        unsupported_features=("multi_compartment_neurons",),
        notes=(
            "Topology mapping remains approximate pending placement-aware planning.",
        ),
    ),
    "lava": BackendCapabilityProfile(
        name="lava",
        neuron_models=frozenset({"lif"}),
        learning_rules=frozenset({"static"}),
        synapse_models=frozenset({"dense", "static"}),
        timing_resolution_seconds=0.001,
        supports_weight_quantization=True,
        concept_support={**_IR_CONCEPT_SUPPORT, "network_topology": "approximate"},
        unsupported_features=("stochastic_spiking",),
        notes=("Current export path is conservative and dense-connection oriented.",),
    ),
    "spinnaker": BackendCapabilityProfile(
        name="spinnaker",
        neuron_models=frozenset({"if_curr_exp"}),
        learning_rules=frozenset({"static"}),
        synapse_models=frozenset({"static"}),
        timing_resolution_seconds=0.001,
        supports_weight_quantization=True,
        concept_support={**_IR_CONCEPT_SUPPORT, "network_topology": "approximate"},
        unsupported_features=("adaptive_spiking",),
        notes=("Projection topology may require backend-specific mapping choices.",),
    ),
    "akida": BackendCapabilityProfile(
        name="akida",
        neuron_models=frozenset({"lif"}),
        learning_rules=frozenset({"static"}),
        synapse_models=frozenset({"dense", "static"}),
        timing_resolution_seconds=None,
        supports_weight_quantization=True,
        concept_support={
            **_IR_CONCEPT_SUPPORT,
            "homeostatic_plasticity": "unsupported",
            "short_term_plasticity": "unsupported",
            "receptor_dynamics": "unsupported",
        },
        unsupported_features=("stochastic_spiking", "on_chip_learning_constraints"),
        notes=("Direct SNN generation for Akida via akida.Sequential().",),
    ),
    "teensy": BackendCapabilityProfile(
        name="teensy",
        neuron_models=frozenset({"lif"}),
        learning_rules=frozenset({"static"}),
        synapse_models=frozenset({"static"}),
        timing_resolution_seconds=0.001,
        supports_weight_quantization=True,
        concept_support={
            **_IR_CONCEPT_SUPPORT,
            "population_coding": "approximate",
            "network_topology": "unsupported",
            "stdp_learning": "unsupported",
            "homeostatic_plasticity": "unsupported",
            "short_term_plasticity": "unsupported",
            "receptor_dynamics": "unsupported",
            "lateral_inhibition": "unsupported",
            "spatial_connectivity": "unsupported",
        },
        unsupported_features=(
            "multi_population_topology",
            "recurrent_connections",
            "on_chip_learning",
            "axonal_delays",
        ),
        notes=(
            "Teensy 4.1 embedded target: feedforward LIF networks with static "
            "weights only. See teensy_deployment_contract.py for full spec. "
            "Supports int8/int16/float32 weight quantization.",
        ),
    ),
    "akida1": BackendCapabilityProfile(
        name="akida1",
        neuron_models=frozenset({"lif"}),
        learning_rules=frozenset({"static"}),
        synapse_models=frozenset({"dense", "static"}),
        timing_resolution_seconds=0.001,
        supports_weight_quantization=True,
        concept_support={
            **_IR_CONCEPT_SUPPORT,
            "network_topology": "unsupported",
            "stdp_learning": "unsupported",
        },
        unsupported_features=("unconstrained_network_topology",),
        notes=(
            "Requires strictly constrained network topologies mapping to NP constraints.",
        ),
    ),
    "akida2": BackendCapabilityProfile(
        name="akida2",
        neuron_models=frozenset({"lif"}),
        learning_rules=frozenset({"static"}),
        synapse_models=frozenset({"dense", "static"}),
        timing_resolution_seconds=0.001,
        supports_weight_quantization=True,
        concept_support={
            **_IR_CONCEPT_SUPPORT,
            "network_topology": "approximate",
            "stdp_learning": "unsupported",
        },
        unsupported_features=("unconstrained_network_topology",),
        notes=(
            "Requires constrained network topologies, avoiding CNN-to-SNN transforms.",
        ),
    ),
    "pynq": BackendCapabilityProfile(
        name="pynq",
        neuron_models=frozenset({"lif"}),
        learning_rules=frozenset({"static"}),
        synapse_models=frozenset({"dense", "static"}),
        timing_resolution_seconds=0.001,
        supports_weight_quantization=True,
        concept_support={
            **_IR_CONCEPT_SUPPORT,
            "network_topology": "approximate",
            "synaptic_weight": "quantized",
        },
        unsupported_features=(
            "on_chip_learning_constraints",
            "adaptive_spiking",
            "multi_compartment_neurons",
        ),
        notes=(
            "Compiles to a direct memory-mapped overlay on Zynq-7000 (PYNQ Z2). "
            "Strictly requires quantized weights (int4/int8) to fit in limited BRAM. "
            "Maximum ~64K synapses total for a Zynq-7000 at int4.",
        ),
    ),
    "spinnaker2": BackendCapabilityProfile(
        name="spinnaker2",
        neuron_models=frozenset({"lif"}),
        learning_rules=frozenset({"static"}),
        synapse_models=frozenset({"static"}),
        timing_resolution_seconds=0.001,
        supports_weight_quantization=True,
        concept_support={**_IR_CONCEPT_SUPPORT, "network_topology": "faithful"},
        unsupported_features=("adaptive_spiking",),
        notes=("Uses py-spinnaker2 rather than PyNN.",),
    ),
    "nir": BackendCapabilityProfile(
        name="nir",
        neuron_models=frozenset({"lif"}),
        learning_rules=frozenset(),
        synapse_models=frozenset({"dense"}),
        timing_resolution_seconds=None,
        supports_weight_quantization=False,
        concept_support=_NIR_CONCEPT_SUPPORT,
        unsupported_features=(
            "first_class_delay_nodes",
            "first_class_learning_rules",
            "structured_sparse_connectivity",
        ),
        notes=(
            "Export format only: NeuroCNL materializes Input, Output, LIF, and Linear nodes.",
            "Axonal delays now lower to executable nir.Delay nodes when they are present on a "
            "connection or inherited from a declared global default delay.",
            "Learning rules and timing declarations are currently preserved as metadata "
            "rather than executable NIR nodes; timing declarations are now machine-checked for "
            "duplicate kinds and delay-quantization consistency within the current bridge.",
            "Adaptive spiking, background noise, and population coding range currently survive as "
            "metadata rather than executable NIR operators.",
            "Receptor dynamics are currently preserved as metadata rather than executable NIR "
            "synapse operators; this is a stable metadata-only contract for the current bridge.",
            "Structured spatial connectivity is only partially supported: one-to-one and explicit "
            "binary-mask families lower exact dense Linear weights, while locality- and "
            "probability-based patterns remain unsupported.",
            "Connections are currently materialized as dense Linear weights, even when the source "
            "CNL semantics are more structured.",
        ),
    ),
}


# Lazy import to avoid circular dependencies
def _get_rockpool_capabilities() -> BackendCapabilityProfile:
    from neurocnl.backends.rockpool_capabilities import rockpool_capabilities

    return rockpool_capabilities


from collections import UserDict


class _BackendCapabilitiesDict(UserDict[str, BackendCapabilityProfile]):
    def __getitem__(self, key: str) -> BackendCapabilityProfile:
        if key == "rockpool":
            return _get_rockpool_capabilities()
        return super().__getitem__(key)

    def __iter__(self) -> Iterator[str]:
        yield from super().__iter__()
        yield "rockpool"

    def __len__(self) -> int:
        return super().__len__() + 1

    def __contains__(self, key: object) -> bool:
        if key == "rockpool":
            return True
        return super().__contains__(key)


BACKEND_CAPABILITIES = _BackendCapabilitiesDict(BACKEND_CAPABILITIES)


def get_backend_capability(name: str) -> BackendCapabilityProfile:
    """Return the capability profile for a backend target."""
    normalized = name.strip().lower()

    if normalized == "rockpool" and "rockpool" not in BACKEND_CAPABILITIES:
        BACKEND_CAPABILITIES["rockpool"] = _get_rockpool_capabilities()

    try:
        return BACKEND_CAPABILITIES[normalized]
    except KeyError as exc:
        raise KeyError(f"Unknown backend capability profile {name!r}.") from exc


def list_backend_capabilities() -> dict[str, BackendCapabilityProfile]:
    """Return all backend capability profiles."""
    if "rockpool" not in BACKEND_CAPABILITIES:
        BACKEND_CAPABILITIES["rockpool"] = _get_rockpool_capabilities()
    return dict(BACKEND_CAPABILITIES)
