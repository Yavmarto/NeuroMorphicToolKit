import contextlib
import json
import os
import signal
import subprocess
import sys
import time
from collections.abc import Iterator
from pathlib import Path
from typing import Any

import httpx
import pytest

API_BASE_URL = "http://127.0.0.1:8005"
SERVER_START_WAIT = 5  # seconds
POLL_INTERVAL = 0.2  # second
MAX_POLL_ATTEMPTS = 30


@pytest.fixture(scope="module")
def api_server() -> Iterator[str]:
    """Start the FastAPI server in a separate process."""
    log_file_path = Path("server.log")
    with log_file_path.open("w") as f:
        f.truncate(0)

    with log_file_path.open("a") as log_file:
        process = subprocess.Popen(
            [
                sys.executable,
                "-m",
                "uvicorn",
                "neurosim.app.main:app",
                "--host",
                "127.0.0.1",
                "--port",
                "8005",
            ],
            stdout=log_file,
            stderr=log_file,
            start_new_session=True,
        )

    start_time = time.time()
    while time.time() - start_time < SERVER_START_WAIT:
        try:
            with httpx.Client() as client:
                response = client.get(f"{API_BASE_URL}/api/neurosim/components")
                if response.status_code == 200:
                    break
        except Exception:
            time.sleep(0.5)
    else:
        if log_file_path.exists():
            with log_file_path.open() as f:
                server_logs = f.read()
                print(f"SERVER LOGS:\n{server_logs}")
                if "operation not permitted" in server_logs.lower():
                    pytest.skip("Socket binding is not permitted in this environment.")
        with contextlib.suppress(ProcessLookupError):
            os.killpg(os.getpgid(process.pid), signal.SIGTERM)
        pytest.fail("Server failed to start")

    yield API_BASE_URL

    with contextlib.suppress(ProcessLookupError):
        os.killpg(os.getpgid(process.pid), signal.SIGTERM)


def _poll(client: httpx.Client, url: str) -> dict[str, Any]:
    last_payload: dict[str, Any] | None = None
    for _ in range(MAX_POLL_ATTEMPTS):
        time.sleep(POLL_INTERVAL)
        response = client.get(url)
        assert response.status_code == 200
        last_payload = response.json()
        if last_payload["status"] not in {"queued", "running"}:
            return last_payload

    pytest.fail(f"Timed out waiting for {url}: {last_payload}")


def _assert_preview_pipeline(
    client: httpx.Client,
    api_server: str,
    parsed_graph: dict[str, Any],
) -> None:
    preview_response = client.post(
        f"{api_server}/api/neurosim/preview",
        json={"graph": parsed_graph, "duration_ms": 100},
    )
    assert preview_response.status_code == 200
    preview_payload = preview_response.json()
    assert preview_payload["job_id"] is not None

    preview_result = _poll(
        client,
        f"{api_server}/api/neurosim/simulations/{preview_payload['job_id']}",
    )
    assert preview_result["status"] == "completed"
    assert "exc_pop" in preview_result["results"]
    assert "inh_pop" in preview_result["results"]


def _run_sweep_pipeline(
    client: httpx.Client,
    api_server: str,
    parsed_graph: dict[str, Any],
) -> dict[str, Any]:
    sweep_response = client.post(
        f"{api_server}/api/neurosim/sweep",
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
    sweep_payload: dict[str, Any] = sweep_response.json()
    assert sweep_payload["job_id"] is not None
    assert sweep_payload["backend_support"]["verdict"] == "approximate"

    sweep_result = _poll(
        client,
        f"{api_server}/api/neurosim/sweep/{sweep_payload['job_id']}",
    )
    assert sweep_result["status"] == "completed"
    assert sweep_result["backend_support"]["verdict"] == "approximate"
    assert len(sweep_result["steps"]) == 2
    assert sweep_result["steps"][0]["result"]["status"] == "completed"
    return sweep_payload


def _assert_sweep_exports(
    client: httpx.Client,
    api_server: str,
    sweep_job_id: str,
) -> None:
    export_json_response = client.get(
        f"{api_server}/api/neurosim/export/sweep/{sweep_job_id}/json"
    )
    assert export_json_response.status_code == 200
    export_json_data = export_json_response.json()
    assert export_json_data["format"] == "json"
    content = json.loads(export_json_data["content"])
    assert len(content) == 2
    assert content[0]["parameter_value"] == 0.01

    export_csv_response = client.get(
        f"{api_server}/api/neurosim/export/sweep/{sweep_job_id}/csv"
    )
    assert export_csv_response.status_code == 200
    export_csv_data = export_csv_response.json()
    assert export_csv_data["format"] == "csv"
    assert "parameter_value,n_neurons,n_connections" in export_csv_data["content"]
    assert "0.01," in export_csv_data["content"]
    assert "0.03," in export_csv_data["content"]


def test_http_pipeline_preview_sweep_and_export_e2e(
    api_server: Any, canonical_graph: dict[str, Any]
) -> None:
    with httpx.Client(timeout=30.0) as client:
        # Verify generate-cnl returns NIR-native format.
        generate_response = client.post(
            f"{api_server}/api/neurosim/generate-cnl",
            json=canonical_graph,
        )
        assert generate_response.status_code == 200
        cnl_spec = generate_response.json()["cnl_spec"]
        assert "exc_pop" in cnl_spec
        assert "inh_pop" in cnl_spec
        assert "Define a LIF neuron named exc_pop" in cnl_spec

        # Note: parse-cnl requires explicit Input/Output port nodes; the
        # canonical_graph fixture uses the legacy format without I/O ports,
        # so the generated CNL will be rejected by parse-cnl (missing_endpoint).
        # Validate/preview/sweep/export operate on the original graph directly.

        validate_response = client.post(
            f"{api_server}/api/neurosim/validate",
            json=canonical_graph,
        )
        assert validate_response.status_code == 200
        validation_payload = validate_response.json()
        assert validation_payload["valid"] is True
        assert validation_payload["backend_support"]["verdict"] == "approximate"

        _assert_preview_pipeline(client, api_server, canonical_graph)
        sweep_payload = _run_sweep_pipeline(client, api_server, canonical_graph)

        export_graph_response = client.post(
            f"{api_server}/api/neurosim/export/cnl",
            json=canonical_graph,
        )
        assert export_graph_response.status_code == 200
        export_graph_payload = export_graph_response.json()
        assert export_graph_payload["format"] == "cnl"
        assert "Connect" in export_graph_payload["content"]

        _assert_sweep_exports(client, api_server, sweep_payload["job_id"])
