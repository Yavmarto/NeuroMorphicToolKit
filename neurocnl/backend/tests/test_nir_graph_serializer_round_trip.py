from __future__ import annotations

import base64
import io

import numpy as np
import pytest
from fastapi.testclient import TestClient

from backend.app.main import app
from backend.app.services.nir_graph_serializer import (
    NIR_CANVAS_TYPE_SPECS,
    deserialize_canvas_graph,
    serialize_nir_to_canvas_graph,
)
from neurocnl.runtime.cnl_nodes import (
    BatchNorm1d,
    Dropout,
    Leaky,
    RLeaky,
    RSynaptic,
    Synaptic,
)
from neurosim.contracts.design_contracts import CanvasGraph

nir = pytest.importorskip("nir")

client = TestClient(app)


def _canvas_node_payload(nir_type: str) -> dict:
    params_by_type = {
        "nir.Input": {"size": 2, "shape": [2]},
        "nir.Output": {"size": 2, "shape": [2]},
        "nir.LIF": {
            "n_neurons": 2,
            "tau": 0.02,
            "threshold": 1.0,
            "r": 1.0,
            "v_leak": 0.0,
        },
        "nir.CubaLIF": {
            "n_neurons": 2,
            "tau_mem": 0.02,
            "tau_syn": 0.01,
            "threshold": 1.0,
            "r": 1.0,
            "v_leak": 0.0,
            "w_in": 1.0,
        },
        "nir.IF": {"n_neurons": 2, "threshold": 1.0, "r": 1.0},
        "nir.LI": {"n_neurons": 2, "tau": 0.02, "r": 1.0, "v_leak": 0.0},
        "nir.Linear": {"rows": 2, "cols": 2, "weight_fill": 0.5},
        "nir.Affine": {"rows": 2, "cols": 2, "weight_fill": 0.5, "bias": [0.1, 0.2]},
        "nir.Conv1d": {
            "weight_shape": [1, 1, 3],
            "weight_fill": 0.1,
            "stride": 1,
            "padding": 0,
            "dilation": 1,
            "groups": 1,
            "input_shape": 8,
            "bias": [0.0],
        },
        "nir.Conv2d": {
            "weight_shape": [1, 1, 3, 3],
            "weight_fill": 0.1,
            "stride": [1, 1],
            "padding": [0, 0],
            "dilation": [1, 1],
            "groups": 1,
            "input_shape": [8, 8],
            "bias": [0.0],
        },
        "nir.Flatten": {"start_dim": 1, "end_dim": -1},
        "nir.AvgPool2d": {"kernel_size": [2, 2], "stride": [2, 2], "padding": [0, 0]},
        "nir.SumPool2d": {"kernel_size": [2, 2], "stride": [2, 2], "padding": [0, 0]},
        "nir.Delay": {"delay": 0.001},
        "nir.Scale": {"scale": [1.5], "scale_fill": 1.5},
        "cnl.Synaptic": {
            "n_neurons": 2,
            "alpha": 0.9,
            "beta": 0.8,
            "threshold": 1.0,
            "reset_mechanism": "subtract",
        },
        "cnl.RSynaptic": {
            "n_neurons": 2,
            "alpha": 0.9,
            "beta": 0.8,
            "threshold": 1.0,
            "reset_mechanism": "subtract",
            "use_bias": False,
            "recurrent_weight_matrix": [[0.1, 0.2], [0.3, 0.4]],
        },
        "cnl.RLeaky": {
            "n_neurons": 2,
            "beta": 0.9,
            "threshold": 1.0,
            "reset_mechanism": "subtract",
        },
        "cnl.Leaky": {
            "n_neurons": 2,
            "beta": 0.9,
            "threshold": 1.0,
            "reset_mechanism": "subtract",
        },
        "cnl.BatchNorm1d": {"num_features": 2},
        "cnl.Dropout": {"p": 0.5},
    }
    spec = NIR_CANVAS_TYPE_SPECS[nir_type]
    return {
        "id": "node",
        "component_id": spec.component_id or nir_type,
        "nir_type": nir_type,
        "label": spec.label,
        "parameters": params_by_type[nir_type],
        "position": [0.0, 0.0],
        "metadata": {"category": spec.category},
    }


