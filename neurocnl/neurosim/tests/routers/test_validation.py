from fastapi.testclient import TestClient

from neurosim.app.main import app

client = TestClient(app)

VALID_GRAPH = {
    "nodes": [
        {
            "id": "sensory_input",
            "component_id": "lif_population",
            "parameters": {
                "name": "sensory_input",
                "n_neurons": 100,
                "tau_rc": 0.02,
                "tau_ref": 0.002,
            },
            "position": [100, 200],
        },
    ],
    "edges": [],
    "metadata": {"zoom": 1.0, "pan": [0, 0]},
}


def test_validate_valid_graph() -> None:
    response = client.post("/api/neurosim/validate", json=VALID_GRAPH)
    assert response.status_code == 200
    result = response.json()
    assert result["valid"] is True
    assert result["backend_support"]["verdict"] == "approximate"
    assert result["backend_support"]["warnings"]


def test_validate_invalid_param_range() -> None:
    graph = {
        "nodes": [
            {
                "id": "bad_node",
                "component_id": "lif_population",
                "parameters": {"name": "bad", "n_neurons": 100, "tau_rc": 999.0},
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
    assert any("exceeds maximum" in e["message"] for e in result["errors"])
    assert result["backend_support"] is not None


def test_validate_marks_multi_node_runtime_path_as_unsupported() -> None:
    graph = {
        "nodes": [
            {
                "id": "sensory_input",
                "component_id": "lif_population",
                "parameters": {"name": "sensory_input", "n_neurons": 100},
                "position": [0, 0],
            },
            {
                "id": "relay",
                "component_id": "lif_population",
                "parameters": {"name": "relay", "n_neurons": 80},
                "position": [150, 0],
            },
            {
                "id": "motor_output",
                "component_id": "lif_population",
                "parameters": {"name": "motor_output", "n_neurons": 100},
                "position": [300, 0],
            },
        ],
        "edges": [
            {
                "id": "edge_0",
                "source_node_id": "sensory_input",
                "source_port": "out",
                "target_node_id": "relay",
                "target_port": "in",
                "parameters": {"weight": 1.0},
            },
            {
                "id": "edge_1",
                "source_node_id": "relay",
                "source_port": "out",
                "target_node_id": "motor_output",
                "target_port": "in",
                "parameters": {"weight": 1.0},
            },
        ],
        "metadata": {},
    }

    response = client.post("/api/neurosim/validate", json=graph)

    assert response.status_code == 200
    result = response.json()
    assert result["valid"] is True
    assert result["backend_support"]["verdict"] == "approximate"
    assert (
        "local_validation_fallback"
        in result["backend_support"]["approximated_concepts"]
    )
