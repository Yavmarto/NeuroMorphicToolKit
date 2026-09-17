from fastapi.testclient import TestClient

from neurosim.app.main import app

client = TestClient(app)


def test_validate_tau_invariant_violation() -> None:
    """Test that tau_ref >= tau_rc fails validation."""
    graph = {
        "nodes": [
            {
                "id": "lif_node",
                "component_id": "lif_population",
                "parameters": {
                    "name": "lif",
                    "tau_rc": 0.020,
                    "tau_ref": 0.030,
                },
                "position": [0, 0],
            },
        ],
        "edges": [],
        "metadata": {},
    }
    response = client.post("/api/neurosim/validate", json=graph)
    assert response.status_code == 200
    result = response.json()
    assert result["valid"] is False
    assert len(result["errors"]) == 1
    error = result["errors"][0]
    assert error["element_id"] == "lif_node"
    assert error["field"] == "parameters.tau_ref"
    assert "tau_ref (0.03) must be less than tau_rc (0.02)" in error["message"]
    assert error["severity"] == "error"


def test_validate_tau_invariant_valid() -> None:
    """Test that tau_ref < tau_rc passes validation."""
    graph = {
        "nodes": [
            {
                "id": "lif_node",
                "component_id": "lif_population",
                "parameters": {
                    "name": "lif",
                    "tau_rc": 0.020,
                    "tau_ref": 0.002,
                },
                "position": [0, 0],
            },
        ],
        "edges": [],
        "metadata": {},
    }
    response = client.post("/api/neurosim/validate", json=graph)
    assert response.status_code == 200
    result = response.json()
    assert result["valid"] is True
    assert len(result["errors"]) == 0


def test_validate_adaptive_lif_violation() -> None:
    """Test that tau_ref >= tau_rc fails validation for adaptive_lif."""
    graph = {
        "nodes": [
            {
                "id": "alif_node",
                "component_id": "adaptive_lif",
                "parameters": {
                    "name": "alif",
                    "tau_rc": 0.020,
                    "tau_ref": 0.020,
                },
                "position": [0, 0],
            },
        ],
        "edges": [],
        "metadata": {},
    }
    response = client.post("/api/neurosim/validate", json=graph)
    assert response.status_code == 200
    result = response.json()
    assert result["valid"] is False
    assert any(
        "tau_ref (0.02) must be less than tau_rc (0.02)" in e["message"]
        for e in result["errors"]
    )
