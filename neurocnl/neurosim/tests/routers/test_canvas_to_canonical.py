"""Tests for the /canvas-to-canonical and /canvas-mutation endpoints."""

from typing import Any

from fastapi.testclient import TestClient

from neurosim.app.main import app

client = TestClient(app)

# Minimal two-node LIF canvas graph payload used across tests.
_LIF_GRAPH = {
    "nodes": [
        {
            "id": "pop_a",
            "component_id": "lif_population",
            "nir_type": "nir.LIF",
            "label": "pop_a",
            "parameters": {
                "name": "pop_a",
                "n_neurons": 10,
                "threshold": 1.0,
                "tau_rc": 0.02,
                "tau_ref": 0.002,
            },
            "position": [100.0, 200.0],
        },
        {
            "id": "pop_b",
            "component_id": "lif_population",
            "nir_type": "nir.LIF",
            "label": "pop_b",
            "parameters": {
                "name": "pop_b",
                "n_neurons": 10,
                "threshold": 0.8,
                "tau_rc": 0.02,
                "tau_ref": 0.002,
            },
            "position": [400.0, 200.0],
        },
    ],
    "edges": [
        {
            "id": "edge_0",
            "source_node_id": "pop_a",
            "source_port": "out",
            "target_node_id": "pop_b",
            "target_port": "in",
            "parameters": {"synapse_type": "static_synapse", "weight": 1.0},
        }
    ],
    "metadata": {},
}


# ---------------------------------------------------------------------------
# /canvas-to-canonical
# ---------------------------------------------------------------------------


def test_canvas_to_canonical_returns_200() -> None:
    resp = client.post("/api/neurosim/canvas-to-canonical", json={"graph": _LIF_GRAPH})
    assert resp.status_code == 200


def test_canvas_to_canonical_returns_canonical_document() -> None:
    resp = client.post("/api/neurosim/canvas-to-canonical", json={"graph": _LIF_GRAPH})
    assert resp.status_code == 200
    body = resp.json()
    assert "document" in body
    doc = body["document"]
    assert "ir_json" in doc
    assert "cnl_text" in doc
    assert doc["cnl_text"] != ""
    assert "canvas" in doc


def test_canvas_to_canonical_canvas_has_nodes() -> None:
    resp = client.post("/api/neurosim/canvas-to-canonical", json={"graph": _LIF_GRAPH})
    assert resp.status_code == 200
    canvas = resp.json()["document"]["canvas"]
    assert canvas is not None
    node_ids = {n["id"] for n in canvas["nodes"]}
    assert "pop_a" in node_ids
    assert "pop_b" in node_ids


def test_canvas_to_canonical_preserves_edges() -> None:
    resp = client.post("/api/neurosim/canvas-to-canonical", json={"graph": _LIF_GRAPH})
    assert resp.status_code == 200
    canvas = resp.json()["document"]["canvas"]
    assert canvas is not None
    assert len(canvas["edges"]) == 1
    assert canvas["edges"][0]["source"] == "pop_a"
    assert canvas["edges"][0]["target"] == "pop_b"


def test_canvas_to_canonical_cnl_contains_node_names() -> None:
    resp = client.post("/api/neurosim/canvas-to-canonical", json={"graph": _LIF_GRAPH})
    assert resp.status_code == 200
    cnl = resp.json()["document"]["cnl_text"]
    assert "pop_a" in cnl
    assert "pop_b" in cnl


def test_canvas_to_canonical_empty_graph_returns_422() -> None:
    resp = client.post(
        "/api/neurosim/canvas-to-canonical",
        json={"graph": {"nodes": [], "edges": [], "metadata": {}}},
    )
    assert resp.status_code == 422


# ---------------------------------------------------------------------------
# /canvas-mutation
# ---------------------------------------------------------------------------


def _get_canonical_doc() -> dict[str, Any]:
    """Helper: get a canonical document by parsing the LIF graph."""
    resp = client.post("/api/neurosim/canvas-to-canonical", json={"graph": _LIF_GRAPH})
    assert resp.status_code == 200
    document: dict[str, Any] = resp.json()["document"]
    return document


def test_canvas_mutation_returns_200() -> None:
    doc = _get_canonical_doc()
    mutation = {"node_id": "pop_a", "threshold": 2.0}
    resp = client.post(
        "/api/neurosim/canvas-mutation",
        json={"document": doc, "mutation": mutation},
    )
    assert resp.status_code == 200


def test_canvas_mutation_updates_threshold() -> None:
    doc = _get_canonical_doc()
    mutation = {"node_id": "pop_a", "threshold": 2.5}
    resp = client.post(
        "/api/neurosim/canvas-mutation",
        json={"document": doc, "mutation": mutation},
    )
    assert resp.status_code == 200
    updated_doc = resp.json()["document"]
    pop = updated_doc["ir_json"]["populations"]["pop_a"]
    assert pop["threshold"] == 2.5


def test_canvas_mutation_returns_full_canonical_document() -> None:
    doc = _get_canonical_doc()
    mutation = {"node_id": "pop_b", "membrane_time_constant": 0.05}
    resp = client.post(
        "/api/neurosim/canvas-mutation",
        json={"document": doc, "mutation": mutation},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert "document" in body
    updated_doc = body["document"]
    assert "cnl_text" in updated_doc
    assert updated_doc["cnl_text"] != ""
    assert "canvas" in updated_doc


def test_canvas_mutation_unknown_node_returns_422() -> None:
    doc = _get_canonical_doc()
    mutation = {"node_id": "does_not_exist", "threshold": 1.0}
    resp = client.post(
        "/api/neurosim/canvas-mutation",
        json={"document": doc, "mutation": mutation},
    )
    assert resp.status_code == 422


# ---------------------------------------------------------------------------
# Network-level timestep (graph.metadata["dt"]) round trip
#
# Companion to the nir_cnl grammar's optional `with timestep <seconds>`
# clause. Without this round trip, editing any canvas node/edge (which goes
# through /canvas-to-canonical) silently drops a declared network timestep.
# ---------------------------------------------------------------------------


def test_canvas_to_canonical_preserves_network_dt_in_cnl_text() -> None:
    graph_with_dt = {**_LIF_GRAPH, "metadata": {"dt": 0.005}}
    resp = client.post(
        "/api/neurosim/canvas-to-canonical", json={"graph": graph_with_dt}
    )
    assert resp.status_code == 200
    doc = resp.json()["document"]
    assert "with timestep" in doc["cnl_text"]
    assert doc["canvas"]["metadata"].get("dt") == 0.005


def test_canvas_to_canonical_no_dt_metadata_unchanged() -> None:
    """Backward-compat guard: no declared dt -> no timestep clause, no dt key."""
    resp = client.post("/api/neurosim/canvas-to-canonical", json={"graph": _LIF_GRAPH})
    assert resp.status_code == 200
    doc = resp.json()["document"]
    assert "with timestep" not in doc["cnl_text"]
    assert "dt" not in doc["canvas"]["metadata"]
