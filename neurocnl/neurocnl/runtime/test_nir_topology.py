"""Tests for neurocnl.runtime.nir_topology — graph-shape classification."""

from __future__ import annotations

import nir
import numpy as np
import pytest

from neurocnl._nir_compat import make_nir_graph
from neurocnl.runtime.cnl_flatten import flatten_cnl_ops
from neurocnl.runtime.cnl_nodes import RLeaky, RSynaptic
from neurocnl.runtime.nir_topology import (
    classify_topology,
    linearize,
    recurrent_partner,
)


def _linear_chain_graph() -> nir.NIRGraph:
    n = 2
    return make_nir_graph(
        nodes={
            "input": nir.Input(input_type={"input": np.zeros(n)}),
            "linear": nir.Linear(weight=np.eye(n)),
            "lif": nir.LIF(
                tau=np.ones(n), r=np.ones(n), v_leak=np.zeros(n), v_threshold=np.ones(n)
            ),
            "output": nir.Output(output_type={"output": np.zeros(n)}),
        },
        edges=[("input", "linear"), ("linear", "lif"), ("lif", "output")],
    )


def _self_loop_graph() -> nir.NIRGraph:
    """Built via the real flatten_cnl_ops, so this tracks the real producer's shape."""
    n = 3
    graph = make_nir_graph(
        nodes={
            "input": nir.Input(input_type={"input": np.zeros(n)}),
            "rsyn": RSynaptic(n_neurons=n, alpha=0.9, beta=0.8),
            "output": nir.Output(output_type={"output": np.zeros(n)}),
        },
        edges=[("input", "rsyn"), ("rsyn", "output")],
    )
    flattened, _ = flatten_cnl_ops(graph)
    return flattened


def _rleaky_self_loop_graph() -> nir.NIRGraph:
    n = 2
    graph = make_nir_graph(
        nodes={
            "input": nir.Input(input_type={"input": np.zeros(n)}),
            "rleaky": RLeaky(n_neurons=n, beta=0.8),
            "output": nir.Output(output_type={"output": np.zeros(n)}),
        },
        edges=[("input", "rleaky"), ("rleaky", "output")],
    )
    flattened, _ = flatten_cnl_ops(graph)
    return flattened


def _branching_graph() -> nir.NIRGraph:
    n = 2
    return make_nir_graph(
        nodes={
            "input": nir.Input(input_type={"input": np.zeros(n)}),
            "branch_a": nir.Linear(weight=np.eye(n)),
            "branch_b": nir.Linear(weight=np.eye(n)),
            "output_a": nir.Output(output_type={"output": np.zeros(n)}),
            "output_b": nir.Output(output_type={"output": np.zeros(n)}),
        },
        edges=[
            ("input", "branch_a"),
            ("input", "branch_b"),
            ("branch_a", "output_a"),
            ("branch_b", "output_b"),
        ],
    )


def _merging_graph() -> nir.NIRGraph:
    n = 2
    return make_nir_graph(
        nodes={
            "input_a": nir.Input(input_type={"input": np.zeros(n)}),
            "input_b": nir.Input(input_type={"input": np.zeros(n)}),
            "merge": nir.Linear(weight=np.eye(n)),
            "output": nir.Output(output_type={"output": np.zeros(n)}),
        },
        edges=[("input_a", "merge"), ("input_b", "merge"), ("merge", "output")],
    )


def _non_isolated_two_cycle_graph() -> nir.NIRGraph:
    """A 2-cycle whose nodes ALSO have other real edges — must be
    classified 'branching', not tolerated as a self-loop.
    """
    n = 2
    return make_nir_graph(
        nodes={
            "input": nir.Input(input_type={"input": np.zeros(n)}),
            "a": nir.Linear(weight=np.eye(n)),
            "b": nir.Linear(weight=np.eye(n)),
            "extra_out": nir.Linear(weight=np.eye(n)),
            "output": nir.Output(output_type={"output": np.zeros(n)}),
        },
        edges=[
            ("input", "a"),
            ("a", "b"),
            ("b", "a"),
            ("b", "extra_out"),
            ("extra_out", "output"),
        ],
    )


