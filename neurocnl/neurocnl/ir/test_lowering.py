"""Characterization tests for the CNL semantic-IR lowering pass (`lower_to_ir`).

This is the golden-fixture gate called for by the Stage 6 refactor plan for
the ``cnl/ir`` canvas-sync pipeline: before this test file existed,
``lower_to_ir`` (the ~1000-line concept dispatcher backing every canvas
parse-as-you-type sync) had zero direct unit tests anywhere in the repo —
only indirect coverage through full-stack neurosim router tests. These
tests pin `lower_to_ir`'s behaviour per concept and its conflict-detection
rules directly, independent of the `condition_parsing`/`ir_merge` module
split performed in this refactor.
"""

from __future__ import annotations

from typing import Any, cast

import numpy as np
import pytest

from neurocnl.cnl.types import ParsedSentence
from neurocnl.ir.lowering import LoweringError, lower_to_ir
from neurocnl.ir.types import AkidaBlockType


def _spec(concept: str, subject: str, **overrides: Any) -> ParsedSentence:
    base: dict[str, Any] = {
        "concept": concept,
        "subject": subject,
        "action": overrides.pop("action", ""),
        "verb": overrides.pop("verb", "has"),
        "negated": overrides.pop("negated", False),
        "condition": overrides.pop("condition", None),
        "raw": overrides.pop("raw", f"{subject} {concept}"),
        "line": overrides.pop("line", 1),
    }
    base.update(overrides)
    return cast(ParsedSentence, base)


def test_unsupported_concept_rejected() -> None:
    with pytest.raises(LoweringError, match="not implemented"):
        lower_to_ir([_spec("not_a_real_concept", "neurons")])


def test_threshold_firing_merges_population_fields() -> None:
    network = lower_to_ir(
        [_spec("threshold_firing", "output neurons", condition="1.5 mV", action="fire")]
    )
    pop = network.populations["output"]
    assert pop.threshold == pytest.approx(1.5)
    assert pop.attributes["threshold_condition"] == "1.5 mV"


def test_conflicting_population_field_raises() -> None:
    specs = [
        _spec("threshold_firing", "a neurons", condition="1.0"),
        _spec("threshold_firing", "a neurons", condition="2.0"),
    ]
    with pytest.raises(LoweringError, match="Conflicting population field"):
        lower_to_ir(specs)


def test_synaptic_weight_creates_connection_and_populations() -> None:
    network = lower_to_ir(
        [_spec("synaptic_weight", "connection from a to b", condition="0.5", negated=False)]
    )
    assert set(network.populations) == {"a", "b"}
    connection = network.connections[0]
    assert connection.source == "a"
    assert connection.target == "b"
    assert connection.weight == pytest.approx(0.5)
    assert connection.polarity == "excitatory"


def test_synaptic_weight_dense_matrix_infers_population_sizes() -> None:
    network = lower_to_ir(
        [
            _spec(
                "synaptic_weight",
                "connection from a to b",
                matrix_kind="dense",
                weight_matrix=[[1.0, 2.0], [3.0, 4.0]],
            )
        ]
    )
    assert network.populations["a"].size == 2
    assert network.populations["b"].size == 2
    weight = np.asarray(network.connections[0].weight)
    assert weight.shape == (2, 2)


def test_axonal_delay_global_scope() -> None:
    network = lower_to_ir([_spec("axonal_delay", "synapse", condition="0.002")])
    assert network.metadata["default_axonal_delay"] == pytest.approx(0.002)


def test_axonal_delay_conflicting_global_values_raise() -> None:
    specs = [
        _spec("axonal_delay", "synapse", condition="0.001"),
        _spec("axonal_delay", "connection", condition="0.002"),
    ]
    with pytest.raises(LoweringError, match="Conflicting global axonal delay"):
        lower_to_ir(specs)


def test_stdp_learning_scoped_to_connection() -> None:
    network = lower_to_ir(
        [
            _spec(
                "stdp_learning",
                "connection from a to b",
                condition="learning rate of 0.01 with window of 0.02",
                action="strengthen",
            )
        ]
    )
    rule = network.learning_rules[0]
    assert rule.kind == "stdp"
    assert rule.source == "a"
    assert rule.target == "b"
    assert rule.rate == pytest.approx(0.01)
    assert rule.window == pytest.approx(0.02)
    assert rule.attributes["update_direction"] == "strengthen"


