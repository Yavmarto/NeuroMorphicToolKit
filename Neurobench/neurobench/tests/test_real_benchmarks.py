import time

import pytest
from fastapi.testclient import TestClient

from app.schemas.benchmarks import JobStatus


def test_async_benchmark_execution(client: TestClient) -> None:
    """Tests the full async benchmark execution flow."""
    # 1. Submit a job
    payload = {
        "benchmark_id": "reaction_latency",
        "network_path": __import__("os").path.join(
            __import__("os").path.dirname(__file__), "test_network.cnl"
        ),
        "target": "simulation",
    }
    response = client.post("/api/neurobench/run", json=payload)
    assert response.status_code == 200
    job_id = response.json()["job_id"]
    assert job_id.startswith("job_")

    # 2. Poll status until completed
    max_retries = 15
    completed = False
    for _ in range(max_retries):
        response = client.get(f"/api/neurobench/run/{job_id}")
        assert response.status_code == 200
        status = response.json()["status"]
        if status == JobStatus.COMPLETED:
            completed = True
            break
        elif status == JobStatus.FAILED:
            pytest.fail(f"Job failed: {response.json().get('error')}")
        time.sleep(1.0)

    assert completed, "Job did not complete in time"
    result_id = response.json()["result_id"]
    assert result_id is not None

    # 3. Get the result
    response = client.get(f"/api/neurobench/run/{job_id}/result")
    assert response.status_code == 200
    result = response.json()
    assert result["id"] == result_id
    assert "assertions_passed" in result["metrics"]
    assert result["metrics"]["assertions_passed"] >= 0


def test_cancel_job(client: TestClient) -> None:
    """Tests job cancellation."""
    payload = {
        "benchmark_id": "reaction_latency",
        "network_path": __import__("os").path.join(
            __import__("os").path.dirname(__file__), "test_network.cnl"
        ),
        "target": "neurochip",
    }
    response = client.post("/api/neurobench/run", json=payload)
    job_id = response.json()["job_id"]

    # Cancel immediately
    response = client.delete(f"/api/neurobench/run/{job_id}")
    assert response.status_code == 200
    assert response.json()["success"] is True

    # Verify status is CANCELLED
    response = client.get(f"/api/neurobench/run/{job_id}")
    assert response.json()["status"] == JobStatus.CANCELLED
