from collections.abc import Callable
from unittest.mock import patch

import pytest

from app.schemas.results import BenchmarkResult
from app.services.fault_sweeper import fault_sweeper


@pytest.fixture
def mock_benchmark_result() -> Callable[..., BenchmarkResult]:
    def _create_result(accuracy: float = 0.85, seed: int = 42) -> BenchmarkResult:
        return BenchmarkResult(
            id="res_test",
            benchmark_id="test_bench",
            network_spec_hash="hash_test",
            timestamp="2024-01-01T00:00:00Z",
            params={},
            metrics={"accuracy": accuracy},
            wall_time_seconds=1.0,
            seed=seed,
        )

    return _create_result


def test_sweep_faults_logic(
    mock_benchmark_result: Callable[..., BenchmarkResult],
) -> None:
    fault_rates = [0.0, 0.1, 0.2]
    n_seeds = 5

    # Mocking run_benchmark to return decreasing accuracy
    # For rate 0.0: 0.95
    # For rate 0.1: 0.91
    # For rate 0.2: 0.85
    accuracies = [0.95] * n_seeds + [0.91] * n_seeds + [0.85] * n_seeds

    with patch("app.services.fault_sweeper.benchmark_runner.run_benchmark") as mock_run:
        mock_run.side_effect = [mock_benchmark_result(acc) for acc in accuracies]

        result = fault_sweeper.sweep_faults(
            cnl_spec_path="test.cnl",
            benchmark_id="test_bench",
            fault_type="dead_neuron",
            fault_rates=fault_rates,
        )

        assert result.fault_type == "dead_neuron"
        assert result.fault_rates == fault_rates
        assert len(result.accuracies_mean) == 3
        assert result.accuracies_mean[0] == pytest.approx(0.95)
        assert result.accuracies_mean[1] == pytest.approx(0.91)
        assert result.accuracies_mean[2] == pytest.approx(0.85)

        # 90% threshold should be between 0.1 and 0.2
        # y1=0.91, y2=0.85, x1=0.1, x2=0.2, target=0.9
        # x = 0.1 + (0.9 - 0.91) * (0.2 - 0.1) / (0.85 - 0.91)  # noqa: ERA001
        # x = 0.1 + (-0.01) * (0.1) / (-0.06) = 0.11666...  # noqa: ERA001
        assert result.threshold_90pct == pytest.approx(0.116666, abs=1e-5)

        assert mock_run.call_count == len(fault_rates) * n_seeds


def test_sweep_faults_ci_math() -> None:
    # Constant accuracy should result in 0 confidence interval
    with patch("app.services.fault_sweeper.benchmark_runner.run_benchmark") as mock_run:
        mock_run.return_value = BenchmarkResult(
            id="res",
            benchmark_id="b",
            network_spec_hash="h",
            timestamp="t",
            params={},
            metrics={"accuracy": 0.8},
            wall_time_seconds=1.0,
            seed=1,
        )

        result = fault_sweeper.sweep_faults(
            cnl_spec_path="test.cnl", benchmark_id="test_bench", fault_rates=[0.0]
        )

        assert result.accuracies_mean[0] == 0.8
        assert result.accuracies_ci_lower[0] == 0.8
        assert result.accuracies_ci_upper[0] == 0.8


def test_interpolate_threshold_never_drops() -> None:
    sweeper = fault_sweeper
    x = [0.0, 0.1, 0.2]
    y = [0.95, 0.94, 0.92]
    threshold = sweeper._interpolate_threshold(x, y, 0.90)
    assert threshold is None


def test_interpolate_threshold_drops_immediately() -> None:
    sweeper = fault_sweeper
    x = [0.0, 0.1, 0.2]
    y = [0.85, 0.80, 0.75]
    threshold = sweeper._interpolate_threshold(x, y, 0.90)
    assert threshold == 0.0


def test_robustness_curve_invariants() -> None:
    # Test that the Pydantic model validator works
    from app.schemas.robustness import RobustnessCurve

    with pytest.raises(ValueError, match="must have the same length"):
        RobustnessCurve(
            fault_type="test",
            fault_rates=[0.0, 0.1],
            accuracies_mean=[0.9],
            accuracies_ci_lower=[0.8],
            accuracies_ci_upper=[1.0],
            n_seeds=5,
        )
