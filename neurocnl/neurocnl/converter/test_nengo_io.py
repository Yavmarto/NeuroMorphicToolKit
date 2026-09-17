"""Regression tests for NengoIO.from_nir()'s NIR-to-Nengo code generation.

Oracle for the numeric conventions asserted here: paper/03_rnn/nir_to_nengo.py.
"""

import math
from typing import Any

import nir
import numpy as np
import pytest

from neurocnl.converter.nengo_io import NengoIO


def _feedforward_cubalif_graph() -> nir.NIRGraph:
    """Input -> Linear -> CubaLIF -> Output (non-recurrent, plain cnl.Synaptic shape)."""
    return nir.NIRGraph(
        nodes={
            "input": nir.Input(input_type={"input": np.array([2])}),
            "fc": nir.Linear(weight=np.eye(3, 2)),
            "cuba": nir.CubaLIF(
                tau_syn=np.array([0.01, 0.01, 0.01]),
                tau_mem=np.array([0.02, 0.02, 0.02]),
                r=np.array([1.0, 1.0, 1.0]),
                v_leak=np.array([0.0, 0.0, 0.0]),
                v_threshold=np.array([1.0, 1.0, 1.0]),
                w_in=np.array([1.0, 1.0, 1.0]),
            ),
            "output": nir.Output(output_type={"output": np.array([3])}),
        },
        edges=[("input", "fc"), ("fc", "cuba"), ("cuba", "output")],
        type_check=False,
    )


def _rsynaptic_shaped_graph() -> nir.NIRGraph:
    """Mirrors cnl.RSynaptic's real NIR shape: a flat nir.CubaLIF plus a
    same-population nir.Linear whose edges form a self-loop
    (lif1_lif -> lif1_w_rec -> lif1_lif), NOT a nested nir.NIRGraph subgraph.
    """
    return nir.NIRGraph(
        nodes={
            "input": nir.Input(input_type={"input": np.array([2])}),
            "fc1": nir.Linear(weight=np.eye(3, 2)),
            "lif1_lif": nir.CubaLIF(
                tau_syn=np.array([0.01, 0.01, 0.01]),
                tau_mem=np.array([0.02, 0.02, 0.02]),
                r=np.array([1.0, 1.0, 1.0]),
                v_leak=np.array([0.0, 0.0, 0.0]),
                v_threshold=np.array([1.0, 1.0, 1.0]),
                w_in=np.array([1.0, 1.0, 1.0]),
            ),
            "lif1_w_rec": nir.Linear(weight=np.zeros((3, 3))),
            "fc2": nir.Linear(weight=np.eye(2, 3)),
            "lif2": nir.CubaLIF(
                tau_syn=np.array([0.01, 0.01]),
                tau_mem=np.array([0.02, 0.02]),
                r=np.array([1.0, 1.0]),
                v_leak=np.array([0.0, 0.0]),
                v_threshold=np.array([1.0, 1.0]),
                w_in=np.array([1.0, 1.0]),
            ),
            "output": nir.Output(output_type={"output": np.array([2])}),
        },
        edges=[
            ("input", "fc1"),
            ("fc1", "lif1_lif"),
            ("lif1_lif", "lif1_w_rec"),
            ("lif1_w_rec", "lif1_lif"),
            ("lif1_lif", "fc2"),
            ("fc2", "lif2"),
            ("lif2", "output"),
        ],
        type_check=False,
    )


def test_input_output_nodes_generated() -> None:
    """Regression: from_nir previously had no nir.Input/nir.Output handling
    at all, so any real graph (which always has these) silently produced
    incomplete code."""
    code = NengoIO().from_nir(_feedforward_cubalif_graph())
    assert "input = nengo.Node(None, size_in=2" in code
    assert "output = nengo.Node(None, size_in=3" in code


def test_cubalif_gain_and_tau_syn_correction() -> None:
    """Regression: the old code assumed nir.CubaLIF has a `.tau` attribute
    (it doesn't -- tau_syn/tau_mem instead) and crashed with AttributeError
    on any real CubaLIF node. Pin the exact tau_syn correction formula and
    gain vector against the oracle's nir_to_nengo.py CubaLIF branch."""
    dt = 1e-4
    tau_syn = 0.01
    expected_tau_syn_corrected = -dt / math.log(1 - dt / tau_syn)
    code = NengoIO().from_nir(_feedforward_cubalif_graph(), dt=dt)
    assert "nengo.Ensemble(n_neurons=3" in code
    assert f"tau_rc={0.02:.8f}" in code
    assert f"amplitude={dt:.8f}" in code
    assert f"nengo.synapses.Lowpass({expected_tau_syn_corrected:.10f})" in code
    # gain = w_in * r / v_threshold = [1,1,1] * 1.0 / 1.0
    assert "gain=np.array([1.0, 1.0, 1.0]) * 1.00000000" in code


