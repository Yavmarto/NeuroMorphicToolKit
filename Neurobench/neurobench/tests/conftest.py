from pathlib import Path
from typing import Any

import pytest
from fastapi.testclient import TestClient

from app.config import settings
from app.main import app
from app.schemas.benchmarks import BenchmarkDefinition
from app.schemas.results import BenchmarkResult
from app.services.result_store import ResultStore


@pytest.fixture(autouse=True)
def disable_auth() -> None:
    """Disable authentication for all tests by default."""
    settings.auth_enabled = False


@pytest.fixture
def client() -> TestClient:
    """Fixture for the FastAPI TestClient."""
    return TestClient(app)


@pytest.fixture
def mock_db(tmp_path: Path) -> ResultStore:
    """Fixture for a temporary SQLite database for testing ResultStore."""
    db_file = tmp_path / "test_neurobench.sqlite"
    return ResultStore(db_path=str(db_file))


@pytest.fixture
def benchmark_definition_dict() -> dict[str, Any]:
    """Fixture for a sample BenchmarkDefinition as a dictionary."""
    return {
        "id": "test_bench",
        "name": "Test Benchmark",
        "description": "A test benchmark",
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
        "builtin": True,
    }


@pytest.fixture
def benchmark_result_dict() -> dict[str, Any]:
    """Fixture for a sample BenchmarkResult as a dictionary."""
    return {
        "id": "res_123",
        "benchmark_id": "test_bench",
        "network_spec_hash": "hash_123",
        "timestamp": "2024-01-01T00:00:00Z",
        "params": {"p1": 1},
        "metrics": {"accuracy": 0.9, "latency_ms": 10.0},
        "wall_time_seconds": 1.5,
        "seed": 42,
        "metric_provenance": "cpu_estimated",
    }


@pytest.fixture
def sample_benchmark_definition(benchmark_definition_dict: dict[str, Any]) -> BenchmarkDefinition:
    """Fixture for a sample BenchmarkDefinition instance."""
    return BenchmarkDefinition(**benchmark_definition_dict)


@pytest.fixture
def sample_benchmark_result(benchmark_result_dict: dict[str, Any]) -> BenchmarkResult:
    """Fixture for a sample BenchmarkResult instance."""
    return BenchmarkResult(**benchmark_result_dict)


from app.services.benchmark_loader import benchmark_loader


@pytest.fixture(autouse=True)
def inject_mock_benchmarks(benchmark_definition_dict: dict[str, Any]) -> Any:
    """Inject mock benchmarks required by tests that were deleted from builtin."""
    mock_ids = [
        "test_bench",
        "reaction_latency",
        "spike_classification",
        "mock_benchmark",
        "wake_word_detection",
        "pattern_recognition",
    ]
    added = []
    for b_id in mock_ids:
        if b_id not in benchmark_loader.benchmarks:
            d = benchmark_definition_dict.copy()
            d["id"] = b_id
            benchmark_loader.benchmarks[b_id] = BenchmarkDefinition(**d)
            added.append(b_id)
    yield
    for b_id in added:
        benchmark_loader.benchmarks.pop(b_id, None)
