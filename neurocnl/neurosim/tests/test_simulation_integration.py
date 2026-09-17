from collections.abc import Callable
from typing import Any

from fastapi.testclient import TestClient


def test_preview_reports_approximate_support_for_shared_neurocnl_graph(
    client: TestClient,
    canonical_graph: dict[str, Any],
    wait_for_preview_completion: Callable[[str], dict[str, Any]],
) -> None:
    response = client.post(
        "/api/neurosim/preview",
        json={"graph": canonical_graph, "duration_ms": 100},
    )
    assert response.status_code == 200
    payload = response.json()
    assert payload["backend_support"]["verdict"] == "approximate"
    assert any(
        "approximates" in warning.lower()
        for warning in payload["backend_support"]["warnings"]
    )

    completed = wait_for_preview_completion(payload["job_id"])
    assert completed["status"] == "completed"
    assert completed["backend_support"]["verdict"] == "approximate"
    assert "voltage" in completed["results"]["exc_pop"]
    assert "spikes" in completed["results"]["inh_pop"]


def test_export_requires_confirmation_for_approximate_python_support(
    client: TestClient, canonical_graph: dict[str, Any]
) -> None:
    preflight_response = client.post(
        "/api/neurosim/export/python?preflight=true",
        json=canonical_graph,
    )
    assert preflight_response.status_code == 200
    preflight_payload = preflight_response.json()
    assert preflight_payload["content"] == ""
    assert preflight_payload["backend_support"]["verdict"] == "approximate"
    assert any(
        "local serializer" in warning.lower()
        for warning in preflight_payload["backend_support"]["warnings"]
    )

    blocked_response = client.post("/api/neurosim/export/python", json=canonical_graph)
    assert blocked_response.status_code == 409
    blocked_payload = blocked_response.json()["detail"]
    assert blocked_payload["backend_support"]["verdict"] == "approximate"
    assert "requires confirmation" in blocked_payload["message"].lower()

    confirmed_response = client.post(
        "/api/neurosim/export/python?allow_approximate=true",
        json=canonical_graph,
    )
    assert confirmed_response.status_code == 200
    confirmed_payload = confirmed_response.json()
    assert confirmed_payload["backend_support"]["verdict"] == "approximate"
    assert "import nengo" in confirmed_payload["content"]


def test_export_surfaces_unsupported_support_for_c_backend(
    client: TestClient, canonical_graph: dict[str, Any]
) -> None:
    response = client.post("/api/neurosim/export/c", json=canonical_graph)
    assert response.status_code == 400
    detail = response.json()["detail"]
    assert detail["backend_support"]["verdict"] == "unsupported"
    assert "local_export_scaffold" in detail["backend_support"]["unsupported_concepts"]
    assert "unsupported" in detail["message"].lower()


def test_sweep_reports_top_level_support_metadata(
    client: TestClient,
    canonical_graph: dict[str, Any],
    wait_for_sweep_completion: Callable[[str], dict[str, Any]],
) -> None:
    response = client.post(
        "/api/neurosim/sweep",
        json={
            "graph": canonical_graph,
            "parameter_path": "nodes.exc_pop.tau_rc",
            "start": 0.01,
            "end": 0.03,
            "steps": 2,
            "simulation_duration_ms": 50,
        },
    )
    assert response.status_code == 200
    payload = response.json()
    assert payload["backend_support"]["verdict"] == "approximate"

    completed = wait_for_sweep_completion(payload["job_id"])
    assert completed["status"] == "completed"
    assert completed["backend_support"]["verdict"] == "approximate"
    assert (
        completed["steps"][0]["result"]["backend_support"]["verdict"] == "approximate"
    )


def test_sweep_reports_approximate_support_for_local_preview_graph(
    client: TestClient,
) -> None:
    response = client.post(
        "/api/neurosim/sweep",
        json={
            "graph": {"nodes": [], "edges": [], "metadata": {}},
            "parameter_path": "nodes.exc_pop.tau_rc",
            "start": 0.01,
            "end": 0.03,
            "steps": 2,
            "simulation_duration_ms": 50,
        },
    )
    assert response.status_code == 422
    payload = response.json()["detail"]
    assert payload["error"] == "invalid_sweep_path"
