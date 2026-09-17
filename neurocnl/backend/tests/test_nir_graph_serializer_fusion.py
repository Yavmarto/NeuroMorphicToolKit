from __future__ import annotations

import numpy as np
import pytest

from backend.app.services.nir_graph_serializer import (
    deserialize_canvas_graph,
    serialize_nir_to_canvas_graph,
)
from neurocnl.runtime.cnl_nodes import RSynaptic, Synaptic

nir = pytest.importorskip("nir")


# ---------------------------------------------------------------------------
# Task 1: NIR import fusion — CubaLIF + self-loop-Linear -> cnl.RSynaptic
# ---------------------------------------------------------------------------
#
# These reproduce the exact node/edge shape found in the real reference file
# paper/03_rnn/braille_noDelay_noBias_subtract.nir (confirmed via `nir.read()`):
#   input -> fc1 -> lif1.lif -> fc2 -> lif2 -> output
#   lif1.lif <-> lif1.w_rec (isolated 2-cycle self-loop, nir.Linear)
# where lif1.lif/lif1.w_rec is the recurrent pair to fuse into cnl.RSynaptic,
# and lif2 is the immediately-following output-stage CubaLIF that must be
# retyped to cnl.Synaptic for exact (not approximate) snntorch_sim fidelity.


def _braille_shape_graph(
    *,
    recurrent_weight: np.ndarray,
    n_lif1: int = 2,
    n_lif2: int = 2,
    tau_syn_lif1: float = 0.004,
    tau_mem_lif1: float = 0.006,
    tau_syn_lif2: float = 0.002,
    tau_mem_lif2: float = 0.003,
) -> nir.NIRGraph:
    from neurocnl._nir_compat import make_nir_graph

    return make_nir_graph(
        nodes={
            "input": nir.Input(input_type={"input": np.array([n_lif1])}),
            "fc1": nir.Linear(weight=np.eye(n_lif1)),
            "lif1.lif": nir.CubaLIF(
                tau_syn=np.full(n_lif1, tau_syn_lif1),
                tau_mem=np.full(n_lif1, tau_mem_lif1),
                r=np.ones(n_lif1),
                v_leak=np.zeros(n_lif1),
                v_threshold=np.ones(n_lif1),
                w_in=np.full(n_lif1, 4.0),
            ),
            "lif1.w_rec": nir.Linear(weight=recurrent_weight),
            "fc2": nir.Linear(weight=np.eye(n_lif2, n_lif1)),
            "lif2": nir.CubaLIF(
                tau_syn=np.full(n_lif2, tau_syn_lif2),
                tau_mem=np.full(n_lif2, tau_mem_lif2),
                r=np.ones(n_lif2),
                v_leak=np.zeros(n_lif2),
                v_threshold=np.ones(n_lif2),
                w_in=np.full(n_lif2, 1.8),
            ),
            "output": nir.Output(output_type={"output": np.array([n_lif2])}),
        },
        edges=[
            ("input", "fc1"),
            ("fc1", "lif1.lif"),
            ("lif1.lif", "lif1.w_rec"),
            ("lif1.w_rec", "lif1.lif"),
            ("lif1.lif", "fc2"),
            ("fc2", "lif2"),
            ("lif2", "output"),
        ],
    )


def test_import_fuses_cubalif_self_loop_into_single_rsynaptic_and_synaptic() -> None:
    """Core structural assertion: importing the braille-shaped graph produces
    exactly one cnl.RSynaptic (carrying the real recurrent weight) and one
    cnl.Synaptic, with the self-loop partner node fully dropped — no orphans.
    """
    recurrent_weight = np.array([[0.5, -0.25], [0.1, 0.75]])
    graph = _braille_shape_graph(recurrent_weight=recurrent_weight)

    canvas_graph = serialize_nir_to_canvas_graph(graph)

    node_by_id = {node.id: node for node in canvas_graph.nodes}
    assert set(node_by_id) == {"input", "fc1", "lif1.lif", "fc2", "lif2", "output"}
    assert "lif1.w_rec" not in node_by_id, "self-loop partner must not survive fusion"

    rsynaptic_nodes = [n for n in canvas_graph.nodes if n.nir_type == "cnl.RSynaptic"]
    synaptic_nodes = [n for n in canvas_graph.nodes if n.nir_type == "cnl.Synaptic"]
    cubalif_nodes = [n for n in canvas_graph.nodes if n.nir_type == "nir.CubaLIF"]
    assert len(rsynaptic_nodes) == 1
    assert len(synaptic_nodes) == 1
    assert cubalif_nodes == [], "both CubaLIF nodes must have been retyped"

    assert rsynaptic_nodes[0].id == "lif1.lif"
    assert synaptic_nodes[0].id == "lif2"

    assert (
        rsynaptic_nodes[0].parameters["recurrent_weight_matrix"]
        == recurrent_weight.tolist()
    )
    assert rsynaptic_nodes[0].parameters["n_neurons"] == 2

    # fc1/fc2 (plain forward Linear transforms) must be untouched.
    assert node_by_id["fc1"].nir_type == "nir.Linear"
    assert node_by_id["fc2"].nir_type == "nir.Linear"

    # Edge count: 7 original edges minus the 2 self-loop edges.
    assert len(canvas_graph.edges) == 5
    edge_pairs = {(e.source_node_id, e.target_node_id) for e in canvas_graph.edges}
    assert ("lif1.lif", "lif1.w_rec") not in edge_pairs
    assert ("lif1.w_rec", "lif1.lif") not in edge_pairs
    assert ("lif1.lif", "fc2") in edge_pairs


