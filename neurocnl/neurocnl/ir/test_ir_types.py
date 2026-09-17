"""Tests for the internal IR dataclasses."""

from neurocnl.ir.types import (
    BackendHintIR,
    ConnectionIR,
    LearningRuleIR,
    NetworkIR,
    PopulationIR,
    SourceProvenance,
    TimingDeclarationIR,
    normalize_identifier,
)


def test_normalize_identifier_collapses_whitespace_and_case() -> None:
    assert normalize_identifier("  Sensory   Neuron ") == "sensory neuron"


def test_source_provenance_defaults() -> None:
    provenance = SourceProvenance()
    assert provenance.line is None
    assert provenance.raw is None
    assert provenance.concept is None


def test_population_ir_normalizes_name_and_role() -> None:
    population = PopulationIR(name=" Sensory   Neuron ", role=" Population ")
    assert population.name == "sensory neuron"
    assert population.role == "population"


def test_population_ir_normalizes_input_output_aliases() -> None:
    assert PopulationIR(name="sensory", role="sensory").role == "input"
    assert PopulationIR(name="motor", role="motor").role == "output"


def test_connection_ir_normalizes_endpoints_and_polarity() -> None:
    connection = ConnectionIR(
        source=" Sensory Neuron ",
        target=" Motor Neuron ",
        polarity=" Inhibitory ",
    )
    assert connection.source == "sensory neuron"
    assert connection.target == "motor neuron"
    assert connection.polarity == "inhibitory"


def test_connection_ir_normalizes_structured_connectivity_fields() -> None:
    connection = ConnectionIR(
        source="Input",
        target="Output",
        connectivity_pattern=" One To One ",
        connectivity_mask=((1, 0), (0, 1)),
        locality_radius=2,
        connection_density=0.5,
    )
    assert connection.connectivity_pattern == "one_to_one"
    assert connection.connectivity_mask == ((1, 0), (0, 1))
    assert connection.locality_radius == 2.0
    assert connection.connection_density == 0.5


def test_connection_ir_infers_binary_mask_pattern() -> None:
    connection = ConnectionIR(
        source="a", target="b", connectivity_mask=((1, 0), (0, 1))
    )
    assert connection.connectivity_pattern == "binary_mask"


def test_learning_rule_ir_normalizes_kind_and_scope() -> None:
    rule = LearningRuleIR(kind=" BCM ", source="Sensory Neuron", target="Motor Neuron")
    assert rule.kind == "bcm"
    assert rule.source == "sensory neuron"
    assert rule.target == "motor neuron"


def test_default_collections_are_isolated() -> None:
    first = NetworkIR()
    second = NetworkIR()
    first.connections.append(ConnectionIR(source="a", target="b"))
    assert first.connections != second.connections
    assert second.connections == []


def test_backend_hint_and_timing_defaults() -> None:
    hint = BackendHintIR(backend=" Loihi ", note="preferred")
    timing = TimingDeclarationIR(kind="timestep", value=0.001, unit="seconds")
    assert hint.backend == "loihi"
    assert timing.kind == "timestep"
    assert timing.provenance == []


def test_population_ir_preserves_provenance_and_attributes() -> None:
    provenance = SourceProvenance(
        line=3, raw="The sensory neuron ...", concept="threshold_firing"
    )
    population = PopulationIR(
        name="sensory neuron",
        provenance=[provenance],
        attributes={"threshold_condition": "exceeds 1.0"},
    )
    assert population.provenance[0].line == 3
    assert population.attributes["threshold_condition"] == "exceeds 1.0"


def test_population_ir_normalizes_shape_and_validates_size() -> None:
    population = PopulationIR(name="grid", size=6, shape=(2, 3))
    assert population.shape == (2, 3)
