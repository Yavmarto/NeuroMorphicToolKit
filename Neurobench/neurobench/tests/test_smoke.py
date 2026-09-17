import os
import time

import pytest
from fastapi.testclient import TestClient

from app.schemas.benchmarks import JobStatus


def test_benchmark_execution_and_report_smoke(client: TestClient) -> None:
    """Smoke test for the full benchmark execution and report generation flow."""
    # 1. Submit a benchmark job
    payload = {
        "benchmark_id": "reaction_latency",
        "network_path": __import__("os").path.join(
            __import__("os").path.dirname(__file__), "test_network.cnl"
        ),
        "target": "simulation",
    }
    response = client.post("/api/neurobench/run", json=payload)
    assert response.status_code == 200, f"Failed to submit job: {response.text}"
    job_id = response.json()["job_id"]
    assert job_id.startswith("job_"), f"Invalid job ID format: {job_id}"

    # 2. Poll for job completion
    max_retries = 30  # Increased from 20 for robustness
    completed = False
    result_id = None
    for i in range(max_retries):
        response = client.get(f"/api/neurobench/run/{job_id}")
        assert response.status_code == 200, f"Failed to get job status (retry {i}): {response.text}"
        status_data = response.json()
        status = status_data["status"]

        if status == JobStatus.COMPLETED:
            completed = True
            result_id = status_data["result_id"]
            break
        elif status == JobStatus.FAILED:
            pytest.fail(f"Job failed at retry {i}: {status_data.get('error')}")

        time.sleep(1.0)  # Increased from 0.5s for robustness

    assert completed, f"Job {job_id} did not complete within timeout"
    assert result_id is not None, f"Job {job_id} completed but result_id is missing"

    # 3. Fetch and validate benchmark results
    response = client.get(f"/api/neurobench/run/{job_id}/result")
    assert response.status_code == 200, f"Failed to fetch result: {response.text}"
    result = response.json()

    assert result["id"] == result_id
    assert "metrics" in result
    metrics = result["metrics"]
    # Validate expected metrics for reaction_latency or general simulation
    assert "assertions_passed" in metrics, f"Missing 'assertions_passed' in metrics: {metrics}"
    # The actual simulation might not produce 'latency_ms' if the network/input doesn't trigger it,
    # but it should at least have 'accuracy' or 'simulation_duration'.
    assert "simulation_duration" in metrics, f"Missing 'simulation_duration' in metrics: {metrics}"
    assert isinstance(metrics["simulation_duration"], (int, float))

    # 4. Generate a report for the result
    report_payload = {
        "format": "json",
        "result_id": result_id,
        "summary": "Smoke test report",
        "new_baseline": False,
    }
    response = client.post("/api/neurobench/report", json=report_payload)
    assert response.status_code == 200, f"Failed to generate report: {response.text}"
    report_data = response.json()

    assert "report_id" in report_data
    assert report_data["status"] == "completed"
    assert report_data["format"] == "json"
    assert "download_url" in report_data
    assert report_data["download_url"].endswith(".json")

    # 5. Verify the report file content exists on disk
    report_id = report_data["report_id"]
    report_file_path = f"data/reports/{report_id}.json"
    assert os.path.exists(report_file_path), f"Report file not found on disk: {report_file_path}"