# --- classify_topology ------------------------------------------------


def test_linear_chain_classified_as_linear() -> None:
    assert classify_topology(_linear_chain_graph()) == "linear"


def test_self_loop_classified_as_linear_with_recurrence() -> None:
    assert classify_topology(_self_loop_graph()) == "linear_with_recurrence"


def test_rleaky_self_loop_classified_as_linear_with_recurrence() -> None:
    assert classify_topology(_rleaky_self_loop_graph()) == "linear_with_recurrence"


def test_branching_graph_classified_as_branching() -> None:
    assert classify_topology(_branching_graph()) == "branching"


def test_merging_graph_classified_as_branching() -> None:
    assert classify_topology(_merging_graph()) == "branching"


def test_non_isolated_two_cycle_is_branching_not_recurrence() -> None:
    assert classify_topology(_non_isolated_two_cycle_graph()) == "branching"


def test_empty_graph_is_linear() -> None:
    empty = make_nir_graph(nodes={}, edges=[])
    assert classify_topology(empty) == "linear"


# --- linearize ----------------------------------------------------------


def test_linearize_linear_chain_excludes_boundary_nodes() -> None:
    assert linearize(_linear_chain_graph()) == ["linear", "lif"]


def test_linearize_self_loop_excludes_recurrent_partner() -> None:
    ordered = linearize(_self_loop_graph())
    assert ordered == ["rsyn"]
    assert "rsyn__rec" not in ordered


def test_linearize_self_loop_partner_queryable_separately() -> None:
    graph = _self_loop_graph()
    assert recurrent_partner(graph, "rsyn") == "rsyn__rec"
    assert recurrent_partner(graph, "input") is None


def test_linearize_branching_raises() -> None:
    with pytest.raises(ValueError, match="branching"):
        linearize(_branching_graph())


def test_linearize_no_input_raises() -> None:
    graph = make_nir_graph(
        nodes={
            "lif": nir.LIF(tau=np.ones(2), r=np.ones(2), v_leak=np.zeros(2), v_threshold=np.ones(2))
        },
        edges=[],
    )
    with pytest.raises(ValueError, match="No nir.Input"):
        linearize(graph)


def test_linearize_multiple_inputs_raises() -> None:
    """Two disconnected Input->Output chains: no single node has >1 real
    edge, so classify_topology reports 'linear' — the multiple-Input check
    inside linearize() must still catch this case on its own.
    """
    n = 2
    graph = make_nir_graph(
        nodes={
            "input_a": nir.Input(input_type={"input": np.zeros(n)}),
            "output_a": nir.Output(output_type={"output": np.zeros(n)}),
            "input_b": nir.Input(input_type={"input": np.zeros(n)}),
            "output_b": nir.Output(output_type={"output": np.zeros(n)}),
        },
        edges=[("input_a", "output_a"), ("input_b", "output_b")],
    )
    assert classify_topology(graph) == "linear"
    with pytest.raises(ValueError, match="Multiple nir.Input"):
        linearize(graph)


def test_linearize_result_order_independent_of_edge_list_order() -> None:
    """Regression test for the infinite-loop/order-dependency bug in the old
    rockpool_io.py hand-rolled walk: the result must not depend on whether
    the forward edge or the self-loop edge appears first in graph.edges.
    """
    graph = _self_loop_graph()
    reordered_edges = [e for e in graph.edges if "rsyn__rec" in e] + [
        e for e in graph.edges if "rsyn__rec" not in e
    ]
    reordered_graph = make_nir_graph(nodes=dict(graph.nodes), edges=reordered_edges)

    assert linearize(graph) == linearize(reordered_graph) == ["rsyn"]
