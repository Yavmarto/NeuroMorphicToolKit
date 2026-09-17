"""Trained weights from a NIR graph must reach the PYNQ deploy payload.

Regression cover for the gap this module exists to close: the CNL spec carries
tensor *shape* only, so before the sidecar a trained network deployed with an
all-zero weight matrix — correct shape, correct synapse count, every value 0.0 —
loaded the overlay and fired nothing.
"""

from __future__ import annotations

import numpy as np
import nir
import pytest

from backend.app.services.pynq_trained_weights import (
    TrainedWeightError,
    apply_trained_weights,
    apply_trained_weights_to_graph,
    graph_is_all_zero,
    load_trained_nir_graph,
)
from neurocnl.ir.types import ConnectionIR, NetworkIR, PopulationIR


def _lif(size: int) -> nir.LIF:
    return nir.LIF(
        tau=np.full(size, 0.02, dtype=np.float32),
        r=np.ones(size, dtype=np.float32),
        v_leak=np.zeros(size, dtype=np.float32),
        v_threshold=np.ones(size, dtype=np.float32),
    )


def _trained_graph(weight: np.ndarray, *, node: str = "fc") -> nir.NIRGraph:
    """The overlay-v1 shape: `in port → LIF → Linear → LIF → out port`."""
    post, pre = weight.shape
    return nir.NIRGraph(
        nodes={
            "pixels": nir.Input(input_type={"input": np.array([pre])}),
            "hidden": _lif(pre),
            node: nir.Linear(weight=weight),
            "out": _lif(post),
            "labels": nir.Output(output_type={"output": np.array([post])}),
        },
        edges=[
            ("pixels", "hidden"),
            ("hidden", node),
            (node, "out"),
            ("out", "labels"),
        ],
    )


def _spec_ir(*, pre: int, post: int) -> NetworkIR:
    """The IR the CNL spec produces: right shape, zero values."""
    return NetworkIR(
        populations={
            "pixels": PopulationIR(name="pixels", size=pre, population_type="input"),
            "hidden": PopulationIR(name="hidden", size=pre, population_type="lif"),
            "out": PopulationIR(name="out", size=post, population_type="lif"),
            "labels": PopulationIR(name="labels", size=post, population_type="output"),
        },
        connections=[
            ConnectionIR(source="pixels", target="hidden", weight=1.0),
            ConnectionIR(source="hidden", target="out", weight=np.zeros((post, pre), dtype=float)),
            ConnectionIR(source="out", target="labels", weight=1.0),
        ],
    )


def _roundtrip(graph: nir.NIRGraph, tmp_path) -> object:
    """Through real `.nir` bytes, so this covers the HDF5 read too."""
    path = tmp_path / "model.nir"
    nir.write(str(path), graph)
    return load_trained_nir_graph(path.read_bytes())


def test_trained_weights_replace_the_specs_zeros(tmp_path) -> None:
    rng = np.random.default_rng(11)
    trained = rng.standard_normal((4, 32)).astype(np.float32)
    ir = _spec_ir(pre=32, post=4)

    dense = next(conn for conn in ir.connections if conn.source == "hidden")
    assert np.count_nonzero(np.asarray(dense.weight)) == 0, "precondition: zeros"

    result = apply_trained_weights(ir, _roundtrip(_trained_graph(trained), tmp_path))

    assert result.applied
    assert result.source_node == "fc"
    assert result.shape == (4, 32)
    assert result.nonzero == 128
    np.testing.assert_allclose(np.asarray(dense.weight), trained, rtol=1e-6)


def test_port_projections_are_not_treated_as_the_weight_matrix(tmp_path) -> None:
    """Only the population-to-population connection gets the trained matrix.

    Port projections are DMA-streamed and dropped by the exporter, so counting one
    as the dense matrix would both pick the wrong connection and report the wrong
    shape mismatch.
    """
    trained = np.full((4, 32), 0.25, dtype=np.float32)
    ir = _spec_ir(pre=32, post=4)

    apply_trained_weights(ir, _roundtrip(_trained_graph(trained), tmp_path))

    port_conn = next(conn for conn in ir.connections if conn.source == "pixels")
    assert port_conn.weight == 1.0


