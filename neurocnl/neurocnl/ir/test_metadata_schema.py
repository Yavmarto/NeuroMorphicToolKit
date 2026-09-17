"""Tests for the versioned advisory metadata schema used by NIR materialization."""

from neurocnl.ir.metadata_schema import (
    ADVISORY_SEMANTICS_VERSION,
    advisory_connection_semantics,
    advisory_delay_semantics,
    advisory_graph_semantics,
    advisory_population_semantics,
)


def test_advisory_population_semantics_uses_versioned_reserved_fields() -> None:
    advisory = advisory_population_semantics(shape_intent=[2, 3])

    assert advisory["schema_version"] == ADVISORY_SEMANTICS_VERSION
    assert advisory["surface"] == "population"
    assert advisory["shape_intent"] == [2, 3]


def test_advisory_connection_semantics_uses_versioned_reserved_fields() -> None:
    advisory = advisory_connection_semantics(
        delay=0.003,
        learning_rules=[{"kind": "stdp"}],
        connectivity_pattern="binary_mask",
        shape_intent={"source_shape": [2, 2], "target_shape": [2, 2]},
        locality_radius=None,
        connection_density=0.2,
    )

    assert advisory["schema_version"] == ADVISORY_SEMANTICS_VERSION
    assert advisory["surface"] == "connection"
    assert advisory["delay"] == 0.003
    assert advisory["learning_rules"] == [{"kind": "stdp"}]
    assert advisory["connectivity_pattern"] == "binary_mask"
    assert advisory["shape_intent"] == {"source_shape": [2, 2], "target_shape": [2, 2]}
    assert advisory["connection_density"] == 0.2


def test_advisory_delay_semantics_uses_versioned_reserved_fields() -> None:
    advisory = advisory_delay_semantics(
        delay=0.004,
        shape_intent={"source_shape": [4], "target_shape": [4]},
    )

    assert advisory["schema_version"] == ADVISORY_SEMANTICS_VERSION
    assert advisory["surface"] == "delay"
    assert advisory["delay"] == 0.004
    assert advisory["shape_intent"] == {"source_shape": [4], "target_shape": [4]}


def test_advisory_graph_semantics_uses_versioned_reserved_fields() -> None:
    advisory = advisory_graph_semantics(
        timing_declarations=[{"kind": "timestep", "value": 0.001}],
        global_receptor_dynamics={"receptor_type": "NMDA"},
        unscoped_learning_rules=[{"kind": "stdp"}],
        population_shapes={"input": [2, 3]},
        neuromodulation_rules=[],
        short_term_plasticity_rules=[],
    )

    assert advisory["schema_version"] == ADVISORY_SEMANTICS_VERSION
    assert advisory["surface"] == "graph"
    assert advisory["timing_declarations"] == [{"kind": "timestep", "value": 0.001}]
    assert advisory["global_receptor_dynamics"] == {"receptor_type": "NMDA"}
    assert advisory["learning_rules"] == [{"kind": "stdp"}]
    assert advisory["population_shapes"] == {"input": [2, 3]}