def test_import_fusion_deserializes_back_to_rsynaptic_and_synaptic_nir_nodes() -> None:
    """The fused canvas graph must deserialize back into a NIR graph actually
    containing cnl_nodes.RSynaptic/Synaptic instances (not just canvas JSON
    labels), with the recurrent weight intact and no self-loop edges.
    """
    recurrent_weight = np.array([[0.2, 0.4], [0.6, 0.8]])
    graph = _braille_shape_graph(recurrent_weight=recurrent_weight)

    canvas_graph = serialize_nir_to_canvas_graph(graph)
    roundtrip = deserialize_canvas_graph(canvas_graph)

    assert set(roundtrip.nodes) == {"input", "fc1", "lif1.lif", "fc2", "lif2", "output"}
    assert isinstance(roundtrip.nodes["lif1.lif"], RSynaptic)
    assert isinstance(roundtrip.nodes["lif2"], Synaptic)
    assert roundtrip.nodes["lif1.lif"].recurrent_weight == recurrent_weight.tolist()
    assert ("lif1.lif", "lif1.w_rec") not in roundtrip.edges
    assert all("lif1.w_rec" not in edge for edge in roundtrip.edges)


def test_fuse_recurrent_pairs_leaves_branching_graph_unchanged() -> None:
    """classify_topology == 'branching' must bail out entirely: a self-loop
    coexisting with genuine fan-out on the same forward node is not fused.
    """
    from neurocnl._nir_compat import make_nir_graph

    n = 2
    recurrent_weight = np.eye(n)
    graph = make_nir_graph(
        nodes={
            "input": nir.Input(input_type={"input": np.zeros(n)}),
            "lif1.lif": nir.CubaLIF(
                tau_syn=np.full(n, 0.01),
                tau_mem=np.full(n, 0.02),
                r=np.ones(n),
                v_leak=np.zeros(n),
                v_threshold=np.ones(n),
            ),
            "lif1.w_rec": nir.Linear(weight=recurrent_weight),
            "branch_a": nir.Linear(weight=np.eye(n)),
            "branch_b": nir.Linear(weight=np.eye(n)),
            "output_a": nir.Output(output_type={"output": np.zeros(n)}),
            "output_b": nir.Output(output_type={"output": np.zeros(n)}),
        },
        edges=[
            ("input", "lif1.lif"),
            ("lif1.lif", "lif1.w_rec"),
            ("lif1.w_rec", "lif1.lif"),
            ("lif1.lif", "branch_a"),
            ("lif1.lif", "branch_b"),
            ("branch_a", "output_a"),
            ("branch_b", "output_b"),
        ],
    )

    canvas_graph = serialize_nir_to_canvas_graph(graph)

    node_types = {node.id: node.nir_type for node in canvas_graph.nodes}
    assert node_types["lif1.lif"] == "nir.CubaLIF"
    assert node_types["lif1.w_rec"] == "nir.Linear"
    assert "cnl.RSynaptic" not in node_types.values()


def test_fuse_recurrent_pairs_does_not_fuse_plain_lif_self_loop() -> None:
    """Narrow-rule check: only a CubaLIF + self-loop-Linear pair is fused.
    A plain nir.LIF self-loop (which would correspond to cnl.RLeaky, not
    cnl.RSynaptic) must be left alone by this CubaLIF-only fusion.
    """
    from neurocnl._nir_compat import make_nir_graph

    n = 2
    graph = make_nir_graph(
        nodes={
            "input": nir.Input(input_type={"input": np.zeros(n)}),
            "rleaky.lif": nir.LIF(
                tau=np.full(n, 0.02),
                r=np.ones(n),
                v_leak=np.zeros(n),
                v_threshold=np.ones(n),
            ),
            "rleaky.w_rec": nir.Linear(weight=np.eye(n)),
            "output": nir.Output(output_type={"output": np.zeros(n)}),
        },
        edges=[
            ("input", "rleaky.lif"),
            ("rleaky.lif", "rleaky.w_rec"),
            ("rleaky.w_rec", "rleaky.lif"),
            ("rleaky.lif", "output"),
        ],
    )

    canvas_graph = serialize_nir_to_canvas_graph(graph)

    node_types = {node.id: node.nir_type for node in canvas_graph.nodes}
    assert node_types["rleaky.lif"] == "nir.LIF"
    assert node_types["rleaky.w_rec"] == "nir.Linear"
    assert "cnl.RSynaptic" not in node_types.values()


