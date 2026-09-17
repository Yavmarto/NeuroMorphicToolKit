from hypothesis import given, settings

from app.schemas.results import BenchmarkResult, RegressionCriteria, RegressionThreshold
from app.services.diff_engine import DiffEngine
from tests.properties.strategies import benchmark_result_strategy, regression_threshold_strategy


@given(
    baseline=benchmark_result_strategy(),
    threshold=regression_threshold_strategy(),
)
@settings(max_examples=100)
def test_regression_detection_flagged_dynamic(
    baseline: BenchmarkResult, threshold: RegressionThreshold
) -> None:
    """Property: Degradation beyond dynamic threshold is always flagged as regressed."""
    # Filter out empty metrics and 0.0 values that cause issues with percentage
    metrics = {k: v for k, v in baseline.metrics.items() if v != 0}
    if not metrics:
        return

    baseline = baseline.model_copy(update={"metrics": metrics})

    engine = DiffEngine()

    # Create current result by degrading metrics beyond the threshold tolerance
    degradation_factor = threshold.tolerance + 1.0  # At least 1% beyond tolerance
    current_metrics = {}
    is_higher_better = threshold.comparison_direction == "higher_is_better"

    for name, value in baseline.metrics.items():
        if value is None:
            continue
        if is_higher_better:
            # Lower the score to regress
            current_metrics[name] = value * (1 - degradation_factor / 100)
        else:
            # Raise the score to regress (e.g. latency, power)
            current_metrics[name] = value * (1 + degradation_factor / 100)

    current = baseline.model_copy(update={"metrics": current_metrics, "id": "current_id"})

    criteria = RegressionCriteria(default_threshold=threshold)
    diff = engine.compute_diff(baseline, current, criteria=criteria)

    for metric_diff in diff.metrics:
        # All metrics should be regressed as we degraded them beyond the tolerance
        msg = (
            f"Metric {metric_diff.name} with delta_pct {metric_diff.delta_pct} "
            f"and tolerance {threshold.tolerance} "
            f"was not flagged as regressed for direction {threshold.comparison_direction}"
        )
        assert metric_diff.status == "regressed", msg
        assert metric_diff.threshold_violated is True


@given(baseline=benchmark_result_strategy())
@settings(max_examples=100)
def test_identical_results_never_regress(baseline: BenchmarkResult) -> None:
    """Property: Comparing a result with itself always yields "unchanged" status for all metrics."""
    engine = DiffEngine()
    # Ensure current is identical to baseline but has a different ID
    current = baseline.model_copy(update={"id": "current_id"})

    diff = engine.compute_diff(baseline, current)

    for metric_diff in diff.metrics:
        assert metric_diff.status == "unchanged"
        assert metric_diff.delta == 0.0
        assert metric_diff.delta_pct == 0.0
        assert metric_diff.threshold_violated is False


@given(
    baseline=benchmark_result_strategy(),
    threshold=regression_threshold_strategy(),
)
@settings(max_examples=100)
def test_improvement_detection_flagged_dynamic(
    baseline: BenchmarkResult, threshold: RegressionThreshold
) -> None:
    """Property: Improvement beyond dynamic threshold is always flagged as improved."""
    metrics = {k: v for k, v in baseline.metrics.items() if v != 0}
    if not metrics:
        return

    baseline = baseline.model_copy(update={"metrics": metrics})
    engine = DiffEngine()

    # Create current result by improving metrics beyond the threshold tolerance
    improvement_factor = threshold.tolerance + 1.0
    current_metrics = {}
    is_higher_better = threshold.comparison_direction == "higher_is_better"

    for name, value in baseline.metrics.items():
        if value is None:
            continue
        if is_higher_better:
            # Raise the score to improve
            current_metrics[name] = value * (1 + improvement_factor / 100)
        else:
            # Lower the score to improve
            current_metrics[name] = value * (1 - improvement_factor / 100)

    current = baseline.model_copy(update={"metrics": current_metrics, "id": "current_id"})

    criteria = RegressionCriteria(default_threshold=threshold)
    diff = engine.compute_diff(baseline, current, criteria=criteria)

    for metric_diff in diff.metrics:
        if threshold.tolerance == 0.0:
            # In strict mode, everything non-zero is a regression
            assert metric_diff.status == "regressed"
            assert metric_diff.threshold_violated is True
        else:
            assert metric_diff.status == "improved"
            assert metric_diff.threshold_violated is False
