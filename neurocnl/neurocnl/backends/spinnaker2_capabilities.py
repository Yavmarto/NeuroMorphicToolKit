"""SpiNNaker2 backend capabilities profile.

Defines the hardware capabilities and constraints for the py-spinnaker2 backend.
"""

from __future__ import annotations

from neurocnl.backends.capabilities import _IR_CONCEPT_SUPPORT, BackendCapabilityProfile

SPINNAKER2_PROFILE = BackendCapabilityProfile(
    name="spinnaker2",
    neuron_models=frozenset({"lif"}),
    learning_rules=frozenset({"static"}),
    synapse_models=frozenset({"static"}),
    timing_resolution_seconds=0.001,
    supports_weight_quantization=True,
    concept_support={**_IR_CONCEPT_SUPPORT, "network_topology": "faithful"},
    unsupported_features=("adaptive_spiking",),
    notes=("Uses py-spinnaker2 rather than PyNN.",),
)