def test_fused_rsynaptic_recurrent_weight_actually_drives_snntorch_simulation() -> None:
    """Fidelity check for snntorch_simulator.py's RSynaptic construction: an
    imported graph's real recurrent weight must be copied into
    snntorch.RSynaptic.recurrent.weight and actually influence the
    simulation — not silently ignored in favour of snnTorch's own random
    initialisation. Proven here by showing two otherwise-identical fused
    graphs that differ only in recurrent_weight produce different spike
    output under the same stimulus/seed/timesteps.
    """
    pytest.importorskip("torch")
    pytest.importorskip("snntorch")
    from neurocnl.runtime.snntorch_simulator import SnnTorchSimulatorAdapter
    from neurocnl.runtime.stimulus import ValidatedStimulus

    def _simulate(recurrent_weight: np.ndarray) -> dict:
        graph = _braille_shape_graph(recurrent_weight=recurrent_weight)
        canvas_graph = serialize_nir_to_canvas_graph(graph)
        fused_graph = deserialize_canvas_graph(canvas_graph)
        stimulus = ValidatedStimulus(
            population="input", neuron_count=2, spikes={0: [0, 1, 2, 3]}
        )
        result = SnnTorchSimulatorAdapter().run(
            fused_graph, stimulus, timesteps=15, seed=0
        )
        return result.voltages

    zero_weight_voltages = _simulate(np.zeros((2, 2)))
    strong_weight_voltages = _simulate(np.full((2, 2), 5.0))

    assert zero_weight_voltages != strong_weight_voltages, (
        "changing the imported recurrent_weight had no effect on the simulated "
        "trace — snntorch_simulator is not actually loading it into "
        "snntorch.RSynaptic.recurrent.weight"
    )


def _chained_recurrent_blocks_graph(
    *,
    a_recurrent_weight: np.ndarray,
    b_recurrent_weight: np.ndarray,
    self_loop_edge_order: str = "a_first",
) -> nir.NIRGraph:
    """Two chained CubaLIF+self-loop-Linear recurrent blocks: A -> mid
    (a plain feedforward nir.Linear, no neuron) -> B, where B is itself a
    SECOND independently-fusable recurrent block -- not a plain
    output-stage CubaLIF. `self_loop_edge_order` controls whether A's or
    B's self-loop forward edge appears first in `graph.edges`, which is
    what determines `_self_loop_partners`/`fuse_recurrent_pairs`'s
    `fusable` dict iteration order.
    """
    from neurocnl._nir_compat import make_nir_graph

    n = 2
    a_block_edges = [
        ("input", "a.lif"),
        ("a.lif", "a.w_rec"),
        ("a.w_rec", "a.lif"),
    ]
    b_block_edges = [
        ("mid", "b.lif"),
        ("b.lif", "b.w_rec"),
        ("b.w_rec", "b.lif"),
        ("b.lif", "output"),
    ]
    bridging_edge = ("a.lif", "mid")

    if self_loop_edge_order == "a_first":
        edges = [*a_block_edges, bridging_edge, *b_block_edges]
    elif self_loop_edge_order == "b_first":
        edges = [*b_block_edges, bridging_edge, *a_block_edges]
    else:
        raise ValueError(self_loop_edge_order)

    return make_nir_graph(
        nodes={
            "input": nir.Input(input_type={"input": np.zeros(n)}),
            "a.lif": nir.CubaLIF(
                tau_syn=np.full(n, 0.01),
                tau_mem=np.full(n, 0.02),
                r=np.ones(n),
                v_leak=np.zeros(n),
                v_threshold=np.ones(n),
            ),
            "a.w_rec": nir.Linear(weight=a_recurrent_weight),
            "mid": nir.Linear(weight=np.eye(n)),
            "b.lif": nir.CubaLIF(
                tau_syn=np.full(n, 0.015),
                tau_mem=np.full(n, 0.025),
                r=np.ones(n),
                v_leak=np.zeros(n),
                v_threshold=np.ones(n),
            ),
            "b.w_rec": nir.Linear(weight=b_recurrent_weight),
            "output": nir.Output(output_type={"output": np.zeros(n)}),
        },
        edges=edges,
    )


