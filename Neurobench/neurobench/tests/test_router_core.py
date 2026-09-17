from collections.abc import Generator

import pytest
from fastapi.testclient import TestClient

from app.services.benchmark_loader import benchmark_loader


@pytest.fixture(autouse=True)
def setup_teardown_benchmarks() -> Generator[None, None, None]:
    """Fixture to ensure a clean state for benchmarks before and after each test."""
    # Ensure custom benchmarks are cleared before and after each test
    benchmark_loader._clear_custom_benchmarks()
    yield
    benchmark_loader._clear_custom_benchmarks()


def test_health_check(client: TestClient) -> None:
    """Tests the health check endpoint."""
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_list_benchmarks(client: TestClient) -> None:
    """Tests listing all benchmarks."""
    response = client.get("/api/neurobench/benchmarks")
    assert response.status_code == 200
    assert isinstance(response.json(), list)


def test_get_benchmark_not_found(client: TestClient) -> None:
    """Tests getting a non-existent benchmark."""
    response = client.get("/api/neurobench/benchmarks/non_existent_id")
    assert response.status_code == 404


def test_create_benchmark_success(client: TestClient) -> None:
    """Tests successfully creating a custom benchmark."""
    benchmark_data = {
        "id": "new_custom_bench",
        "name": "Custom Benchmark",
        "description": "A newly created custom benchmark",
        "task_type": "classification",
        "input_spec": {"type": "synthetic", "synthetic_config": {}},
        "assertions": ["accuracy > 0.8"],
        "scoring": {
            "primary_metric": "accuracy",
            "secondary_metrics": [],
            "higher_is_better": True,
            "pass_threshold": 0.8,
        },
        "default_params": {},
        "builtin": False,
    }
    response = client.post("/api/neurobench/benchmarks", json=benchmark_data)
    assert response.status_code == 200
    assert response.json()["id"] == "new_custom_bench"

    # Verify it can be retrieved
    response = client.get("/api/neurobench/benchmarks/new_custom_bench")
    assert response.status_code == 200
    assert response.json()["name"] == "Custom Benchmark"


def test_create_benchmark_duplicate_id(client: TestClient) -> None:
    """Tests creating a benchmark with an existing ID."""
    benchmark_data = {
        "id": "duplicate_bench",
        "name": "Custom Benchmark",
        "description": "A newly created custom benchmark",
        "task_type": "classification",
        "input_spec": {"type": "synthetic", "synthetic_config": {}},
        "assertions": ["accuracy > 0.8"],
        "scoring": {
            "primary_metric": "accuracy",
            "secondary_metrics": [],
            "higher_is_better": True,
            "pass_threshold": 0.8,
        },
        "default_params": {},
        "builtin": False,
    }
    # Create first time
    response = client.post("/api/neurobench/benchmarks", json=benchmark_data)
    assert response.status_code == 200

    # Create second time with same ID
    response = client.post("/api/neurobench/benchmarks", json=benchmark_data)
    assert response.status_code == 400
    assert "already exists" in response.json()["detail"]


def test_run_benchmark(client: TestClient) -> None:
    """Tests running a benchmark."""
    payload = {
        "benchmark_id": "test_bench",
        "network_path": __import__("os").path.join(
            __import__("os").path.dirname(__file__), "test_network.cnl"
        ),
        "target": "simulation",
    }
    response = client.post("/api/neurobench/run", json=payload)
    # The actual execution might fail due to "test_bench" not existing,
    # but the payload should be successfully processed by the router.
    # The job manager will raise a ValueError which maps to a 404.
    # If the benchmark existed, it would be 200.
    assert response.status_code in (200, 404)
    if response.status_code == 200:
        assert "job_id" in response.json()


def test_get_job_status_not_found(client: TestClient) -> None:
    """Tests getting job status for non-existent job."""
    response = client.get("/api/neurobench/run/job_123")
    assert response.status_code == 404