def test_linear_becomes_node_not_connection_transform() -> None:
    """Regression: weights must be emitted as a Node computing weight @ x
    (oracle's design), not folded into Connection(transform=...) -- the
    generic edge-replay loop depends on every node being addressable as a
    plain pre/post endpoint."""
    code = NengoIO().from_nir(_feedforward_cubalif_graph())
    assert "_w @ x" in code
    assert "transform=" not in code


def test_rsynaptic_self_loop_gets_filter_on_both_edges() -> None:
    """The recurrent self-loop (lif1_w_rec -> lif1_lif) and the feedforward
    edge (fc1 -> lif1_lif) must both receive the CubaLIF's Lowpass filter --
    with zero special-casing for "is this recurrent", exactly like the
    oracle's generic `filters.get(post)` edge-replay."""
    code = NengoIO().from_nir(_rsynaptic_shaped_graph())
    ns: dict[str, Any] = {}
    exec(compile(code, "<generated_nengo_net>", "exec"), ns)
    model = ns["model"]
    lif1_neurons = ns["lif1_lif"]

    incoming = [c for c in model.all_connections if c.post_obj is lif1_neurons]
    assert len(incoming) == 2
    for conn in incoming:
        assert conn.synapse is not None
        assert conn.synapse.tau > 0


def test_unsupported_node_type_raises() -> None:
    """Unrecognized NIR node types must raise loudly, not silently degrade --
    the previous silent-failure mode (an AttributeError swallowed elsewhere
    into a scaffold comment) is exactly how the CubaLIF gap went undetected."""
    graph = nir.NIRGraph(
        nodes={
            "input": nir.Input(input_type={"input": np.array([2])}),
            "flat": nir.Flatten(
                input_type={"input": np.array([2])},
                start_dim=1,
                end_dim=-1,
            ),
            "output": nir.Output(output_type={"output": np.array([2])}),
        },
        edges=[("input", "flat"), ("flat", "output")],
        type_check=False,
    )
    with pytest.raises(ValueError, match="Unsupported NIR node type"):
        NengoIO().from_nir(graph)


def test_generated_network_builds_and_simulates() -> None:
    """Execution-level smoke test: the generated code must build a real
    nengo.Network and produce at least one spike under a constant nonzero
    input -- not just parse as valid Python. Uses a lower threshold than the
    other fixtures purely so a spike is guaranteed within a short sim run."""
    nengo = pytest.importorskip("nengo")

    graph = nir.NIRGraph(
        nodes={
            "input": nir.Input(input_type={"input": np.array([2])}),
            "fc": nir.Linear(weight=np.ones((3, 2))),
            "cuba": nir.CubaLIF(
                tau_syn=np.array([0.01, 0.01, 0.01]),
                tau_mem=np.array([0.02, 0.02, 0.02]),
                r=np.array([1.0, 1.0, 1.0]),
                v_leak=np.array([0.0, 0.0, 0.0]),
                v_threshold=np.array([0.5, 0.5, 0.5]),
                w_in=np.array([1.0, 1.0, 1.0]),
            ),
            "output": nir.Output(output_type={"output": np.array([3])}),
        },
        edges=[("input", "fc"), ("fc", "cuba"), ("cuba", "output")],
        type_check=False,
    )
    code = NengoIO().from_nir(graph)
    ns: dict[str, Any] = {}
    exec(compile(code, "<generated_nengo_net>", "exec"), ns)
    model = ns["model"]
    cuba_neurons = ns["cuba"]
    input_node = ns["input"]

    with model:
        stim = nengo.Node(lambda t: [1.0, 1.0])
        nengo.Connection(stim, input_node, synapse=None)
        p_spikes = nengo.Probe(cuba_neurons)

    with nengo.Simulator(model, dt=1e-4, progress_bar=False) as sim:
        sim.run(0.05)

    assert (sim.data[p_spikes] > 0).sum() > 0