def test_serialize_nir_to_canvas_graph_handles_multiple_supported_types() -> None:
    graph = nir.NIRGraph(
        nodes={
            "input": nir.Input(input_type={"input": np.array([4])}),
            "linear": nir.Linear(weight=np.eye(4)),
            "lif": nir.LIF(
                tau=np.full(4, 0.02),
                r=np.ones(4),
                v_leak=np.zeros(4),
                v_threshold=np.ones(4),
            ),
            "output": nir.Output(output_type={"output": np.array([4])}),
        },
        edges=[("input", "linear"), ("linear", "lif"), ("lif", "output")],
    )

    canvas_graph = serialize_nir_to_canvas_graph(graph)

    assert canvas_graph.metadata["graph_kind"] == "nir"
    assert {node.nir_type for node in canvas_graph.nodes} == {
        "nir.Input",
        "nir.Linear",
        "nir.LIF",
        "nir.Output",
    }
    lif_node = next(node for node in canvas_graph.nodes if node.id == "lif")
    assert lif_node.parameters["n_neurons"] == 4
    assert lif_node.parameters["tau"] == pytest.approx(0.02)


def test_conv2d_weight_matrix_round_trips_through_canvas_payload() -> None:
    weight = np.arange(16, dtype=float).reshape(1, 1, 4, 4) / 10.0
    graph = nir.NIRGraph(
        nodes={
            "conv": nir.Conv2d(
                input_shape=(8, 8),
                weight=weight,
                stride=(1, 1),
                padding=(0, 0),
                dilation=(1, 1),
                groups=1,
                bias=np.array([0.0]),
            )
        },
        edges=[],
    )

    canvas_graph = serialize_nir_to_canvas_graph(graph)
    conv_node = canvas_graph.nodes[0]
    assert conv_node.parameters["weight_matrix"] == weight.tolist()

    roundtrip_graph = deserialize_canvas_graph(canvas_graph)
    assert np.array_equal(roundtrip_graph.nodes["conv"].weight, weight)


def test_deserialize_canvas_graph_round_trips_lif_flow() -> None:
    canvas_graph = CanvasGraph.model_validate(
        {
            "nodes": [
                {
                    "id": "input",
                    "component_id": "input_node",
                    "nir_type": "nir.Input",
                    "label": "Input",
                    "parameters": {"size": 2, "shape": [2]},
                    "position": [0.0, 0.0],
                },
                {
                    "id": "lif",
                    "component_id": "lif_population",
                    "nir_type": "nir.LIF",
                    "label": "Population",
                    "parameters": {
                        "name": "Population",
                        "n_neurons": 2,
                        "tau": 0.03,
                        "threshold": 1.2,
                    },
                    "position": [200.0, 0.0],
                },
                {
                    "id": "output",
                    "component_id": "output_node",
                    "nir_type": "nir.Output",
                    "label": "Output",
                    "parameters": {"size": 2, "shape": [2]},
                    "position": [400.0, 0.0],
                },
            ],
            "edges": [
                {
                    "id": "edge_0",
                    "source_node_id": "input",
                    "source_port": "out",
                    "target_node_id": "lif",
                    "target_port": "in",
                    "parameters": {},
                },
                {
                    "id": "edge_1",
                    "source_node_id": "lif",
                    "source_port": "out",
                    "target_node_id": "output",
                    "target_port": "in",
                    "parameters": {},
                },
            ],
            "metadata": {"graph_kind": "nir"},
        }
    )

    nir_graph = deserialize_canvas_graph(canvas_graph)

    assert isinstance(nir_graph.nodes["lif"], nir.LIF)
    assert float(np.asarray(nir_graph.nodes["lif"].tau).flat[0]) == pytest.approx(0.03)
    assert len(nir_graph.edges) == 2


