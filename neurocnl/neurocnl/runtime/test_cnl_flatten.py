"""Tests for neurocnl.runtime.cnl_flatten — cnl.* -> standard NIR lowering."""

from __future__ import annotations


import nir
import numpy as np
import pytest

from neurocnl._nir_compat import make_nir_graph
from neurocnl.lif_semantics import DEFAULT_LIF_DT_SECONDS, decay_from_tau
from neurocnl.runtime.cnl_flatten import flatten_cnl_ops
from neurocnl.runtime.cnl_nodes import (
    BatchNorm1d,
    Dropout,
    Leaky,
    RLeaky,
    RSynaptic,
    Synaptic,
)
from neurocnl.runtime.nir_support import classify_nir_graph


def _wrap(name: str, node: object) -> nir.NIRGraph:
    """Wrap a single cnl.* node between Input/Output boundary nodes."""
    return make_nir_graph(
        nodes={
            "input": nir.Input(input_type={"input": np.array([2])}),
            name: node,
            "output": nir.Output(output_type={"output": np.array([2])}),
        },
        edges=[("input", name), (name, "output")],
    )


def test_no_cnl_nodes_is_noop() -> None:
    graph = make_nir_graph(
        nodes={
            "input": nir.Input(input_type={"input": np.array([2])}),
            "fc": nir.Linear(weight=np.eye(2)),
            "output": nir.Output(output_type={"output": np.array([2])}),
        },
        edges=[("input", "fc"), ("fc", "output")],
    )
    flattened, diagnostics = flatten_cnl_ops(graph)
    assert diagnostics == []
    assert set(flattened.nodes) == set(graph.nodes)
    assert flattened.edges == graph.edges


def test_leaky_flattens_to_lif_with_inverse_tau() -> None:
    """beta is a per-step decay; tau is seconds. tau = dt/(1-beta).

    The old inverse was ``-1/log(beta)``, which produced a time constant in
    *timesteps* inside a seconds-typed field.
    """
    graph = _wrap("leaky", Leaky(n_neurons=3, beta=0.8, threshold=1.0))
    flattened, diagnostics = flatten_cnl_ops(graph)
    assert diagnostics == []
    node = flattened.nodes["leaky"]
    assert isinstance(node, nir.LIF)
    tau = float(np.asarray(node.tau).flat[0])
    assert tau == pytest.approx(DEFAULT_LIF_DT_SECONDS / (1 - 0.8))
    assert decay_from_tau(tau, DEFAULT_LIF_DT_SECONDS) == pytest.approx(0.8)
    assert np.all(np.asarray(node.v_threshold) == 1.0)
    assert set(flattened.nodes) == {"input", "leaky", "output"}
    assert flattened.edges == [("input", "leaky"), ("leaky", "output")]


def test_leaky_inverse_honours_the_nodes_recorded_timestep() -> None:
    """A node that records its own dt round-trips at that dt, not the default."""
    graph = _wrap("leaky", Leaky(n_neurons=3, beta=0.8, metadata={"dt": 0.001}))
    flattened, _ = flatten_cnl_ops(graph)
    tau = float(np.asarray(flattened.nodes["leaky"].tau).flat[0])
    assert tau == pytest.approx(0.001 / (1 - 0.8))
    assert decay_from_tau(tau, 0.001) == pytest.approx(0.8)


def test_synaptic_flattens_to_cubalif_with_inverse_tau() -> None:
    graph = _wrap("syn", Synaptic(n_neurons=2, alpha=0.9, beta=0.8, threshold=1.0))
    flattened, diagnostics = flatten_cnl_ops(graph)
    assert diagnostics == []
    node = flattened.nodes["syn"]
    assert isinstance(node, nir.CubaLIF)
    tau_syn = float(np.asarray(node.tau_syn).flat[0])
    tau_mem = float(np.asarray(node.tau_mem).flat[0])
    assert tau_syn == pytest.approx(DEFAULT_LIF_DT_SECONDS / (1 - 0.9))
    assert tau_mem == pytest.approx(DEFAULT_LIF_DT_SECONDS / (1 - 0.8))


def test_distinct_decays_stay_distinct_after_flattening() -> None:
    """Regression for the clamp that collapsed every tau onto one value.

    ``exp(-1/tau)`` clamped to [0.01, 0.99] mapped every time constant below
    ~0.22 s to exactly 0.01, so two populations with different taus came back
    identical.
    """
    graph = _wrap("syn", Synaptic(n_neurons=2, alpha=0.9, beta=0.8))
    node = flatten_cnl_ops(graph)[0].nodes["syn"]
    assert float(np.asarray(node.tau_syn).flat[0]) != pytest.approx(
        float(np.asarray(node.tau_mem).flat[0])
    )


def test_leaky_zero_reset_sets_v_reset_and_emits_diagnostic() -> None:
    graph = _wrap("leaky", Leaky(n_neurons=2, reset_mechanism="zero"))
    flattened, diagnostics = flatten_cnl_ops(graph)
    node = flattened.nodes["leaky"]
    if hasattr(node, "v_reset") and node.v_reset is not None:
        assert np.all(np.asarray(node.v_reset) == 0)
    assert any("reset_mechanism='zero'" in d for d in diagnostics)


