from pathlib import Path
from typing import Any

import pytest
from pydantic import ValidationError

from contracts import BenchmarkSuite, RegressionThreshold, RobustnessCurve, ScoringConfig
from contracts.benchmark_contracts import (
    BenchmarkResult,
    MetricProvenance,
    _provenance_from_target_id,
)
from contracts.regression_contracts import RunResult


def test_benchmark_suite_validation(tmp_path: Path) -> None:
    """Tests validation for the BenchmarkSuite contract."""
    # Create a dummy dataset file
    dataset_file = tmp_path / "dataset.txt"
    dataset_file.touch()

    # Valid data
    valid_data: dict[str, Any] = {
        "task_name": "Grip Stability",
        "dataset_path": str(dataset_file),
        "metric": "accuracy",
    }
    suite = BenchmarkSuite(**valid_data)
    assert suite.task_name == "Grip Stability"

    # Invalid: empty task_name
    invalid_task = valid_data.copy()
    invalid_task["task_name"] = ""
    with pytest.raises(ValidationError):
        BenchmarkSuite(**invalid_task)

    # Invalid: non-existent dataset_path
    invalid_path = valid_data.copy()
    invalid_path["dataset_path"] = str(tmp_path / "non_existent.txt")
    with pytest.raises(ValidationError):
        BenchmarkSuite(**invalid_path)

    # Invalid: metric not in allowed set
    invalid_metric = valid_data.copy()
    invalid_metric["metric"] = "invalid_metric"
    with pytest.raises(ValidationError):
        BenchmarkSuite(**invalid_metric)


def test_scoring_config_validation() -> None:
    """Tests validation for the ScoringConfig contract."""
    # Valid data
    valid_data: dict[str, Any] = {
        "primary_metric": "accuracy",
        "secondary_metrics": ["latency_ms", "power_mw"],
        "higher_is_better": True,
        "pass_threshold": 0.8,
    }
    config = ScoringConfig(**valid_data)
    assert config.primary_metric == "accuracy"
    assert config.secondary_metrics == ["latency_ms", "power_mw"]

    # Invalid primary metric
    invalid_primary = valid_data.copy()
    invalid_primary["primary_metric"] = "throughput_fps"
    with pytest.raises(ValidationError):
        ScoringConfig(**invalid_primary)

    # Invalid secondary metric
    invalid_secondary = valid_data.copy()
    invalid_secondary["secondary_metrics"] = ["latency_ms", "unknown_metric"]
    with pytest.raises(ValidationError):
        ScoringConfig(**invalid_secondary)

    # All supported metrics are valid
    for metric in [
        "accuracy",
        "latency_ms",
        "power_mw",
        "memory_kb",
        "spike_fidelity",
        "stopping_distance",
    ]:
        valid_config = valid_data.copy()
        valid_config["primary_metric"] = metric
        valid_config["secondary_metrics"] = []
        ScoringConfig(**valid_config)


def test_run_result_validation() -> None:
    """Tests validation for the RunResult contract."""
    # Valid data
    valid_data: dict[str, Any] = {
        "score": 0.95,
        "timestamp": "2026-03-15T12:00:00Z",
        "hardware_tag": "Loihi2",
    }
    result = RunResult(**valid_data)
    assert result.score == 0.95

    # Invalid: negative score
    invalid_score = valid_data.copy()
    invalid_score["score"] = -0.1
    with pytest.raises(ValidationError):
        RunResult(**invalid_score)

    # Invalid: non-ISO-8601 timestamp
    invalid_timestamp = valid_data.copy()
    invalid_timestamp["timestamp"] = "2026-03-15 12:00:00"
    with pytest.raises(ValidationError):
        RunResult(**invalid_timestamp)

    # Invalid: empty hardware_tag
    invalid_hardware = valid_data.copy()
    invalid_hardware["hardware_tag"] = ""
    with pytest.raises(ValidationError):
        RunResult(**invalid_hardware)