def test_shape_mismatch_names_both_shapes(tmp_path) -> None:
    """The usual cause is a stale checkpoint, so the message has to say so."""
    trained = np.ones((10, 64), dtype=np.float32)
    ir = _spec_ir(pre=32, post=4)

    with pytest.raises(TrainedWeightError) as excinfo:
        apply_trained_weights(ir, _roundtrip(_trained_graph(trained), tmp_path))

    message = str(excinfo.value)
    assert "4×32" in message, "the shape the network needs"
    assert "10×64" in message, "the shape the file actually holds"
    assert "re-run training" in message


def test_graph_with_no_weighted_node_is_rejected(tmp_path) -> None:
    graph = nir.NIRGraph(
        nodes={
            "pixels": nir.Input(input_type={"input": np.array([4])}),
            "out": _lif(4),
            "labels": nir.Output(output_type={"output": np.array([4])}),
        },
        edges=[("pixels", "out"), ("out", "labels")],
    )

    with pytest.raises(TrainedWeightError, match="no Linear or Affine node"):
        apply_trained_weights(_spec_ir(pre=32, post=4), _roundtrip(graph, tmp_path))


def test_more_matrices_than_layers_is_rejected_by_count(tmp_path) -> None:
    """A file holding matrices the network has no layers for is out of step.

    Overlay-v1 could only ever store one matrix, so this used to be reported as
    "more than one 4×4 matrix, which one is ambiguous". With a chain the real
    fault is the count, and naming it points at the stale checkpoint instead.
    """
    weight = np.ones((4, 4), dtype=np.float32)
    graph = nir.NIRGraph(
        nodes={
            "pixels": nir.Input(input_type={"input": np.array([4])}),
            "hidden": _lif(4),
            "fc1": nir.Linear(weight=weight),
            "fc2": nir.Linear(weight=weight.copy()),
            "out": _lif(4),
            "labels": nir.Output(output_type={"output": np.array([4])}),
        },
        edges=[
            ("pixels", "hidden"),
            ("hidden", "fc1"),
            ("fc1", "out"),
            ("hidden", "fc2"),
            ("out", "labels"),
        ],
    )

    with pytest.raises(TrainedWeightError) as excinfo:
        apply_trained_weights(_spec_ir(pre=4, post=4), _roundtrip(graph, tmp_path))

    message = str(excinfo.value)
    assert "2 weight matrices" in message
    assert "1 layer" in message
    assert "re-run training" in message


def test_affine_weights_are_accepted(tmp_path) -> None:
    """Overlay-v1 has no bias register, so Affine is usable — the bias is dropped."""
    trained = np.full((2, 3), 0.5, dtype=np.float32)
    graph = nir.NIRGraph(
        nodes={
            "pixels": nir.Input(input_type={"input": np.array([3])}),
            "hidden": _lif(3),
            "fc": nir.Affine(weight=trained, bias=np.ones(2, dtype=np.float32)),
            "out": _lif(2),
            "labels": nir.Output(output_type={"output": np.array([2])}),
        },
        edges=[("pixels", "hidden"), ("hidden", "fc"), ("fc", "out"), ("out", "labels")],
    )

    result = apply_trained_weights(_spec_ir(pre=3, post=2), _roundtrip(graph, tmp_path))

    assert result.applied
    assert result.shape == (2, 3)


def test_an_untrained_export_is_reported_rather_than_passed_off(tmp_path) -> None:
    """A zero matrix that *matches* still deploys nothing — say which it was."""
    ir = _spec_ir(pre=3, post=2)
    graph = _trained_graph(np.zeros((2, 3), dtype=np.float32))

    result = apply_trained_weights(ir, _roundtrip(graph, tmp_path))

    assert result.applied
    assert result.nonzero == 0
    assert "every weight is zero" in result.detail


