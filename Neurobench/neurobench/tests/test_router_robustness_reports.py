from unittest.mock import MagicMock, patch

import pytest
from fastapi.testclient import TestClient

from app.schemas.results import BenchmarkResult


@pytest.fixture
def mock_benchmark_result() -> BenchmarkResult:
    return BenchmarkResult(
        id="res_test",
        benchmark_id="spike_classification",
        network_spec_hash="hash_test",
        timestamp="2024-01-01T00:00:00Z",
        params={},
        metrics={"accuracy": 0.9},
        wall_time_seconds=0.1,
        seed=0,
    )


@patch("app.services.fault_sweeper.benchmark_runner.run_benchmark")
def test_faults_endpoints(
    mock_run: MagicMock,
    client: TestClient,
    mock_benchmark_result: BenchmarkResult,
) -> None:
    """Tests the fault injection sweep endpoints."""
    mock_run.return_value = mock_benchmark_result

    payload = {
        "cnl_spec_path": __import__("os").path.join(
            __import__("os").path.dirname(__file__), "test_network.cnl"
        ),
        "benchmark_id": "spike_classification",
    }
    response = client.post("/api/neurobench/faults/sweep", json=payload)
    assert response.status_code == 200
    assert "fault_type" in response.json()


@patch("app.services.perturbation_sweeper.benchmark_runner.run_benchmark")
def test_perturbation_endpoints(
    mock_run: MagicMock,
    client: TestClient,
    mock_benchmark_result: BenchmarkResult,
) -> None:
    """Tests the input perturbation sweep endpoints."""
    mock_run.return_value = mock_benchmark_result

    payload = {
        "cnl_spec_path": __import__("os").path.join(
            __import__("os").path.dirname(__file__), "test_network.cnl"
        ),
        "benchmark_id": "spike_classification",
        "dataset_path": "tests/test_data.npy",
    }
    response = client.post("/api/neurobench/perturbation/sweep", json=payload)
    assert response.status_code == 200
    assert isinstance(response.json(), dict)


def test_reports_endpoints(client: TestClient) -> None:
    """Tests the report generation endpoint."""
    response = client.post("/api/neurobench/report")
    assert response.status_code == 200
    assert isinstance(response.json(), dict)
