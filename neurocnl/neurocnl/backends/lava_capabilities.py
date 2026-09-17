"""Lava backend capability configuration."""

from __future__ import annotations

from neurocnl.backends.capabilities import _IR_CONCEPT_SUPPORT, BackendCapabilityProfile

LAVA_PROFILE = BackendCapabilityProfile(
    name="lava",
    neuron_models=frozenset({"lif"}),
    learning_rules=frozenset({"static"}),
    synapse_models=frozenset({"dense", "static"}),
    timing_resolution_seconds=0.001,
    supports_weight_quantization=True,
    concept_support={**_IR_CONCEPT_SUPPORT, "network_topology": "approximate"},
    unsupported_features=("stochastic_spiking",),
    notes=("Current export path is conservative and dense-connection oriented.",),
)


def get_lava_capabilities() -> BackendCapabilityProfile:
    """Return capability profile for Lava backend."""
    return LAVA_PROFILE