def _two_layer_graph(
    first: np.ndarray, second: np.ndarray, *, reversed_nodes: bool = False
) -> nir.NIRGraph:
    """`in → LIF → Linear → LIF → Linear → LIF → out`, the v2 chain shape."""
    hidden_size = first.shape[1]
    middle_size = first.shape[0]
    out_size = second.shape[0]
    linears = {
        "fc1": nir.Linear(weight=first),
        "fc2": nir.Linear(weight=second),
    }
    nodes: dict[str, object] = {
        "pixels": nir.Input(input_type={"input": np.array([hidden_size])}),
        "hidden": _lif(hidden_size),
        "middle": _lif(middle_size),
        "out": _lif(out_size),
        "labels": nir.Output(output_type={"output": np.array([out_size])}),
    }
    # The node dict's order is however the exporter happened to write it, so a
    # reversed one must still produce the same assignment — chain order comes
    # from the edges.
    for name in reversed(list(linears)) if reversed_nodes else linears:
        nodes[name] = linears[name]
    return nir.NIRGraph(
        nodes=nodes,
        edges=[
            ("pixels", "hidden"),
            ("hidden", "fc1"),
            ("fc1", "middle"),
            ("middle", "fc2"),
            ("fc2", "out"),
            ("out", "labels"),
        ],
    )


def _two_layer_ir(*, first: int, middle: int, last: int) -> NetworkIR:
    return NetworkIR(
        populations={
            "pixels": PopulationIR(name="pixels", size=first, population_type="input"),
            "hidden": PopulationIR(name="hidden", size=first, population_type="lif"),
            "middle": PopulationIR(name="middle", size=middle, population_type="lif"),
            "out": PopulationIR(name="out", size=last, population_type="lif"),
            "labels": PopulationIR(name="labels", size=last, population_type="output"),
        },
        connections=[
            ConnectionIR(source="pixels", target="hidden", weight=1.0),
            ConnectionIR(
                source="hidden",
                target="middle",
                weight=np.zeros((middle, first), dtype=float),
            ),
            ConnectionIR(
                source="middle",
                target="out",
                weight=np.zeros((last, middle), dtype=float),
            ),
            ConnectionIR(source="out", target="labels", weight=1.0),
        ],
    )


def test_every_layer_in_a_chain_gets_its_trained_matrix(tmp_path) -> None:
    """Overlay-v1 refused any network with more than one matrix outright.

    That would now reject the MNIST-scale `784 → 256 → 10` chain the planner
    accepts, and the deploy would carry zeros for both layers.
    """
    rng = np.random.default_rng(7)
    first = rng.standard_normal((6, 8)).astype(np.float32)
    second = rng.standard_normal((3, 6)).astype(np.float32)
    ir = _two_layer_ir(first=8, middle=6, last=3)

    result = apply_trained_weights(ir, _roundtrip(_two_layer_graph(first, second), tmp_path))

    assert result.applied
    assert result.nonzero == 48 + 18
    assert "fc1" in result.detail and "fc2" in result.detail

    layer1 = next(conn for conn in ir.connections if conn.source == "hidden")
    layer2 = next(conn for conn in ir.connections if conn.source == "middle")
    np.testing.assert_allclose(np.asarray(layer1.weight), first, rtol=1e-6)
    np.testing.assert_allclose(np.asarray(layer2.weight), second, rtol=1e-6)


def test_chain_order_comes_from_the_graph_not_the_node_dict(tmp_path) -> None:
    """Same-shaped layers can only be separated by position, so it must be right."""
    first = np.full((4, 4), 0.25, dtype=np.float32)
    second = np.full((4, 4), 0.75, dtype=np.float32)
    ir = _two_layer_ir(first=4, middle=4, last=4)

    apply_trained_weights(
        ir,
        _roundtrip(_two_layer_graph(first, second, reversed_nodes=True), tmp_path),
    )

    layer1 = next(conn for conn in ir.connections if conn.source == "hidden")
    layer2 = next(conn for conn in ir.connections if conn.source == "middle")
    np.testing.assert_allclose(np.asarray(layer1.weight), first, rtol=1e-6)
    np.testing.assert_allclose(np.asarray(layer2.weight), second, rtol=1e-6)


def test_a_chain_whose_middle_layer_is_the_wrong_shape_names_that_layer(
    tmp_path,
) -> None:
    # A self-consistent 8 → 6 → 3 checkpoint against a canvas whose last layer
    # has since been widened to 4 — the usual "checkpoint predates my last edit".
    first = np.ones((6, 8), dtype=np.float32)
    second = np.ones((3, 6), dtype=np.float32)
    ir = _two_layer_ir(first=8, middle=6, last=4)

    with pytest.raises(TrainedWeightError) as excinfo:
        apply_trained_weights(ir, _roundtrip(_two_layer_graph(first, second), tmp_path))

    message = str(excinfo.value)
    assert "layer 2" in message
    assert "middle → out" in message
    assert "4×6" in message and "3×6" in message
    # Layer 1 matched, so it must not be blamed.
    assert "layer 1" not in message


