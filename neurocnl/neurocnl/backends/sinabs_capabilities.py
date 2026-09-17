"""Capability profile for SynSense sinabs backend."""

from neurocnl.backends.capabilities import _IR_CONCEPT_SUPPORT, BackendCapabilityProfile

SINABS_PROFILE = BackendCapabilityProfile(
    name="sinabs",
    neuron_models=frozenset({"iaf", "lif"}),
    learning_rules=frozenset({"static"}),
    synapse_models=frozenset({"dense", "static"}),
    timing_resolution_seconds=0.001,
    supports_weight_quantization=True,
    concept_support={
        **_IR_CONCEPT_SUPPORT,
        "network_topology": "approximate",  # sequential path works with simplifications
        "branching_topology": "approximate",
    },
    unsupported_features=("multi_compartment_neurons", "stochastic_spiking"),
    notes=(
        "Primary deployment path for SynSense Speck and DYNAP-CNN.",
        "Sequential topologies remain the most faithful path; branching DAGs are lowered "
        "through a deterministic wrapper in sinabs_io.py.",
    ),
)
