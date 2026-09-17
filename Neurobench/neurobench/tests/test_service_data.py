import json
from pathlib import Path
from typing import Any

from app.schemas.results import BenchmarkResult
from app.services.benchmark_loader import BenchmarkLoader
from app.services.result_store import ResultStore


def test_benchmark_loader_builtin(
    tmp_path: Path, benchmark_definition_dict: dict[str, Any]
) -> None:
    """Tests loading built-in benchmarks from JSON files."""
    # Create a temporary builtin directory
    builtin_dir = tmp_path / "builtin"
    builtin_dir.mkdir()

    benchmark_data = benchmark_definition_dict

    with open(builtin_dir / "test_bench.json", "w") as f:
        json.dump(benchmark_data, f)

    loader = BenchmarkLoader(builtin_dir=str(builtin_dir))

    benchmarks = loader.get_all()
    assert len(benchmarks) == 1
    assert benchmarks[0].id == "test_bench"

    bench = loader.get("test_bench")
    assert bench is not None
    assert bench.name == "Test Benchmark"

    assert loader.get("non_existent") is None


def test_result_store_operations(
    mock_db: ResultStore, sample_benchmark_result: BenchmarkResult
) -> None:
    """Tests result store operations (save/get results and baselines)."""
    result_data = sample_benchmark_result

    # Test save and get result
    mock_db.save_result(result_data)
    retrieved = mock_db.get_result(result_data.id)
    assert retrieved is not None
    assert retrieved.id == result_data.id
    assert retrieved.metrics["accuracy"] == 0.9

    # Test get all results
    all_results = mock_db.get_all_results()
    assert len(all_results) == 1
    assert all_results[0].id == result_data.id

    # Test save and get baseline
    mock_db.save_baseline(result_data)
    all_baselines = mock_db.get_all_baselines()
    assert len(all_baselines) == 1
    assert all_baselines[0].id == result_data.id

    assert mock_db.get_result("non_existent") is None
