"""Unit tests for NetworkFacts — the shared per-graph facts planner.py reads from.

These are the first direct, isolated tests of the counting/detection logic that
used to be duplicated inline across plan_teensy_deployability,
plan_pynq_exportability, and plan_akida_exportability.
"""

from __future__ import annotations

from neurocnl.ir.types import (
    ConnectionIR,
    NetworkIR,
    PopulationIR,
    SourceProvenance,
    TimingDeclarationIR,
)
from neurocnl.network_facts import DEFAULT_POPULATION_SIZE, NetworkFacts, is_port_population


def _ir(
    *,
    populations: dict[str, PopulationIR] | None = None,
    connections: list[ConnectionIR] | None = None,
    timing_declarations: list[TimingDeclarationIR] | None = None,
) -> NetworkIR:
    return NetworkIR(
        populations=populations or {},
        connections=connections or [],
        timing_declarations=timing_declarations or [],
    )


def _feedforward_ir(*, with_port: bool = False) -> NetworkIR:
    pops = {
        "hidden": PopulationIR(name="hidden", size=10, population_type="lif"),
        "output": PopulationIR(name="output", size=5, population_type="lif"),
    }
    conns = [ConnectionIR(source="hidden", target="output", weight=1.0)]
    if with_port:
        pops["input"] = PopulationIR(name="input", size=8, population_type="input")
        conns.insert(0, ConnectionIR(source="input", target="hidden", weight=1.0))
    return _ir(populations=pops, connections=conns)


class TestPortExclusion:
    def test_is_port_population_true_for_input_output(self) -> None:
        assert is_port_population(PopulationIR(name="in", population_type="input"))
        assert is_port_population(PopulationIR(name="out", population_type="output"))

    def test_is_port_population_false_for_lif(self) -> None:
        assert not is_port_population(PopulationIR(name="pop", population_type="lif"))

    def test_is_port_population_false_for_none(self) -> None:
        assert not is_port_population(PopulationIR(name="pop"))

    def test_neuron_counts_differ_with_and_without_port_exclusion(self) -> None:
        facts = NetworkFacts.from_ir(_feedforward_ir(with_port=True))
        # 8 (input port) + 10 (hidden) + 5 (output) = 23 total
        assert facts.n_neurons_total == 23
        # Port excluded: 10 + 5 = 15
        assert facts.n_neurons_excluding_ports == 15

    def test_neuron_counts_equal_without_ports(self) -> None:
        facts = NetworkFacts.from_ir(_feedforward_ir(with_port=False))
        assert facts.n_neurons_total == facts.n_neurons_excluding_ports == 15

    def test_default_population_size_used_when_unspecified(self) -> None:
        ir = _ir(populations={"pop": PopulationIR(name="pop", population_type="lif")})
        facts = NetworkFacts.from_ir(ir)
        assert facts.population_sizes["pop"] == DEFAULT_POPULATION_SIZE
        assert facts.n_neurons_total == DEFAULT_POPULATION_SIZE


class TestSynapseCounting:
    def test_dense_synapse_count(self) -> None:
        ir = _feedforward_ir(with_port=False)
        facts = NetworkFacts.from_ir(ir)
        # One connection, hidden(10) -> output(5): 10*5 = 50 synapses
        assert facts.n_synapses_total == 50
        assert facts.n_synapses_excluding_ports == 50

    def test_port_touching_connection_excluded_when_requested(self) -> None:
        ir = _feedforward_ir(with_port=True)
        facts = NetworkFacts.from_ir(ir)
        # input(8)->hidden(10) = 80, hidden(10)->output(5) = 50 => 130 total
        assert facts.n_synapses_total == 130
        # Excluding the port-touching connection leaves only hidden->output
        assert facts.n_synapses_excluding_ports == 50


class TestConnectionPairsAndCounts:
    def test_real_connection_pairs_excludes_port_touching_edges(self) -> None:
        ir = _feedforward_ir(with_port=True)
        facts = NetworkFacts.from_ir(ir)
        assert facts.real_connection_pairs == {("hidden", "output")}

    def test_population_and_connection_totals(self) -> None:
        ir = _feedforward_ir(with_port=True)
        facts = NetworkFacts.from_ir(ir)
        assert facts.n_populations_total == 3
        assert facts.n_populations_excluding_ports == 2
        assert facts.n_connections_total == 2


class TestProvenanceConcepts:
    def test_collects_population_and_connection_concepts(self) -> None:
        pops = {
            "a": PopulationIR(
                name="a",
                size=4,
                population_type="lif",
                provenance=[SourceProvenance(concept="lateral_inhibition")],
            ),
        }
        conns = [
            ConnectionIR(
                source="a",
                target="a",
                weight=1.0,
                provenance=[SourceProvenance(concept="spatial_connectivity")],
            )
        ]
        facts = NetworkFacts.from_ir(_ir(populations=pops, connections=conns))
        assert facts.provenance_concepts == {"lateral_inhibition", "spatial_connectivity"}

    def test_empty_when_no_provenance(self) -> None:
        facts = NetworkFacts.from_ir(_feedforward_ir())
        assert facts.provenance_concepts == frozenset()


