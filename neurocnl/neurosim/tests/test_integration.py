import json
from collections.abc import Callable
from typing import Any

from fastapi.testclient import TestClient


def _run_preview_job(
    client: TestClient,
    parsed_graph: Any,
    wait_for_preview_completion: Callable[[str], dict[str, Any]],
) -> dict[str, Any]:
    preview_response = client.post(
        "/api/neurosim/preview",
        json={"graph": parsed_graph, "duration_ms": 100},
    )
    assert preview_response.status_code == 200
    preview_job: dict[str, Any] = preview_response.json()
    assert preview_job["status"] in {"queued", "running", "completed"}
    assert preview_job["backend_support"]["verdict"] == "approximate"
    assert preview_job["job_id"] is not None

    preview_result = wait_for_preview_completion(preview_job["job_id"])
    assert preview_result["status"] == "completed"
    assert preview_result["backend_support"]["verdict"] == "approximate"
    assert "exc_pop" in preview_result["results"]
    assert "inh_pop" in preview_result["results"]
    assert "spikes" in preview_result["results"]["exc_pop"]
    return preview_job


def _run_sweep_job(
    client: TestClient,
    parsed_graph: Any,
    wait_for_sweep_completion: Callable[[str], dict[str, Any]],
) -> dict[str, Any]:
    sweep_response = client.post(
        "/api/neurosim/sweep",
        json={
            "graph": parsed_graph,
            "parameter_path": "nodes.exc_pop.tau_rc",
            "start": 0.01,
            "end": 0.03,
            "steps": 2,
            "simulation_duration_ms": 50,
        },
    )
    assert sweep_response.status_code == 200
    sweep_job: dict[str, Any] = sweep_response.json()
    assert sweep_job["status"] in {"queued", "running", "completed"}
    assert sweep_job["job_id"] is not None

    sweep_result = wait_for_sweep_completion(sweep_job["job_id"])
    assert sweep_result["status"] == "completed"
    assert sweep_result["parameter_path"] == "nodes.exc_pop.tau_rc"
    assert len(sweep_result["steps"]) == 2
    assert sweep_result["steps"][0]["result"]["status"] == "completed"
    return sweep_job


def _assert_sweep_exports(client: TestClient, sweep_job_id: Any) -> None:
    export_sweep_json_response = client.get(
        f"/api/neurosim/export/sweep/{sweep_job_id}/json"
    )
    assert export_sweep_json_response.status_code == 200
    export_sweep_json = export_sweep_json_response.json()
    assert export_sweep_json["format"] == "json"
    exported_steps = json.loads(export_sweep_json["content"])
    assert len(exported_steps) == 2
    assert exported_steps[0]["parameter_value"] == 0.01

    export_sweep_csv_response = client.get(
        f"/api/neurosim/export/sweep/{sweep_job_id}/csv"
    )
    assert export_sweep_csv_response.status_code == 200
    export_sweep_csv = export_sweep_csv_response.json()
    assert export_sweep_csv["format"] == "csv"
    assert "parameter_value,n_neurons,n_connections" in export_sweep_csv["content"]
    assert "0.01," in export_sweep_csv["content"]


def test_full_pipeline_shared_neurocnl_path(
    client: TestClient,
    canonical_graph: dict[str, Any],
    wait_for_preview_completion: Callable[[str], dict[str, Any]],
    wait_for_sweep_completion: Callable[[str], dict[str, Any]],
) -> None:
    # Step 1: generate-cnl must return NIR-native format (not legacy MUST-format).
    generate_response = client.post("/api/neurosim/generate-cnl", json=canonical_graph)
    assert generate_response.status_code == 200
    cnl_spec = generate_response.json()["cnl_spec"]
    assert "exc_pop" in cnl_spec
    assert "inh_pop" in cnl_spec
    assert "Define a LIF neuron named exc_pop" in cnl_spec
    assert "MUST" not in cnl_spec  # no legacy Biological_Grammar tokens

    # Note: parse-cnl requires explicit Input/Output port nodes in the CNL.
    # The canonical_graph fixture uses the legacy lif_population format
    # (no nir_type, no I/O ports), so the generated CNL only contains
    # LIF neurons and lacks endpoint nodes.  parse-cnl-canonical handles
    # this for the editor pipeline; the simulation pipeline (validate,
    # preview, sweep, export) operates on the original canvas graph directly.

    validate_response = client.post("/api/neurosim/validate", json=canonical_graph)
    assert validate_response.status_code == 200
    validation = validate_response.json()
    assert validation["valid"] is True
    assert validation["backend_support"]["verdict"] == "approximate"
    assert all(
        "local preview" not in warning.lower()
        for warning in validation["backend_support"]["warnings"]
    )

    _run_preview_job(client, canonical_graph, wait_for_preview_completion)
    sweep_job = _run_sweep_job(client, canonical_graph, wait_for_sweep_completion)

    export_graph_response = client.post(
        "/api/neurosim/export/cnl", json=canonical_graph
    )
    assert export_graph_response.status_code == 200
    export_graph = export_graph_response.json()
    assert export_graph["format"] == "cnl"
    assert export_graph["backend_support"]["verdict"] == "faithful"
    assert "exc_pop" in export_graph["content"]
    assert "inh_pop" in export_graph["content"]

    _assert_sweep_exports(client, sweep_job["job_id"])


def test_parse_cnl_rejects_implicit_local_semantics(
    client: TestClient, canonical_graph: dict[str, Any]
) -> None:
    cnl_spec = (
        "Create a population 'sensory' of 50 LIF neurons with tau_rc=0.02 and tau_ref=0.002.\n"
        "Create a population 'motor' of 50 LIF neurons with tau_rc=0.02 and tau_ref=0.002.\n"
        "Connect 'sensory' to 'motor' with a static synapse of weight 1.0 and delay 0.001.\n"
    )

    parse_response = client.post("/api/neurosim/parse-cnl", json={"cnl_spec": cnl_spec})

    assert parse_response.status_code == 422
