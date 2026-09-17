from unittest.mock import patch

from fastapi.testclient import TestClient

from app.schemas.results import BenchmarkResult
from app.services.result_store import result_store


def test_results_endpoints(client: TestClient) -> None:
    """Tests the benchmark results endpoints."""
    # Get all results
    response = client.get("/api/neurobench/results")
    assert response.status_code == 200
    assert isinstance(response.json(), list)

    # Get specific result (should fail as it doesn't exist)
    response = client.get("/api/neurobench/results/non_existent_result")
    assert response.status_code == 404


def test_baselines_endpoints(client: TestClient) -> None:
    """Tests the benchmark baselines endpoints."""
    # Get all baselines
    response = client.get("/api/neurobench/baselines")
    assert response.status_code == 200
    assert isinstance(response.json(), list)

    # Save a baseline
    baseline_data = {
        "id": "base_1",
        "benchmark_id": "bench_1",
        "network_spec_hash": "hash_1",
        "timestamp": "2024-01-01T00:00:00",
        "params": {},
        "metrics": {"accuracy": 0.85},
        "wall_time_seconds": 5.0,
        "seed": 123,
    }
    response = client.post("/api/neurobench/baselines", json=baseline_data)
    assert response.status_code == 200
    assert response.json()["id"] == "base_1"


def test_comparison_endpoints(client: TestClient) -> None:
    """Tests the target and encoding comparison endpoints."""
    # Compare targets
    with patch("app.services.target_comparator.benchmark_runner.run_benchmark") as mock_run:
        mock_run.return_value = BenchmarkResult(
            id="res",
            benchmark_id="b",
            network_spec_hash="h",
            timestamp="2023-01-01T00:00:00Z",
            params={},
            metrics={"accuracy": 0.9},
            wall_time_seconds=1.0,
            seed=1,
        )
        response = client.post(
            f"/api/neurobench/compare/targets?cnl_spec_path={__import__('os').path.join(__import__('os').path.dirname(__file__), 'test_network.cnl')}"
        )
        assert response.status_code == 200
        assert "targets" in response.json()

    # Compare encoding
    with patch("app.services.encoding_comparator.run_pipeline") as mock_sim:
        mock_sim.return_value = {"accuracy": 0.9, "spike_rate_hz": 100.0}
        response = client.post("/api/neurobench/compare/encoding")
        assert response.status_code == 200
        assert isinstance(response.json(), dict)


def test_export_diff_csv(client: TestClient) -> None:
    """Tests CSV export without requiring pandas at import time."""
    baseline = BenchmarkResult(
        id="base_export",
        benchmark_id="bench_export",
        network_spec_hash="hash_base",
        timestamp="2024-01-01T00:00:00Z",
        params={},
        metrics={"accuracy": 0.8, "latency_ms": 11.0},
        wall_time_seconds=1.0,
        seed=1,
    )
    current = BenchmarkResult(
        id="current_export",
        benchmark_id="bench_export",
        network_spec_hash="hash_current",
        timestamp="2024-01-02T00:00:00Z",
        params={},
        metrics={"accuracy": 0.9, "latency_ms": 10.0},
        wall_time_seconds=0.9,
        seed=1,
    )
    result_store.save_baseline(baseline)
    result_store.save_result(current)

    response = client.get(
        "/api/neurobench/compare/export",
        params={
            "baseline_ids": baseline.id,
            "current_ids": current.id,
            "format": "csv",
        },
    )

    assert response.status_code == 200
    assert response.headers["content-type"].startswith("text/csv")
    assert (
        "name,baseline_value,current_value,delta,delta_pct,status,threshold_violated"
        in response.text
    )
    assert "accuracy,0.8,0.9" in response.text