class TestRecurrentConnections:
    def test_self_connection_detected(self) -> None:
        pops = {"a": PopulationIR(name="a", size=4, population_type="lif")}
        conns = [ConnectionIR(source="a", target="a", weight=1.0)]
        facts = NetworkFacts.from_ir(_ir(populations=pops, connections=conns))
        assert facts.has_recurrent_connections
        assert "self-connection on 'a'" in facts.recurrent_connection_descriptions[0]

    def test_cycle_detected(self) -> None:
        pops = {
            "a": PopulationIR(name="a", size=4, population_type="lif"),
            "b": PopulationIR(name="b", size=4, population_type="lif"),
        }
        conns = [
            ConnectionIR(source="a", target="b", weight=1.0),
            ConnectionIR(source="b", target="a", weight=1.0),
        ]
        facts = NetworkFacts.from_ir(_ir(populations=pops, connections=conns))
        assert facts.has_recurrent_connections

    def test_no_recurrence_in_feedforward_chain(self) -> None:
        facts = NetworkFacts.from_ir(_feedforward_ir())
        assert not facts.has_recurrent_connections
        assert facts.recurrent_connection_descriptions == ()


class TestAxonalDelays:
    def test_detects_positive_delay(self) -> None:
        pops = {
            "a": PopulationIR(name="a", size=4, population_type="lif"),
            "b": PopulationIR(name="b", size=4, population_type="lif"),
        }
        conns = [ConnectionIR(source="a", target="b", weight=1.0, delay=0.5)]
        facts = NetworkFacts.from_ir(_ir(populations=pops, connections=conns))
        assert facts.has_axonal_delays

    def test_no_delay_by_default(self) -> None:
        facts = NetworkFacts.from_ir(_feedforward_ir())
        assert not facts.has_axonal_delays

    def test_zero_delay_does_not_count(self) -> None:
        pops = {
            "a": PopulationIR(name="a", size=4, population_type="lif"),
            "b": PopulationIR(name="b", size=4, population_type="lif"),
        }
        conns = [ConnectionIR(source="a", target="b", weight=1.0, delay=0.0)]
        facts = NetworkFacts.from_ir(_ir(populations=pops, connections=conns))
        assert not facts.has_axonal_delays


class TestTimingDeclarations:
    def test_extracts_timestep(self) -> None:
        ir = _ir(timing_declarations=[TimingDeclarationIR(kind="timestep", value=0.001)])
        facts = NetworkFacts.from_ir(ir)
        assert facts.declared_timestep_seconds == 0.001

    def test_extracts_delay_quantization(self) -> None:
        ir = _ir(timing_declarations=[TimingDeclarationIR(kind="delay_quantization", value=0.0001)])
        facts = NetworkFacts.from_ir(ir)
        assert facts.declared_delay_quantization_seconds == 0.0001

    def test_none_when_absent(self) -> None:
        facts = NetworkFacts.from_ir(_feedforward_ir())
        assert facts.declared_timestep_seconds is None
        assert facts.declared_delay_quantization_seconds is None


class TestWeightFlattening:
    def test_scalar_weight(self) -> None:
        facts = NetworkFacts.from_ir(_feedforward_ir())
        assert facts.connection_weights_total == (1.0,)

    def test_matrix_weight_flattened(self) -> None:
        pops = {
            "a": PopulationIR(name="a", size=2, population_type="lif"),
            "b": PopulationIR(name="b", size=2, population_type="lif"),
        }
        conns = [ConnectionIR(source="a", target="b", weight=[[1.0, -2.0], [3.0, -4.0]])]
        facts = NetworkFacts.from_ir(_ir(populations=pops, connections=conns))
        assert sorted(facts.connection_weights_total) == [-4.0, -2.0, 1.0, 3.0]
        assert facts.max_abs_weight == 4.0

    def test_none_weight_skipped(self) -> None:
        pops = {
            "a": PopulationIR(name="a", size=2, population_type="lif"),
            "b": PopulationIR(name="b", size=2, population_type="lif"),
        }
        conns = [ConnectionIR(source="a", target="b", weight=None)]
        facts = NetworkFacts.from_ir(_ir(populations=pops, connections=conns))
        assert facts.connection_weights_total == ()
        assert facts.max_abs_weight is None

    def test_port_touching_weight_excluded(self) -> None:
        ir = _feedforward_ir(with_port=True)
        facts = NetworkFacts.from_ir(ir)
        # Both connections have weight=1.0; only the non-port one (hidden->output)
        # survives exclusion.
        assert facts.connection_weights_excluding_ports == (1.0,)
        assert facts.connection_weights_total == (1.0, 1.0)


class TestNeuronModelsUsed:
    def test_collects_lowercased_population_types(self) -> None:
        pops = {
            "a": PopulationIR(name="a", size=2, population_type="LIF"),
            "b": PopulationIR(name="b", size=2, population_type="Izhikevich"),
        }
        facts = NetworkFacts.from_ir(_ir(populations=pops))
        assert facts.neuron_models_used == {"lif", "izhikevich"}

    def test_empty_when_no_population_type(self) -> None:
        pops = {"a": PopulationIR(name="a", size=2)}
        facts = NetworkFacts.from_ir(_ir(populations=pops))
        assert facts.neuron_models_used == frozenset()
