from __future__ import annotations

import numpy as np
import pytest

from backend.app.services.nir_graph_serializer import (
    deserialize_canvas_graph,
    serialize_nir_to_canvas_graph,
)
from neurosim.contracts.design_contracts import CanvasGraph

nir = pytest.importorskip("nir")


# ---------------------------------------------------------------------------
# Editable size fields must outrank the derived fields serialized alongside them
#
# `serialize_nir_to_canvas_graph` emits `weight_matrix`/`shape` next to the
# `rows`/`cols`/`size` the Inspector edits, and the canvas mirrors those
# parameters back over its own nodes after every round trip. Preferring the
# derived field silently reverted the user's edit and shipped the old layer
# width to codegen.
# ---------------------------------------------------------------------------


def _fcn_nir_graph(hidden: int) -> nir.NIRGraph:
    """784 -> Linear -> LIF -> Output, the head of the guide's MNIST FCN."""
    return nir.NIRGraph(
        nodes={
            "inp": nir.Input(input_type={"input": np.array([784])}),
            "lin": nir.Linear(weight=np.full((hidden, 784), 0.5)),
            "lif": nir.LIF(
                tau=np.full(hidden, 0.002),
                r=np.ones(hidden),
                v_leak=np.zeros(hidden),
                v_threshold=np.ones(hidden),
            ),
            "out": nir.Output(output_type={"output": np.array([hidden])}),
        },
        edges=[("inp", "lin"), ("lin", "lif"), ("lif", "out")],
    )


def _node_by_id(canvas_graph: CanvasGraph, node_id: str):
    return next(node for node in canvas_graph.nodes if node.id == node_id)


def test_edited_rows_wins_over_a_stale_weight_matrix() -> None:
    canvas_graph = serialize_nir_to_canvas_graph(_fcn_nir_graph(1000))
    linear_params = _node_by_id(canvas_graph, "lin").parameters
    # Precondition: the round trip really does leave a matrix behind to shadow.
    assert np.asarray(linear_params["weight_matrix"]).shape == (1000, 784)

    linear_params["rows"] = 256  # the user retypes `Rows` in the Inspector

    nir_graph = deserialize_canvas_graph(canvas_graph)
    assert np.asarray(nir_graph.nodes["lin"].weight).shape == (256, 784)


def test_edited_cols_wins_over_a_stale_weight_matrix() -> None:
    canvas_graph = serialize_nir_to_canvas_graph(_fcn_nir_graph(1000))
    _node_by_id(canvas_graph, "lin").parameters["cols"] = 128

    nir_graph = deserialize_canvas_graph(canvas_graph)
    assert np.asarray(nir_graph.nodes["lin"].weight).shape == (1000, 128)


def test_weight_matrix_survives_untouched_when_it_agrees_with_rows_and_cols() -> None:
    """An import-then-push with no edit must not flatten trained weights into
    a constant fill."""
    graph = _fcn_nir_graph(4)
    weight = np.arange(4 * 784, dtype=float).reshape(4, 784)
    graph.nodes["lin"] = nir.Linear(weight=weight)

    canvas_graph = serialize_nir_to_canvas_graph(graph)
    nir_graph = deserialize_canvas_graph(canvas_graph)

    np.testing.assert_allclose(np.asarray(nir_graph.nodes["lin"].weight), weight)


def test_weight_matrix_is_kept_when_no_rows_cols_were_declared() -> None:
    canvas_graph = serialize_nir_to_canvas_graph(_fcn_nir_graph(3))
    linear_params = _node_by_id(canvas_graph, "lin").parameters
    del linear_params["rows"]
    del linear_params["cols"]

    nir_graph = deserialize_canvas_graph(canvas_graph)
    assert np.asarray(nir_graph.nodes["lin"].weight).shape == (3, 784)


def test_edited_size_wins_over_a_stale_shape() -> None:
    canvas_graph = serialize_nir_to_canvas_graph(_fcn_nir_graph(1000))
    input_params = _node_by_id(canvas_graph, "inp").parameters
    assert input_params["shape"] == [784]

    input_params["size"] = 256  # the user retypes `Size` on the Input node

    nir_graph = deserialize_canvas_graph(canvas_graph)
    assert list(nir_graph.nodes["inp"].input_type["input"]) == [256]


def test_multidimensional_shape_survives_when_size_agrees() -> None:
    """`shape` still wins when it agrees with `size` — a conv feature map must
    not be flattened to a bare length."""
    canvas_graph = serialize_nir_to_canvas_graph(_fcn_nir_graph(2))
    input_params = _node_by_id(canvas_graph, "inp").parameters
    input_params["shape"] = [1, 28, 28]
    input_params["size"] = 784

    nir_graph = deserialize_canvas_graph(canvas_graph)
    assert list(nir_graph.nodes["inp"].input_type["input"]) == [1, 28, 28]


def test_edited_n_neurons_wins_over_a_stale_shape() -> None:
    canvas_graph = serialize_nir_to_canvas_graph(_fcn_nir_graph(1000))
    _node_by_id(canvas_graph, "lif").parameters["n_neurons"] = 256

    nir_graph = deserialize_canvas_graph(canvas_graph)
    assert np.asarray(nir_graph.nodes["lif"].tau).size == 256
