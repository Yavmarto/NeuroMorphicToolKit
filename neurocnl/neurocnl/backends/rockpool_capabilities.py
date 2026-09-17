"""Rockpool backend capability claims."""

from __future__ import annotations

from neurocnl.backends.capabilities import _IR_CONCEPT_SUPPORT, BackendCapabilityProfile

rockpool_capabilities = BackendCapabilityProfile(
    name="rockpool",
    neuron_models=frozenset({"lif", "lif_bitshift", "exp_syn_lif"}),
    learning_rules=frozenset({"bptt", "surrogate_gradient"}),
    synapse_models=frozenset({"linear", "exp_syn"}),
    timing_resolution_seconds=0.001,
    supports_weight_quantization=True,
    concept_support={
        **_IR_CONCEPT_SUPPORT,
        "on_chip_learning": "unsupported",
        "neurocnl_direct_conversion": "approximate",
    },
    unsupported_features=("multi_compartment_neurons",),
    notes=(
        "Focused on PyTorch-integrated training using surrogate gradients.",
        "Sequential feed-forward IR and NIR graphs can be lowered to Rockpool modules.",
        "Branching and merged topologies remain unsupported in the direct conversion path.",
    ),
)