def test_unreadable_bytes_fail_with_a_clear_message() -> None:
    with pytest.raises(TrainedWeightError, match="could not be read as a NIR graph"):
        load_trained_nir_graph(b"not an hdf5 file")


def test_network_without_a_dense_connection_is_not_an_error(tmp_path) -> None:
    """Nothing to fill in is a fact to report, not a failure."""
    ir = NetworkIR(
        populations={
            "pixels": PopulationIR(name="pixels", size=4, population_type="input"),
            "out": PopulationIR(name="out", size=4, population_type="lif"),
        },
        connections=[ConnectionIR(source="pixels", target="out", weight=1.0)],
    )

    result = apply_trained_weights(
        ir, _roundtrip(_trained_graph(np.ones((4, 4), dtype=np.float32)), tmp_path)
    )

    assert not result.applied
    assert "no weight matrix" in result.detail


# ---------------------------------------------------------------------------
# The NIR-graph sibling, used by the simulator run path
# ---------------------------------------------------------------------------
#
# Same gap, different consumer: `POST /api/simulators/run` recompiles the spec
# on every run, so before this the three software simulators ran a network whose
# every weight was 0.0 and returned an empty raster in milliseconds.


def _compiled_two_layer_graph(*, pre: int, middle: int, post: int) -> nir.NIRGraph:
    """What `compile_to_nir` produces from a spec: right shapes, all zeros."""
    return _two_layer_graph(
        np.zeros((middle, pre), dtype=np.float32),
        np.zeros((post, middle), dtype=np.float32),
    )


def test_graph_overlay_replaces_every_zero_matrix_in_the_chain(tmp_path) -> None:
    compiled = _compiled_two_layer_graph(pre=4, middle=3, post=2)
    first = np.arange(12, dtype=np.float32).reshape(3, 4) + 1.0
    second = np.arange(6, dtype=np.float32).reshape(2, 3) + 1.0

    result = apply_trained_weights_to_graph(
        compiled, _roundtrip(_two_layer_graph(first, second), tmp_path)
    )

    assert result.applied
    assert not graph_is_all_zero(compiled)
    np.testing.assert_allclose(compiled.nodes["fc1"].weight, first)
    np.testing.assert_allclose(compiled.nodes["fc2"].weight, second)


def test_graph_overlay_uses_chain_order_not_node_dict_order(tmp_path) -> None:
    """Two layers of different shape must not be swapped by dict ordering."""
    compiled = _compiled_two_layer_graph(pre=4, middle=3, post=2)
    first = np.full((3, 4), 0.25, dtype=np.float32)
    second = np.full((2, 3), 0.75, dtype=np.float32)

    apply_trained_weights_to_graph(
        compiled,
        _roundtrip(_two_layer_graph(first, second, reversed_nodes=True), tmp_path),
    )

    np.testing.assert_allclose(compiled.nodes["fc1"].weight, first)
    np.testing.assert_allclose(compiled.nodes["fc2"].weight, second)


def test_graph_overlay_rejects_a_wrong_shaped_layer_by_position(tmp_path) -> None:
    compiled = _compiled_two_layer_graph(pre=4, middle=3, post=2)
    wrong_middle = np.ones((5, 4), dtype=np.float32)
    second = np.ones((2, 5), dtype=np.float32)

    with pytest.raises(TrainedWeightError, match="layer 1"):
        apply_trained_weights_to_graph(
            compiled, _roundtrip(_two_layer_graph(wrong_middle, second), tmp_path)
        )


def test_graph_overlay_rejects_a_different_layer_count(tmp_path) -> None:
    compiled = _compiled_two_layer_graph(pre=4, middle=3, post=2)

    with pytest.raises(TrainedWeightError, match="2 layers"):
        apply_trained_weights_to_graph(
            compiled,
            _roundtrip(_trained_graph(np.ones((3, 4), dtype=np.float32)), tmp_path),
        )


