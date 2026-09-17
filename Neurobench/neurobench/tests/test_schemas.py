from typing import Any, cast

import pytest
from pydantic import ValidationError

from app.schemas.benchmarks import BenchmarkDefinition
from app.schemas.results import BenchmarkResult
from app.schemas.robustness import RobustnessCurve


def test_benchmark_definition_validation(benchmark_definition_dict: dict[str, Any]) -> None:
    """Tests validation for the BenchmarkDefinition schema."""
    valid_data = benchmark_definition_dict
    bench = BenchmarkDefinition(**valid_data)
    assert bench.id == "test_bench"

    # Missing required field
    invalid_data = valid_data.copy()
    del invalid_data["id"]
    with pytest.raises(ValidationError):
        BenchmarkDefinition(**invalid_data)

    # Invalid type
    invalid_data = valid_data.copy()
    # Explicitly cast to dict to avoid mypy issues after modification
    input_spec = cast(dict[str, Any], invalid_data["input_spec"]).copy()
    input_spec["type"] = "invalid_type"
    invalid_data["input_spec"] = input_spec
    with pytest.raises(ValidationError):
        BenchmarkDefinition(**invalid_data)


def test_benchmark_result_validation(benchmark_result_dict: dict[str, Any]) -> None:
    """Tests validation for the BenchmarkResult schema."""
    valid_data = benchmark_result_dict
    res = BenchmarkResult(**valid_data)
    assert res.id == "res_123"

    invalid_data = valid_data.copy()
    invalid_data["metrics"] = {"m1": "not_a_float"}
    with pytest.raises(ValidationError):
        BenchmarkResult(**invalid_data)


def test_robustness_curve_validation() -> None:
    """Tests validation for the RobustnessCurve schema."""
    valid_data: dict[str, Any] = {
        "fault_type": "stuck_at_0",
        "fault_rates": [0.0, 0.1],
        "accuracies_mean": [0.9, 0.8],
        "accuracies_ci_lower": [0.85, 0.75],
        "accuracies_ci_upper": [0.95, 0.85],
        "n_seeds": 5,
    }
    curve = RobustnessCurve(**valid_data)
    assert curve.fault_type == "stuck_at_0"
