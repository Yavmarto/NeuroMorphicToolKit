from fastapi.testclient import TestClient

from neurosim.app.main import app
from neurosim.contracts.design_contracts import SimulationStatus

client = TestClient(app)

VALID_GRAPH = {
    "nodes": [
        {
            "id": "n1",
            "component_id": "lif_population",
            "parameters": {"name": "P1", "tau_rc": 0.02},
            "position": [0, 0],
        }
    ],
    "edges": [],
    "metadata": {},
}


def test_sweep_lifecycle_success() -> None:
    sweep_request = {
        "graph": VALID_GRAPH,
        "parameter_path": "nodes.n1.tau_rc",
        "start": 0.01,
        "end": 0.03,
        "steps": 3,
        "simulation_duration_ms": 50.0,
    }

    # 1. Submit sweep job
    response = client.post("/api/neurosim/sweep", json=sweep_request)
    assert response.status_code == 200
    result = response.json()
    assert "job_id" in result
    job_id = result["job_id"]
    assert result["status"] == SimulationStatus.QUEUED
    assert result["parameter_path"] == "nodes.n1.tau_rc"
    assert result["steps"] is None

    # 2. Poll for completion (background tasks run immediately in TestClient by default unless configured otherwise,
    # but let's check the transitions)
    # In FastAPI TestClient, background tasks are executed during the response cycle.
    # However, since we are using a separate GET request, we should see the final state.

    status_response = client.get(f"/api/neurosim/sweep/{job_id}")
    assert status_response.status_code == 200
    status_result = status_response.json()
    assert status_result["job_id"] == job_id
    assert status_result["status"] == SimulationStatus.COMPLETED
    assert status_result["parameter_path"] == "nodes.n1.tau_rc"
    assert len(status_result["steps"]) == 3
    assert status_result["steps"][0]["parameter_value"] == 0.01
    assert status_result["steps"][2]["parameter_value"] == 0.03


def test_sweep_lifecycle_failure_invalid_path() -> None:
    sweep_request = {
        "graph": VALID_GRAPH,
        "parameter_path": "invalid.path",  # Should fail validation or during run
        "start": 0.01,
        "end": 0.03,
        "steps": 3,
        "simulation_duration_ms": 50.0,
    }

    response = client.post("/api/neurosim/sweep", json=sweep_request)
    assert response.status_code == 422
    detail = response.json()["detail"]
    assert detail["error"] == "invalid_sweep_path"
    assert "expected format" in detail["message"]


def test_sweep_lifecycle_failure_missing_node() -> None:
    sweep_request = {
        "graph": VALID_GRAPH,
        "parameter_path": "nodes.nonexistent.tau_rc",
        "start": 0.01,
        "end": 0.03,
        "steps": 3,
        "simulation_duration_ms": 50.0,
    }

    response = client.post("/api/neurosim/sweep", json=sweep_request)
    assert response.status_code == 422
    detail = response.json()["detail"]
    assert detail["error"] == "invalid_sweep_path"
    assert "No node with id" in detail["message"]


def test_sweep_lifecycle_failure_non_numeric_param() -> None:
    sweep_request = {
        "graph": VALID_GRAPH,
        "parameter_path": "nodes.n1.name",
        "start": 0.01,
        "end": 0.03,
        "steps": 3,
        "simulation_duration_ms": 50.0,
    }

    response = client.post("/api/neurosim/sweep", json=sweep_request)
    assert response.status_code == 422
    detail = response.json()["detail"]
    assert detail["error"] == "invalid_sweep_path"
    assert "not a supported sweep target" in detail["message"]


def test_sweep_lifecycle_failure_preview_error() -> None:
    bad_sweep = {
        "graph": {
            "nodes": [
                {
                    "id": "n1",
                    "component_id": "lif_population",
                    "parameters": {"name": "P1", "tau_rc": 0.01, "tau_ref": 0.002},
                    "position": [0, 0],
                }
            ],
            "edges": [],
            "metadata": {},
        },
        "parameter_path": "nodes.n1.tau_ref",
        "start": 0.02,  # start > tau_rc (0.01) -> should fail invariant
        "end": 0.03,
        "steps": 2,
    }

    response = client.post("/api/neurosim/sweep", json=bad_sweep)
    assert response.status_code == 200
    job_id = response.json()["job_id"]

    status_response = client.get(f"/api/neurosim/sweep/{job_id}")
    assert status_response.status_code == 200
    status_result = status_response.json()
    assert status_result["status"] == SimulationStatus.FAILED
    assert "error" in status_result
    assert status_result["error"] is not None


def test_sweep_job_not_found() -> None:
    response = client.get("/api/neurosim/sweep/non-existent-id")
    assert response.status_code == 404
    assert response.json()["detail"] == "Sweep job not found"