def test_graph_with_no_weight_matrix_is_not_an_error() -> None:
    compiled = nir.NIRGraph(
        nodes={
            "pixels": nir.Input(input_type={"input": np.array([2])}),
            "out": _lif(2),
        },
        edges=[("pixels", "out")],
    )

    result = apply_trained_weights_to_graph(compiled, compiled)

    assert not result.applied
    assert "no weight matrix" in result.detail


def test_graph_is_all_zero_only_when_there_are_weights_to_be_zero() -> None:
    assert graph_is_all_zero(_compiled_two_layer_graph(pre=4, middle=3, post=2))
    assert not graph_is_all_zero(
        _two_layer_graph(np.ones((3, 4), dtype=np.float32), np.ones((2, 3), dtype=np.float32))
    )
    # No weighted node at all is not "all zero" — there is nothing to be zero.
    assert not graph_is_all_zero(nir.NIRGraph(nodes={"out": _lif(2)}, edges=[]))


# ---------------------------------------------------------------------------
# Neuron-parameter overlay
# ---------------------------------------------------------------------------


def _zeroed_neurons(graph: nir.NIRGraph) -> nir.NIRGraph:
    """Blank every LIF parameter, the way compile_to_nir leaves a CNL spec.

    CNL records a neuron as `with time constant shape (256,)` -- a shape, not a
    value -- so `_resolve_tensor` zero-fills tau, v_threshold and r alike.
    """
    for node in graph.nodes.values():
        if isinstance(node, nir.LIF):
            node.tau = np.zeros_like(np.asarray(node.tau))
            node.v_threshold = np.zeros_like(np.asarray(node.v_threshold))
            node.r = np.zeros_like(np.asarray(node.r))
    return graph


def test_graph_overlay_fills_in_zeroed_neuron_parameters(tmp_path) -> None:
    """The regression: weights alone left tau=0, so no backend could run.

    A CNL-compiled graph reaches the simulators with every neuron parameter
    zeroed. Overlaying only the weight matrices left tau at 0, which is not a
    leaky membrane at any timestep -- the run failed instead of producing a
    network.
    """
    compiled = _zeroed_neurons(_compiled_two_layer_graph(pre=4, middle=3, post=2))
    trained = _two_layer_graph(np.ones((3, 4), dtype=np.float32), np.ones((2, 3), dtype=np.float32))

    result = apply_trained_weights_to_graph(compiled, _roundtrip(trained, tmp_path))

    assert result.applied is True
    for name in ("hidden", "middle", "out"):
        node = compiled.nodes[name]
        assert np.allclose(np.asarray(node.tau), 0.02), name
        assert np.allclose(np.asarray(node.v_threshold), 1.0), name
        assert np.allclose(np.asarray(node.r), 1.0), name
    assert "time constants and firing thresholds" in result.detail


def test_graph_overlay_reconstructs_when_the_trained_file_is_blank_too(tmp_path) -> None:
    """Recovery for a .nir written before the exporter recorded real values.

    The exporter used to copy weight matrices onto the same shape-only graph,
    so its output had real weights and tau=0. Refusing to run that would strand
    every model trained before the fix; the codegen fallback (beta=0.95, no
    threshold rescale) says exactly what the network was fitted at.
    """
    compiled = _zeroed_neurons(_compiled_two_layer_graph(pre=4, middle=3, post=2))
    trained = _zeroed_neurons(
        _two_layer_graph(np.ones((3, 4), dtype=np.float32), np.ones((2, 3), dtype=np.float32))
    )

    result = apply_trained_weights_to_graph(compiled, _roundtrip(trained, tmp_path))

    assert result.applied is True
    for name in ("hidden", "middle", "out"):
        tau = float(np.asarray(compiled.nodes[name].tau).ravel()[0])
        # beta = 1 - dt/tau must come back out as the 0.95 training used.
        assert 1.0 - 1e-4 / tau == pytest.approx(0.95)
        assert np.allclose(np.asarray(compiled.nodes[name].v_threshold), 1.0)
    assert "reconstructed" in result.detail
    assert "Re-run training" in result.detail


