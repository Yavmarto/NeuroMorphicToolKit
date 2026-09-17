"""Tests for the /api/neurosim/handoff endpoint — NIR-native CNL contract."""

from pathlib import Path

from fastapi.testclient import TestClient

from backend.app.main import app

client = TestClient(app)

# The reflex-arc template: 2 LIF neurons (sensor, actuator) connected via a
# linear transformation node.  The handoff extracts only the neuron nodes.
VALID_SPEC = (
    Path(__file__).resolve().parent.parent / "app" / "templates" / "reflex_arc.cnl"
).read_text()


def test_neurosim_handoff_returns_canonical_import_contract() -> None:
    response = client.post("/api/neurosim/handoff", json={"spec": VALID_SPEC})

    assert response.status_code == 200
    payload = response.json()
    import_contract = payload["import_contract"]
    cnl_spec = import_contract["cnl_spec"]
    graph = import_contract["graph"]

    # cnl_spec contains the NIR-native text with comment lines stripped.
    assert "Define a LIF neuron named sensor" in cnl_spec
    assert "sensor connects to w_sensor_actuator" in cnl_spec

    # Structural handoff fields must be present.
    assert import_contract["payload_type"] == "neurocnl_import_contract"
    assert import_contract["semantics_mode"] == "canonical_import"

    # The reflex-arc template has exactly 2 LIF neuron nodes (sensor, actuator).
    # Linear transformation nodes (w_sensor_actuator) are not included in the
    # neuron-level graph because they are weight bridges, not spiking populations.
    assert len(graph["nodes"]) == 2
    node_ids = {n["id"] for n in graph["nodes"]}
    assert "sensor" in node_ids
    assert "actuator" in node_ids


def test_neurosim_handoff_rejects_invalid_spec() -> None:
    response = client.post("/api/neurosim/handoff", json={"spec": "not valid cnl"})

    assert response.status_code == 400
    detail = response.json()["detail"]
    # The error message mentions that parsing failed.
    assert "parse" in detail.lower() or "failed" in detail.lower()
