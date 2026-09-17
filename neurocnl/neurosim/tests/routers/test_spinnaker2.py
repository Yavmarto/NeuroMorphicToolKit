import pytest
from fastapi.testclient import TestClient

from neurosim.app.main import app
from neurosim.app.routers import spinnaker2 as spinnaker2_router
from neurosim.contracts.design_contracts import SimulationStatus

client = TestClient(app)

VALID_GRAPH = {
    "nodes": [
        {
            "id": "node1",
            "component_id": "lif",
            "parameters": {"n_neurons": 10},
            "position": [0, 0],
        },
        {
            "id": "node2",
            "component_id": "lif",
            "parameters": {"n_neurons": 20},
            "position": [100, 100],
        },
    ],
    "edges": [
        {
            "id": "edge1",
            "source_node_id": "node1",
            "source_port": "out",
            "target_node_id": "node2",
            "target_port": "in",
            "parameters": {"weight": 1.5, "delay": 2.0},
        }
    ],
    "metadata": {},
}


def test_spinnaker2_missing_sdk_returns_failed(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(spinnaker2_router, "SPINNAKER2_AVAILABLE", False)
    monkeypatch.setattr(
        "neurosim.app.backends.spinnaker2_backend.SPINNAKER2_AVAILABLE",
        False,
    )

    response = client.post(
        "/api/sim/spinnaker2/run",
        json={"graph": VALID_GRAPH, "duration_ms": 100},
    )
    assert response.status_code == 200
    result = response.json()
    assert result["status"] == SimulationStatus.FAILED
    assert result["backend_type"] == "unavailable"
    assert "py-spinnaker2" in result["error"]


def test_spinnaker2_explicit_mock_mode_returns_completed_labeled(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(spinnaker2_router, "SPINNAKER2_AVAILABLE", False)
    monkeypatch.setattr(
        "neurosim.app.backends.spinnaker2_backend.SPINNAKER2_AVAILABLE",
        False,
    )

    response = client.post(
        "/api/sim/spinnaker2/run?mock_mode=true",
        json={"graph": VALID_GRAPH, "duration_ms": 100},
    )
    assert response.status_code == 200
    result = response.json()
    assert "job_id" in result
    assert result["status"] == SimulationStatus.COMPLETED
    assert result["backend_type"] == "mock"
    assert len(result["results"]["node1"]["spikes"]) == 10


def test_spinnaker2_get_results_not_found() -> None:
    response = client.get("/api/sim/spinnaker2/results/nonexistent")
    assert response.status_code == 404
    assert response.json()["detail"] == "Run not found or expired"