def test_rsynaptic_gains_recurrent_linear_self_loop() -> None:
    graph = _wrap("rsyn", RSynaptic(n_neurons=3, alpha=0.9, beta=0.8))
    flattened, diagnostics = flatten_cnl_ops(graph)
    assert set(flattened.nodes) == {"input", "rsyn", "rsyn__rec", "output"}
    assert isinstance(flattened.nodes["rsyn"], nir.CubaLIF)
    rec = flattened.nodes["rsyn__rec"]
    assert isinstance(rec, nir.Linear)
    assert np.array_equal(rec.weight, np.eye(3))
    assert ("rsyn", "rsyn__rec") in flattened.edges
    assert ("rsyn__rec", "rsyn") in flattened.edges
    assert ("input", "rsyn") in flattened.edges
    assert ("rsyn", "output") in flattened.edges
    assert any("structural-only" in d for d in diagnostics)


def test_rsynaptic_with_recurrent_weight_uses_it_instead_of_identity() -> None:
    weight = [[0.5, -0.25], [0.1, 0.75]]
    graph = _wrap(
        "rsyn",
        RSynaptic(n_neurons=2, alpha=0.9, beta=0.8, recurrent_weight=weight),
    )
    flattened, diagnostics = flatten_cnl_ops(graph)
    rec = flattened.nodes["rsyn__rec"]
    assert isinstance(rec, nir.Linear)
    assert np.allclose(rec.weight, np.asarray(weight, dtype=float))
    assert not np.array_equal(rec.weight, np.eye(2))
    assert not any("structural-only" in d for d in diagnostics)
    assert not any("no stored recurrent weight matrix" in d for d in diagnostics)
    assert any("previously trained/imported checkpoint" in d for d in diagnostics)


def test_rsynaptic_without_recurrent_weight_falls_back_to_identity() -> None:
    graph = _wrap("rsyn", RSynaptic(n_neurons=3, alpha=0.9, beta=0.8))
    flattened, diagnostics = flatten_cnl_ops(graph)
    rec = flattened.nodes["rsyn__rec"]
    assert isinstance(rec, nir.Linear)
    assert np.array_equal(rec.weight, np.eye(3))
    assert any("structural-only" in d for d in diagnostics)
    assert not any("previously trained/imported checkpoint" in d for d in diagnostics)


def test_rsynaptic_use_bias_emits_dropped_diagnostic() -> None:
    graph = _wrap("rsyn", RSynaptic(n_neurons=2, use_bias=True))
    _, diagnostics = flatten_cnl_ops(graph)
    assert any("use_bias=True" in d for d in diagnostics)


def test_rleaky_gains_recurrent_linear_self_loop() -> None:
    graph = _wrap("rleaky", RLeaky(n_neurons=2, beta=0.8))
    flattened, diagnostics = flatten_cnl_ops(graph)
    assert isinstance(flattened.nodes["rleaky"], nir.LIF)
    assert isinstance(flattened.nodes["rleaky__rec"], nir.Linear)
    assert ("rleaky", "rleaky__rec") in flattened.edges
    assert ("rleaky__rec", "rleaky") in flattened.edges
    assert any("structural-only" in d for d in diagnostics)


def test_rsynaptic_flattened_graph_no_longer_unsupported_for_nengo() -> None:
    graph = _wrap("rsyn", RSynaptic(n_neurons=2, alpha=0.9, beta=0.8))
    flattened, _ = flatten_cnl_ops(graph)
    result = classify_nir_graph(flattened, "nengo")
    assert "RSynaptic" not in result.unsupported_nodes
    assert "Synaptic" not in result.unsupported_nodes


def test_batchnorm1d_spliced_out_with_diagnostic() -> None:
    graph = _wrap("bn", BatchNorm1d(num_features=2))
    flattened, diagnostics = flatten_cnl_ops(graph)
    assert "bn" not in flattened.nodes
    assert set(flattened.nodes) == {"input", "output"}
    assert ("input", "output") in flattened.edges
    assert any("no stored running stats" in d for d in diagnostics)


def test_dropout_spliced_out_with_no_diagnostic() -> None:
    graph = _wrap("drop", Dropout(p=0.5))
    flattened, diagnostics = flatten_cnl_ops(graph)
    assert "drop" not in flattened.nodes
    assert set(flattened.nodes) == {"input", "output"}
    assert ("input", "output") in flattened.edges
    assert diagnostics == []


def test_idempotent_on_already_flattened_graph() -> None:
    graph = _wrap("rsyn", RSynaptic(n_neurons=2, alpha=0.9, beta=0.8))
    once, _ = flatten_cnl_ops(graph)
    twice, diagnostics_twice = flatten_cnl_ops(once)
    assert set(once.nodes) == set(twice.nodes)
    assert sorted(once.edges) == sorted(twice.edges)
    assert diagnostics_twice == []