def test_regression_threshold_validation() -> None:
    """Tests validation for the RegressionThreshold contract."""
    # Valid data
    valid_data: dict[str, Any] = {"tolerance": 0.01, "comparison_direction": "higher_is_better"}
    threshold = RegressionThreshold(**valid_data)
    assert threshold.tolerance == 0.01

    # Invalid: tolerance < 0  # noqa: ERA001 (intentional test case description)
    invalid_tolerance = valid_data.copy()
    invalid_tolerance["tolerance"] = -0.01
    with pytest.raises(ValidationError):
        RegressionThreshold(**invalid_tolerance)

    # Invalid: invalid comparison_direction
    invalid_direction = valid_data.copy()
    invalid_direction["comparison_direction"] = "better"
    with pytest.raises(ValidationError):
        RegressionThreshold(**invalid_direction)


def test_robustness_curve_validation() -> None:
    """Tests validation for the RobustnessCurve contract."""
    # Valid data
    valid_data: dict[str, Any] = {
        "fault_type": "dead_neuron",
        "fault_rates": [0.0, 0.1, 0.2],
        "accuracies_mean": [0.95, 0.90, 0.85],
        "accuracies_ci_lower": [0.94, 0.89, 0.84],
        "accuracies_ci_upper": [0.96, 0.91, 0.86],
        "n_seeds": 5,
    }
    curve = RobustnessCurve(**valid_data)
    assert curve.n_seeds == 5

    # Invalid: n_seeds < 5  # noqa: ERA001 (intentional test case description)
    invalid_seeds = valid_data.copy()
    invalid_seeds["n_seeds"] = 4
    with pytest.raises(ValidationError):
        RobustnessCurve(**invalid_seeds)

    # Invalid: mismatched list lengths
    invalid_lengths = valid_data.copy()
    invalid_lengths["fault_rates"] = [0.0, 0.1]  # Should be 3
    with pytest.raises(ValidationError):
        RobustnessCurve(**invalid_lengths)


def test_benchmark_result_requires_metric_provenance() -> None:
    """BenchmarkResult must include metric_provenance."""
    result = BenchmarkResult(
        id="res_001",
        benchmark_id="bench_001",
        network_spec_hash="abc123",
        timestamp="2026-01-01T00:00:00Z",
        params={"p": 1},
        metrics={"accuracy": 0.9},
        wall_time_seconds=1.0,
        seed=42,
        metric_provenance=MetricProvenance.CPU_ESTIMATED,
    )
    assert result.metric_provenance == MetricProvenance.CPU_ESTIMATED


def test_provenance_from_target_id_classifies_correctly() -> None:
    """_provenance_from_target_id maps hardware targets to on_device, others to cpu_estimated."""
    assert _provenance_from_target_id(None) == MetricProvenance.CPU_ESTIMATED
    assert _provenance_from_target_id("neurobench") == MetricProvenance.CPU_ESTIMATED
    assert _provenance_from_target_id("neurosense_recording") == MetricProvenance.CPU_ESTIMATED
    # akida runs in simulator_only mode (localModeFallback per modules.json) — NOT on_device
    assert _provenance_from_target_id("akida") == MetricProvenance.CPU_ESTIMATED
    # Physical neuromorphic hardware
    assert _provenance_from_target_id("spinnaker2") == MetricProvenance.ON_DEVICE
    assert _provenance_from_target_id("synsense") == MetricProvenance.ON_DEVICE
    assert _provenance_from_target_id("pynq") == MetricProvenance.ON_DEVICE


def test_provenance_helper_covers_all_runner_target_ids() -> None:
    """Every target_id used across benchmark_runner.py and hardware runners maps correctly."""
    for cpu_target in [
        None,
        "neurobench",
        "neurosense_recording",
        "neurosim",
        "neurochip",
        "akida",
    ]:
        assert _provenance_from_target_id(cpu_target) == MetricProvenance.CPU_ESTIMATED, (
            f"Expected CPU_ESTIMATED for target_id={cpu_target!r}"
        )
    for hw_target in ["spinnaker2", "synsense", "pynq"]:
        assert _provenance_from_target_id(hw_target) == MetricProvenance.ON_DEVICE, (
            f"Expected ON_DEVICE for target_id={hw_target!r}"
        )