def test_graph_overlay_never_overwrites_an_authored_neuron_parameter(tmp_path) -> None:
    """A neuron with a real time constant is left completely alone.

    A zero v_leak or v_threshold is a value a user could mean, so the whole
    population is judged by its tau: non-zero means configured, hands off.
    """
    compiled = _zeroed_neurons(_compiled_two_layer_graph(pre=4, middle=3, post=2))
    compiled.nodes["hidden"].tau = np.full(4, 0.005, dtype=np.float32)
    compiled.nodes["hidden"].v_threshold = np.full(4, 0.25, dtype=np.float32)

    trained = _two_layer_graph(np.ones((3, 4), dtype=np.float32), np.ones((2, 3), dtype=np.float32))
    apply_trained_weights_to_graph(compiled, _roundtrip(trained, tmp_path))

    assert np.allclose(np.asarray(compiled.nodes["hidden"].tau), 0.005)
    assert np.allclose(np.asarray(compiled.nodes["hidden"].v_threshold), 0.25)
    # ...while its shape-only neighbours still get filled in.
    assert np.allclose(np.asarray(compiled.nodes["middle"].tau), 0.02)


def test_graph_overlay_reports_no_neuron_fill_when_nothing_was_zeroed(tmp_path) -> None:
    compiled = _compiled_two_layer_graph(pre=4, middle=3, post=2)
    trained = _two_layer_graph(np.ones((3, 4), dtype=np.float32), np.ones((2, 3), dtype=np.float32))
    result = apply_trained_weights_to_graph(compiled, _roundtrip(trained, tmp_path))
    assert "time constants and firing thresholds" not in result.detail


# ---------------------------------------------------------------------------
# Per-layer breakdown
# ---------------------------------------------------------------------------
# `shape` is the first matrix only while `nonzero` counts them all, so on any
# multi-layer network `nonzero / prod(shape)` reads above 1.0. `layers` is the
# field a sparsity display has to be built on instead.


def test_layers_break_the_nonzero_total_down_per_layer(tmp_path) -> None:
    compiled = _compiled_two_layer_graph(pre=4, middle=3, post=2)
    first = np.arange(12, dtype=np.float32).reshape(3, 4)  # one zero, at [0, 0]
    second = np.ones((2, 3), dtype=np.float32)

    result = apply_trained_weights_to_graph(
        compiled, _roundtrip(_two_layer_graph(first, second), tmp_path)
    )

    assert [layer["name"] for layer in result.layers] == ["fc1", "fc2"]
    assert [layer["shape"] for layer in result.layers] == [[3, 4], [2, 3]]
    assert [layer["nonzero"] for layer in result.layers] == [11, 6]
    assert sum(layer["nonzero"] for layer in result.layers) == result.nonzero
    # The bug this field exists for: the headline pair does not divide out.
    assert result.shape == (3, 4)
    assert result.nonzero > result.shape[0] * result.shape[1]


def test_deploy_path_also_reports_one_layer_entry_per_connection(tmp_path) -> None:
    first = np.ones((6, 8), dtype=np.float32)
    second = np.ones((3, 6), dtype=np.float32)
    ir = _two_layer_ir(first=8, middle=6, last=3)

    result = apply_trained_weights(ir, _roundtrip(_two_layer_graph(first, second), tmp_path))

    assert [layer["name"] for layer in result.layers] == ["fc1", "fc2"]
    assert sum(layer["nonzero"] for layer in result.layers) == result.nonzero


def test_a_network_with_no_weighted_node_reports_no_layers() -> None:
    compiled = nir.NIRGraph(
        nodes={
            "pixels": nir.Input(input_type={"input": np.array([2])}),
            "out": _lif(2),
        },
        edges=[("pixels", "out")],
    )

    result = apply_trained_weights_to_graph(compiled, compiled)

    assert not result.applied
    assert result.layers == ()


def test_to_dict_carries_the_layer_breakdown(tmp_path) -> None:
    """The simulator run result serialises through `to_dict`, not the dataclass."""
    compiled = _compiled_two_layer_graph(pre=4, middle=3, post=2)
    result = apply_trained_weights_to_graph(
        compiled,
        _roundtrip(
            _two_layer_graph(np.ones((3, 4), dtype=np.float32), np.ones((2, 3), dtype=np.float32)),
            tmp_path,
        ),
    )

    payload = result.to_dict()

    assert payload["layers"] == [
        {"name": "fc1", "shape": [3, 4], "nonzero": 12},
        {"name": "fc2", "shape": [2, 3], "nonzero": 6},
    ]