def test_inhibitory_connection_forces_negative_weight() -> None:
    network = lower_to_ir(
        [_spec("inhibitory_connection", "connection from a to b", condition="0.5")]
    )
    connection = network.connections[0]
    assert connection.polarity == "inhibitory"
    assert connection.weight == pytest.approx(-0.5)


def test_population_coding_with_shape() -> None:
    network = lower_to_ir(
        [_spec("population_coding", "input population", shape=[2, 3], condition="")]
    )
    pop = network.populations["input"]
    assert pop.shape == (2, 3)
    assert pop.role == "input"


def test_network_topology_projection_creates_edge() -> None:
    network = lower_to_ir(
        [_spec("network_topology", "layer1", condition="projects to layer2, layer3")]
    )
    targets = {connection.target for connection in network.connections}
    assert targets == {"layer2", "layer3"}


def test_spatial_connectivity_one_to_one() -> None:
    network = lower_to_ir(
        [
            _spec(
                "spatial_connectivity",
                "a",
                connectivity_pattern="one_to_one",
                action="connect to b",
                condition="one-to-one",
            )
        ]
    )
    connection = network.connections[0]
    assert connection.connectivity_pattern == "one_to_one"
    assert connection.target == "b"


def test_spatial_connectivity_unsupported_condition_raises() -> None:
    with pytest.raises(LoweringError, match="Unsupported spatial connectivity"):
        lower_to_ir([_spec("spatial_connectivity", "a", condition="nonsense condition", action="")])


def test_lateral_inhibition_self_connection() -> None:
    network = lower_to_ir([_spec("lateral_inhibition", "layer1", condition="radius of 2.0")])
    connection = network.connections[0]
    assert connection.source == connection.target == "layer1"
    assert connection.polarity == "inhibitory"
    assert connection.locality_radius == pytest.approx(2.0)


def test_neuromodulation_recorded_in_metadata() -> None:
    network = lower_to_ir(
        [_spec("neuromodulation", "dopamine", condition="1.5", action="modulate")]
    )
    rules = network.metadata["neuromodulation_rules"]
    assert rules[0]["modulator"] == "dopamine"
    assert rules[0]["factor"] == pytest.approx(1.5)


def test_short_term_plasticity_scoped_to_connection() -> None:
    network = lower_to_ir(
        [
            _spec(
                "short_term_plasticity",
                "connection from a to b",
                condition="short-term depression WITH utilization rate of 0.3",
            )
        ]
    )
    connection = network.connections[0]
    assert connection.attributes["short_term_plasticity_type"] == "depression"
    assert connection.attributes["utilization_rate"] == pytest.approx(0.3)


def test_timing_declaration_timestep() -> None:
    network = lower_to_ir([_spec("timing_declaration", "network", condition="timestep of 0.001")])
    declaration = network.timing_declarations[0]
    assert declaration.kind == "timestep"
    assert declaration.value == pytest.approx(0.001)


def test_akida_hardware_declared_once() -> None:
    network = lower_to_ir([_spec("akida_hardware", "hardware", condition="AKD1000")])
    assert network.akida_hardware is not None
    assert network.akida_hardware.version == "AKD1000"


def test_akida_hardware_duplicate_raises() -> None:
    specs = [
        _spec("akida_hardware", "hardware", condition="AKD1000"),
        _spec("akida_hardware", "hardware", condition="AKD1000"),
    ]
    with pytest.raises(LoweringError, match="Multiple Akida hardware"):
        lower_to_ir(specs)


def test_akida_spatiotemporal_connection_scoped() -> None:
    network = lower_to_ir(
        [_spec("akida_spatiotemporal", "connection from a to b", condition="spatial block")]
    )
    prop = network.akida_connection_properties[0]
    assert prop.block_type == AkidaBlockType.SPATIAL
    assert prop.source == "a"
    assert prop.target == "b"