@pytest.mark.parametrize("nir_type", sorted(NIR_CANVAS_TYPE_SPECS))
def test_canvas_serializer_round_trips_every_supported_primitive(nir_type: str) -> None:
    canvas_graph = CanvasGraph.model_validate(
        {
            "nodes": [_canvas_node_payload(nir_type)],
            "edges": [],
            "metadata": {"graph_kind": "nir"},
        }
    )

    nir_graph = deserialize_canvas_graph(canvas_graph)
    expected_type = {
        "cnl.Synaptic": Synaptic,
        "cnl.RSynaptic": RSynaptic,
        "cnl.Leaky": Leaky,
        "cnl.RLeaky": RLeaky,
        "cnl.BatchNorm1d": BatchNorm1d,
        "cnl.Dropout": Dropout,
    }.get(nir_type)
    if expected_type is None:
        primitive_name = nir_type.split(".", maxsplit=1)[1]
        expected_type = getattr(nir, primitive_name)

    assert isinstance(nir_graph.nodes["node"], expected_type)
    if nir_type == "cnl.RSynaptic":
        assert nir_graph.nodes["node"].recurrent_weight == [[0.1, 0.2], [0.3, 0.4]]

    roundtrip_canvas = serialize_nir_to_canvas_graph(nir_graph)

    assert roundtrip_canvas.nodes[0].nir_type == nir_type
    assert (
        roundtrip_canvas.nodes[0].metadata["category"]
        == NIR_CANVAS_TYPE_SPECS[nir_type].category
    )
    if nir_type == "cnl.RSynaptic":
        assert roundtrip_canvas.nodes[0].parameters["recurrent_weight_matrix"] == [
            [0.1, 0.2],
            [0.3, 0.4],
        ]


def test_deserialize_canvas_flatten_without_shape_uses_default_input_type() -> None:
    canvas_graph = CanvasGraph.model_validate(
        {
            "nodes": [
                {
                    "id": "flat",
                    "component_id": "nir.Flatten",
                    "nir_type": "nir.Flatten",
                    "label": "Flatten",
                    "parameters": {"start_dim": 1, "end_dim": -1},
                    "position": [0.0, 0.0],
                }
            ],
            "edges": [],
            "metadata": {"graph_kind": "nir"},
        }
    )

    nir_graph = deserialize_canvas_graph(canvas_graph)

    flatten = nir_graph.nodes["flat"]
    assert isinstance(flatten, nir.Flatten)
    assert list(np.asarray(flatten.input_type["input"])) == [1]


def test_nir_canvas_routes_round_trip_canvas_payload() -> None:
    original = nir.NIRGraph(
        nodes={
            "input": nir.Input(input_type={"input": np.array([1])}),
            "lif": nir.LIF(
                tau=np.array([0.02]),
                r=np.array([1.0]),
                v_leak=np.array([0.0]),
                v_threshold=np.array([1.0]),
            ),
            "output": nir.Output(output_type={"output": np.array([1])}),
        },
        edges=[("input", "lif"), ("lif", "output")],
    )
    buffer = io.BytesIO()
    nir.write(buffer, original)

    import_response = client.post(
        "/api/neurosim/nir/import",
        json={"content_b64": base64.b64encode(buffer.getvalue()).decode("utf-8")},
    )
    assert import_response.status_code == 200, import_response.text
    imported_graph = import_response.json()["graph"]
    assert imported_graph["metadata"]["graph_kind"] == "nir"
    assert imported_graph["nodes"][1]["nir_type"] == "nir.LIF"

    export_response = client.post("/api/neurosim/nir/export", json=imported_graph)
    assert export_response.status_code == 200, export_response.text
    roundtrip_bytes = base64.b64decode(export_response.json()["content_b64"])
    roundtrip_graph = nir.read(io.BytesIO(roundtrip_bytes))
    assert isinstance(roundtrip_graph, nir.NIRGraph)
    assert set(roundtrip_graph.nodes) == {"input", "lif", "output"}
