from app.schemas.results import BenchmarkResult, RegressionCriteria, RegressionThreshold
from app.services.diff_engine import DiffEngine


def test_regression(sample_benchmark_result: BenchmarkResult) -> None:
    """Tests that a standard regression is correctly flagged."""
    engine = DiffEngine()

    # Given baseline accuracy = 0.90, new accuracy = 0.88, and tolerance = 0.015,
    # the engine correctly marks the result as a regression
    baseline = sample_benchmark_result.model_copy(update={"metrics": {"accuracy": 0.90}})
    current = sample_benchmark_result.model_copy(update={"metrics": {"accuracy": 0.88}})
    criteria = RegressionCriteria(
        default_threshold=RegressionThreshold(
            tolerance=0.015, comparison_direction="higher_is_better"
        )
    )

    diff = engine.compute_diff(baseline, current, criteria=criteria)
    assert diff.metrics[0].status == "regressed"


def test_floating_point_denormals(sample_benchmark_result: BenchmarkResult) -> None:
    """Tests that floating-point denormals do not falsely trigger a regression flag."""
    engine = DiffEngine()

    # Given baseline latency_ms = 10.000000, new latency_ms = 10.000001, and tolerance = 0.001,
    # the engine does not flag a regression
    baseline = sample_benchmark_result.model_copy(update={"metrics": {"latency_ms": 10.000000}})
    current = sample_benchmark_result.model_copy(update={"metrics": {"latency_ms": 10.000001}})
    criteria = RegressionCriteria(
        default_threshold=RegressionThreshold(
            tolerance=0.001, comparison_direction="lower_is_better"
        )
    )
    diff = engine.compute_diff(baseline, current, criteria=criteria)
    assert diff.metrics[0].status == "unchanged"


def test_zero_tolerance(sample_benchmark_result: BenchmarkResult) -> None:
    """Tests that zero-tolerance strict mode flags any non-zero delta."""
    engine = DiffEngine()

    # Given tolerance = 0.0 and any non-zero delta, the engine flags a regression.
    baseline = sample_benchmark_result.model_copy(update={"metrics": {"latency_ms": 10.000000}})
    current = sample_benchmark_result.model_copy(update={"metrics": {"latency_ms": 10.000001}})
    criteria = RegressionCriteria(
        default_threshold=RegressionThreshold(tolerance=0.0, comparison_direction="lower_is_better")
    )
    diff = engine.compute_diff(baseline, current, criteria=criteria)
    assert diff.metrics[0].status == "regressed"

    # Also test an improvement, which should also be flagged as a regression under zero-tolerance
    baseline_improved = sample_benchmark_result.model_copy(
        update={"metrics": {"latency_ms": 10.000000}}
    )
    current_improved = sample_benchmark_result.model_copy(
        update={"metrics": {"latency_ms": 9.999999}}
    )
    diff_improved = engine.compute_diff(baseline_improved, current_improved, criteria=criteria)
    assert diff_improved.metrics[0].status == "regressed"


def test_exact_tolerance_boundary(sample_benchmark_result: BenchmarkResult) -> None:
    """Tests the boundary condition where delta matches tolerance exactly."""
    engine = DiffEngine()

    baseline = sample_benchmark_result.model_copy(update={"metrics": {"latency_ms": 100.0}})
    current = sample_benchmark_result.model_copy(update={"metrics": {"latency_ms": 101.0}})
    criteria = RegressionCriteria(
        default_threshold=RegressionThreshold(tolerance=1.0, comparison_direction="lower_is_better")
    )
    diff = engine.compute_diff(baseline, current, criteria=criteria)
    assert diff.metrics[0].status == "unchanged"