@pytest.mark.parametrize("self_loop_edge_order", ["a_first", "b_first"])
def test_fuse_recurrent_pairs_chained_recurrent_blocks_both_stay_rsynaptic(
    self_loop_edge_order: str,
) -> None:
    """Regression test for the chained-recurrent-block retype-order bug.

    When block A's successor-walk (`_next_neuron_node`) reaches block B --
    a second, independently fusable CubaLIF+self-loop-Linear pair, not a
    plain output-stage CubaLIF -- B's already-correct RSynaptic retyping
    must not be overwritten back to plain Synaptic just because it happens
    to be "the next neuron after A".

    Parametrized over both possible `fusable` iteration orders
    (`_self_loop_partners`'s dict order follows whichever self-loop's
    forward edge appears first in `graph.edges`): under the old
    `.flat[0]`/pristine-`graph`-read bug this test would fail for
    `"b_first"` (B gets fused correctly, then A's successor-walk clobbers
    it back to Synaptic) while `"a_first"` happened to self-correct. The
    fix makes the result invariant to iteration order, so both orders must
    produce the same correct outcome.
    """
    a_recurrent_weight = np.array([[0.5, -0.25], [0.1, 0.75]])
    b_recurrent_weight = np.array([[0.2, 0.4], [0.6, 0.8]])
    graph = _chained_recurrent_blocks_graph(
        a_recurrent_weight=a_recurrent_weight,
        b_recurrent_weight=b_recurrent_weight,
        self_loop_edge_order=self_loop_edge_order,
    )

    canvas_graph = serialize_nir_to_canvas_graph(graph)

    node_by_id = {node.id: node for node in canvas_graph.nodes}
    assert "a.w_rec" not in node_by_id
    assert "b.w_rec" not in node_by_id
    assert (
        node_by_id["a.lif"].nir_type == "cnl.RSynaptic"
    ), "block A must remain RSynaptic"
    assert node_by_id["b.lif"].nir_type == "cnl.RSynaptic", (
        "block B must remain RSynaptic -- must not have been clobbered "
        "back to Synaptic by block A's successor-walk"
    )
    assert (
        node_by_id["a.lif"].parameters["recurrent_weight_matrix"]
        == a_recurrent_weight.tolist()
    )
    assert (
        node_by_id["b.lif"].parameters["recurrent_weight_matrix"]
        == b_recurrent_weight.tolist()
    )


def test_fuse_recurrent_pairs_threshold_uses_mean_not_first_element() -> None:
    """Regression test: fused RSynaptic/Synaptic threshold must be the mean
    over the population's v_threshold array -- the established convention
    in snntorch_simulator._lif_threshold -- not just the first neuron's
    value (what `.flat[0]` silently used to compute).
    """
    from neurocnl._nir_compat import make_nir_graph

    n = 2
    graph = make_nir_graph(
        nodes={
            "input": nir.Input(input_type={"input": np.zeros(n)}),
            "fc1": nir.Linear(weight=np.eye(n)),
            "lif1.lif": nir.CubaLIF(
                tau_syn=np.full(n, 0.01),
                tau_mem=np.full(n, 0.02),
                r=np.ones(n),
                v_leak=np.zeros(n),
                v_threshold=np.array([0.5, 1.5]),
            ),
            "lif1.w_rec": nir.Linear(weight=np.eye(n)),
            "lif2": nir.CubaLIF(
                tau_syn=np.full(n, 0.015),
                tau_mem=np.full(n, 0.025),
                r=np.ones(n),
                v_leak=np.zeros(n),
                v_threshold=np.array([2.0, 4.0]),
            ),
            "output": nir.Output(output_type={"output": np.zeros(n)}),
        },
        edges=[
            ("input", "fc1"),
            ("fc1", "lif1.lif"),
            ("lif1.lif", "lif1.w_rec"),
            ("lif1.w_rec", "lif1.lif"),
            ("lif1.lif", "lif2"),
            ("lif2", "output"),
        ],
    )

    canvas_graph = serialize_nir_to_canvas_graph(graph)

    node_by_id = {node.id: node for node in canvas_graph.nodes}
    assert node_by_id["lif1.lif"].nir_type == "cnl.RSynaptic"
    assert node_by_id["lif1.lif"].parameters["threshold"] == pytest.approx(1.0), (
        "RSynaptic threshold must be the mean of v_threshold=[0.5, 1.5] (1.0), "
        "not the first element (0.5)"
    )
    assert node_by_id["lif2"].nir_type == "cnl.Synaptic"
    assert node_by_id["lif2"].parameters["threshold"] == pytest.approx(3.0), (
        "Synaptic threshold must be the mean of v_threshold=[2.0, 4.0] (3.0), "
        "not the first element (2.0)"
    )
