"""Characterization tests for `Materializer` (semantic IR -> nir.NIRGraph).

Golden-fixture gate for the Stage 6 refactor's `cnl/ir` canvas-sync
pipeline: before this test file existed, `Materializer` — the class that
turns a `NetworkIR` into the `nir.NIRGraph` the canvas renders — had zero
direct unit tests, only indirect coverage through full-stack neurosim
router tests. These pin its weight-synthesis representations, entry/exit
port synthesis, and `summarize_lowering` concept verdicts directly,
independent of the `connection_lowering`/`graph_metadata`/
`lowering_summary` module split performed in this refactor.
"""

from __future__ import annotations

import nir
import numpy as np
import pytest

from neurocnl.ir.materializer import Materializer, MaterializerError
from neurocnl.ir.types import ConnectionIR, NetworkIR, PopulationIR, SourceProvenance


def _network(**populations: PopulationIR) -> NetworkIR:
    network = NetworkIR()
    for name, pop in populations.items():
        network.populations[name] = pop
    return network


def test_materialize_basic_input_lif_output_chain() -> None:
    network = _network(
        input=PopulationIR(name="input", role="input", size=4),
        hidden=PopulationIR(name="hidden", size=4),
        output=PopulationIR(name="output", role="output", size=4),
    )
    network.connections.append(ConnectionIR(source="input", target="hidden", weight=0.5))
    network.connections.append(ConnectionIR(source="hidden", target="output", weight=1.0))

    graph = Materializer().materialize(network)

    assert isinstance(graph.nodes["input"], nir.Input)
    assert isinstance(graph.nodes["hidden"], nir.LIF)
    assert isinstance(graph.nodes["output"], nir.Output)
    weight_nodes = [name for name in graph.nodes if name.startswith("weight_")]
    assert len(weight_nodes) == 2


def test_materialize_unknown_connection_population_raises() -> None:
    network = _network(a=PopulationIR(name="a", size=2))
    network.connections.append(ConnectionIR(source="a", target="ghost", weight=1.0))
    with pytest.raises(MaterializerError, match="unknown populations"):
        Materializer().materialize(network)


def test_materialize_inserts_delay_node_when_delay_present() -> None:
    network = _network(
        a=PopulationIR(name="a", role="input", size=2),
        b=PopulationIR(name="b", role="output", size=2),
    )
    network.connections.append(ConnectionIR(source="a", target="b", weight=1.0, delay=0.005))

    graph = Materializer().materialize(network)

    delay_nodes = [node for node in graph.nodes.values() if isinstance(node, nir.Delay)]
    assert len(delay_nodes) == 1
    assert np.allclose(delay_nodes[0].delay, 0.005)


def test_materialize_one_to_one_connectivity_produces_diagonal_weight() -> None:
    network = _network(
        a=PopulationIR(name="a", role="input", size=3),
        b=PopulationIR(name="b", role="output", size=3),
    )
    network.connections.append(
        ConnectionIR(source="a", target="b", weight=2.0, connectivity_pattern="one_to_one")
    )

    graph = Materializer().materialize(network)

    weight_node = next(node for name, node in graph.nodes.items() if name.startswith("weight_"))
    weight = np.asarray(weight_node.weight)
    assert np.allclose(weight, np.diag([2.0, 2.0, 2.0]))


def test_materialize_binary_mask_connectivity_applies_mask() -> None:
    network = _network(
        a=PopulationIR(name="a", role="input", size=2),
        b=PopulationIR(name="b", role="output", size=2),
    )
    network.connections.append(
        ConnectionIR(
            source="a",
            target="b",
            weight=1.0,
            connectivity_mask=((1, 0), (0, 1)),
        )
    )

    graph = Materializer().materialize(network)

    weight_node = next(node for name, node in graph.nodes.items() if name.startswith("weight_"))
    weight = np.asarray(weight_node.weight)
    assert np.allclose(weight, np.eye(2))


def test_materialize_inhibitory_polarity_negates_weight() -> None:
    network = _network(
        a=PopulationIR(name="a", role="input", size=1),
        b=PopulationIR(name="b", role="output", size=1),
    )
    network.connections.append(
        ConnectionIR(source="a", target="b", weight=0.5, polarity="inhibitory")
    )

    graph = Materializer().materialize(network)

    weight_node = next(node for name, node in graph.nodes.items() if name.startswith("weight_"))
    assert float(np.asarray(weight_node.weight).reshape(-1)[0]) == pytest.approx(-0.5)


def test_materialize_adds_synthetic_input_for_unfed_population() -> None:
    network = _network(hidden=PopulationIR(name="hidden", size=2))
    graph = Materializer().materialize(network)

    synthetic_inputs = [name for name in graph.nodes if name.startswith("input_")]
    assert len(synthetic_inputs) == 1
    assert isinstance(graph.nodes[synthetic_inputs[0]], nir.Input)


def test_summarize_lowering_axonal_delay_verdict() -> None:
    network = _network(
        a=PopulationIR(
            name="a",
            provenance=[SourceProvenance(concept="axonal_delay")],
        ),
        b=PopulationIR(name="b"),
    )
    network.connections.append(ConnectionIR(source="a", target="b", delay=0.01))
    network.populations["a"].provenance = [SourceProvenance(concept="axonal_delay")]

    summary = Materializer().summarize_lowering(network)

    assert summary.concept_verdicts["axonal_delay"] == "lowered_faithfully"
    assert summary.connection_summary["delay_nodes"] == 1


def test_summarize_lowering_unrecognised_concept_is_not_lowered() -> None:
    network = _network(
        a=PopulationIR(name="a", provenance=[SourceProvenance(concept="totally_unknown")])
    )
    summary = Materializer().summarize_lowering(network)
    assert summary.concept_verdicts["totally_unknown"] == "not_lowered"


def test_population_size_mismatch_with_shape_raises() -> None:
    with pytest.raises(ValueError, match="does not match shape product"):
        PopulationIR(name="bad", shape=(2, 2), size=3)
