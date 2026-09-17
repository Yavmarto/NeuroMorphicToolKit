from __future__ import annotations

import numpy as np
import pytest

from backend.app.services.nir_graph_serializer import (
    deserialize_canvas_graph,
    serialize_nir_to_canvas_graph,
)
from neurosim.contracts.design_contracts import CanvasGraph

nir = pytest.importorskip("nir")


# ── Network-level timestep (graph.metadata["dt"]) round trip ────────────────
#
# Companion to the nir_cnl grammar's optional `with timestep <seconds>` clause
# (see neurocnl/tests/nir_native_cnl/test_network_timestep.py and
# backend/tests/test_notebook_codegen_network_timestep.py). Without this
# round trip, editing any canvas node/edge silently drops a declared network
# timestep, reverting to the LIF codegen's unreachable-threshold default.


def _lif_flow_canvas_graph(
    *, graph_metadata: dict, node_metadata: dict | None = None
) -> CanvasGraph:
    return CanvasGraph.model_validate(
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
                    "metadata": node_metadata or {},
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
            "metadata": graph_metadata,
        }
    )


def test_deserialize_canvas_graph_propagates_network_dt_to_graph_and_lif_nodes() -> (
    None
):
    canvas_graph = _lif_flow_canvas_graph(graph_metadata={"dt": 0.005})
    nir_graph = deserialize_canvas_graph(canvas_graph)
    assert nir_graph.metadata["dt"] == 0.005
    assert nir_graph.nodes["lif"].metadata["dt"] == 0.005


def test_deserialize_canvas_graph_explicit_node_dt_wins_over_network_dt() -> None:
    canvas_graph = _lif_flow_canvas_graph(
        graph_metadata={"dt": 0.005}, node_metadata={"dt": 0.001}
    )
    nir_graph = deserialize_canvas_graph(canvas_graph)
    assert nir_graph.metadata["dt"] == 0.005
    assert nir_graph.nodes["lif"].metadata["dt"] == 0.001


def test_deserialize_canvas_graph_no_dt_key_is_unchanged() -> None:
    """Critical backward-compat guarantee: an undeclared network timestep
    must inject nothing anywhere."""
    canvas_graph = _lif_flow_canvas_graph(graph_metadata={"graph_kind": "nir"})
    nir_graph = deserialize_canvas_graph(canvas_graph)
    assert "dt" not in nir_graph.metadata
    assert "dt" not in nir_graph.nodes["lif"].metadata


def test_serialize_nir_to_canvas_graph_preserves_network_dt() -> None:
    graph = nir.NIRGraph(
        nodes={
            "input": nir.Input(input_type={"input": np.array([2])}),
            "lif": nir.LIF(
                tau=np.full(2, 0.03),
                r=np.ones(2),
                v_leak=np.zeros(2),
                v_threshold=np.full(2, 1.2),
            ),
            "output": nir.Output(output_type={"output": np.array([2])}),
        },
        edges=[("input", "lif"), ("lif", "output")],
        metadata={"dt": 0.01},
    )
    canvas_graph = serialize_nir_to_canvas_graph(graph)
    assert canvas_graph.metadata["dt"] == 0.01
    assert canvas_graph.metadata["graph_kind"] == "nir"


def test_serialize_nir_to_canvas_graph_no_dt_omits_key() -> None:
    graph = nir.NIRGraph(
        nodes={
            "input": nir.Input(input_type={"input": np.array([2])}),
            "output": nir.Output(output_type={"output": np.array([2])}),
        },
        edges=[("input", "output")],
    )
    canvas_graph = serialize_nir_to_canvas_graph(graph)
    assert "dt" not in canvas_graph.metadata


def test_network_dt_round_trips_serialize_then_deserialize() -> None:
    graph = nir.NIRGraph(
        nodes={
            "input": nir.Input(input_type={"input": np.array([2])}),
            "lif": nir.LIF(
                tau=np.full(2, 0.03),
                r=np.ones(2),
                v_leak=np.zeros(2),
                v_threshold=np.full(2, 1.2),
            ),
            "output": nir.Output(output_type={"output": np.array([2])}),
        },
        edges=[("input", "lif"), ("lif", "output")],
        metadata={"dt": 0.002},
    )
    canvas_graph = serialize_nir_to_canvas_graph(graph)
    rebuilt = deserialize_canvas_graph(canvas_graph)
    assert rebuilt.metadata["dt"] == 0.002
    assert rebuilt.nodes["lif"].metadata["dt"] == 0.002


def test_serialize_nir_to_canvas_graph_preserves_dt_through_fuse_recurrent_pairs() -> (
    None
):
    """Regression: fuse_recurrent_pairs can return a brand-new nir.NIRGraph
    (no metadata kwarg) when it actually fuses a CubaLIF+self-loop pair —
    the network-level dt must survive that reassignment."""
    graph = nir.NIRGraph(
        nodes={
            "input": nir.Input(input_type={"input": np.array([2])}),
            "fc1": nir.Linear(weight=np.eye(2)),
            "lif1.lif": nir.CubaLIF(
                tau_syn=np.array([0.01, 0.01]),
                tau_mem=np.array([0.02, 0.02]),
                r=np.array([1.0, 1.0]),
                v_leak=np.array([0.0, 0.0]),
                v_threshold=np.array([1.0, 1.0]),
                w_in=np.array([1.0, 1.0]),
            ),
            "lif1.w_rec": nir.Linear(weight=np.zeros((2, 2))),
            "output": nir.Output(output_type={"output": np.array([2])}),
        },
        edges=[
            ("input", "fc1"),
            ("fc1", "lif1.lif"),
            ("lif1.lif", "lif1.w_rec"),
            ("lif1.w_rec", "lif1.lif"),
            ("lif1.lif", "output"),
        ],
        metadata={"dt": 0.003},
    )
    canvas_graph = serialize_nir_to_canvas_graph(graph)
    assert canvas_graph.metadata.get("dt") == 0.003
