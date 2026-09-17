import pytest

from app.schemas.results import BenchmarkResult, RegressionCriteria, RegressionThreshold
from app.services.diff_engine import diff_engine
from app.services.regression_service import regression_service
from app.services.result_store import result_store


@pytest.fixture
def sample_results() -> tuple[BenchmarkResult, BenchmarkResult]:
    """Fixture providing sample benchmark results."""
    res1 = BenchmarkResult(
        id="res1",
        benchmark_id="bench1",
        network_spec_hash="hash1",
        timestamp="2023-01-01T12:00:00",
        params={},
        metrics={"accuracy": 0.9, "latency": 10.0},
        wall_time_seconds=1.0,
        seed=1,
    )
    res2 = BenchmarkResult(
        id="res2",
        benchmark_id="bench1",
        network_spec_hash="hash1",
        timestamp="2023-01-02T12:00:00",
        params={},
        metrics={"accuracy": 0.85, "latency": 12.0},
        wall_time_seconds=1.0,
        seed=1,
    )
    return res1, res2


def test_diff_engine_with_criteria(
    sample_results: tuple[BenchmarkResult, BenchmarkResult],
) -> None:
    """Test DiffEngine with RegressionCriteria overrides."""
    res1, res2 = sample_results

    # Default: accuracy higher is better, latency lower is better (inferred)
    # res2 accuracy 0.9 -> 0.85 (regressed if >1% tolerance)
    # res2 latency 10.0 -> 12.0 (regressed if >1% tolerance)

    criteria = RegressionCriteria(
        default_threshold=RegressionThreshold(
            tolerance=10.0, comparison_direction="higher_is_better"
        ),
        overrides={
            "latency": RegressionThreshold(tolerance=30.0, comparison_direction="lower_is_better")
        },
    )

    diff = diff_engine.compute_diff(res1, res2, criteria=criteria)

    # Accuracy: (0.85-0.9)/0.9 = -5.55% -> > 10% tolerance? No, it's -5.55%, tolerance is 10%.
    # Wait, -5.55% is within 10% tolerance.
    # Latency: (12-10)/10 = +20% -> within 30% tolerance.

    assert diff.has_regression is False

    # Now lower tolerance
    criteria.default_threshold.tolerance = 1.0
    diff = diff_engine.compute_diff(res1, res2, criteria=criteria)
    assert diff.has_regression is True
    assert diff.metrics[0].name == "accuracy"
    assert diff.metrics[0].status == "regressed"


def test_regression_service_trends(
    sample_results: tuple[BenchmarkResult, BenchmarkResult],
) -> None:
    """Test RegressionService trend calculation."""
    res1, res2 = sample_results

    # Mock result_store to return our samples
    import unittest.mock as mock

    with mock.patch.object(result_store, "get_all_results", return_value=[res1, res2]):
        trends = regression_service.get_trends("bench1")

        assert trends.benchmark_id == "bench1"
        assert len(trends.history) == 2
        assert "accuracy" in trends.metric_names
        assert "latency" in trends.metric_names
        assert trends.history[0].result_id == "res1"
        assert trends.history[1].result_id == "res2"
