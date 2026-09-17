import builtins
import importlib
import sys
from types import ModuleType
from typing import Any
from unittest.mock import patch

import pytest

from app.exceptions import OptionalDependencyError
from app.schemas.comparison import TargetMetrics
from app.schemas.results import BenchmarkResult
from app.services.target_comparator import TargetComparator


@pytest.fixture
def target_comparator() -> TargetComparator:
    return TargetComparator()


def create_mock_result(
    accuracy: float = 0.9,
    power: float = 100.0,
    latency: float = 1000.0,
    fidelity: float = 0.98,
) -> BenchmarkResult:
    return BenchmarkResult(
        id="res",
        benchmark_id="b",
        network_spec_hash="h",
        timestamp="2023-01-01T00:00:00Z",
        params={},
        metrics={
            "accuracy": accuracy,
            "estimated_power_mw": power,
            "estimated_latency_us": latency,
            "spike_fidelity": fidelity,
        },
        wall_time_seconds=1.0,
        seed=1,
    )


def test_pareto_one_dominant(target_comparator: TargetComparator) -> None:
    # loihi dominates others
    targets = [
        TargetMetrics(
            target_id="loihi2",
            target_name="Loihi 2",
            quantization_bits=8,
            accuracy=0.95,
            accuracy_loss_pct=0.0,
            estimated_power_mw=50.0,
            estimated_latency_us=500.0,
            memory_kb=128.0,
            spike_fidelity=0.99,
            warnings=[],
        ),
        TargetMetrics(
            target_id="akida",
            target_name="Akida 1.0",
            quantization_bits=4,
            accuracy=0.90,
            accuracy_loss_pct=5.0,
            estimated_power_mw=100.0,
            estimated_latency_us=1000.0,
            memory_kb=64.0,
            spike_fidelity=0.90,
            warnings=[],
        ),
        TargetMetrics(
            target_id="teensy",
            target_name="Teensy 4.1",
            quantization_bits=16,
            accuracy=0.92,
            accuracy_loss_pct=3.0,
            estimated_power_mw=150.0,
            estimated_latency_us=1500.0,
            memory_kb=512.0,
            spike_fidelity=1.00,
            warnings=[],
        ),
    ]
    pareto = target_comparator._calculate_pareto(targets)
    assert pareto == ["loihi2"]


def test_pareto_multiple_optimal(target_comparator: TargetComparator) -> None:
    # Akida: low power, low accuracy
    # Teensy: high accuracy, high power
    targets = [
        TargetMetrics(
            target_id="akida",
            target_name="Akida 1.0",
            quantization_bits=4,
            accuracy=0.80,
            accuracy_loss_pct=10.0,
            estimated_power_mw=10.0,
            estimated_latency_us=1000.0,
            memory_kb=64.0,
            spike_fidelity=0.90,
            warnings=[],
        ),
        TargetMetrics(
            target_id="teensy",
            target_name="Teensy 4.1",
            quantization_bits=16,
            accuracy=0.98,
            accuracy_loss_pct=0.0,
            estimated_power_mw=200.0,
            estimated_latency_us=1500.0,
            memory_kb=512.0,
            spike_fidelity=1.00,
            warnings=[],
        ),
    ]
    pareto = target_comparator._calculate_pareto(targets)
    assert sorted(pareto) == sorted(["akida", "teensy"])


def test_pareto_all_identical(target_comparator: TargetComparator) -> None:
    targets = [
        TargetMetrics(
            target_id="t1",
            target_name="T1",
            quantization_bits=8,
            accuracy=0.9,
            accuracy_loss_pct=0.0,
            estimated_power_mw=100.0,
            estimated_latency_us=1000.0,
            memory_kb=128.0,
            spike_fidelity=0.98,
            warnings=[],
        ),
        TargetMetrics(
            target_id="t2",
            target_name="T2",
            quantization_bits=8,
            accuracy=0.9,
            accuracy_loss_pct=0.0,
            estimated_power_mw=100.0,
            estimated_latency_us=1000.0,
            memory_kb=128.0,
            spike_fidelity=0.98,
            warnings=[],
        ),
    ]
    pareto = target_comparator._calculate_pareto(targets)
    # Identical targets do not dominate each other because dominance
    # requires being strictly better in at least one dimension.
    assert sorted(pareto) == sorted(["t1", "t2"])


def test_compare_targets_orchestration(target_comparator: TargetComparator) -> None:
    with patch("app.services.target_comparator.benchmark_runner.run_benchmark") as mock_run:
        # Mock responses for baseline, loihi2, akida, teensy, spinnaker2
        mock_run.side_effect = [
            create_mock_result(accuracy=0.95),  # baseline
            create_mock_result(accuracy=0.93, power=50.0, latency=500.0),  # loihi2
            create_mock_result(accuracy=0.90, power=20.0, latency=800.0),  # akida
            create_mock_result(accuracy=0.94, power=200.0, latency=1500.0),  # teensy
            create_mock_result(accuracy=0.95, power=100.0, latency=1000.0),  # spinnaker2
        ]

        result = target_comparator.compare_targets(cnl_spec_path="dummy.cnl")

        assert len(result.targets) == 4
        assert result.benchmark_id == "mock_benchmark"
        # Check accuracy_loss_pct for loihi2: (0.95 - 0.93) * 100 = 2.0
        loihi = next(t for t in result.targets if t.target_id == "loihi2")
        assert loihi.accuracy_loss_pct == pytest.approx(2.0)

        # Check warnings
        akida = next(t for t in result.targets if t.target_id == "akida")
        # acc_loss for akida: (0.95 - 0.90) * 100 = 5.0. No warning (should be > 5.0)
        assert akida.accuracy_loss_pct == pytest.approx(5.0)
        assert "Quantization loss > 5%" not in akida.warnings


def test_compare_targets_warnings(target_comparator: TargetComparator) -> None:
    with patch("app.services.target_comparator.benchmark_runner.run_benchmark") as mock_run:
        mock_run.side_effect = [
            create_mock_result(accuracy=1.0),  # baseline
            create_mock_result(accuracy=0.94, fidelity=0.94),  # loihi2
            create_mock_result(accuracy=0.90, fidelity=0.96),  # akida
            create_mock_result(accuracy=0.99, fidelity=0.99),  # teensy
            create_mock_result(accuracy=0.98, fidelity=0.98),  # spinnaker2
        ]

        result = target_comparator.compare_targets(cnl_spec_path="dummy.cnl")

        loihi = next(t for t in result.targets if t.target_id == "loihi2")
        # 6% loss > 5% and fidelity 0.94 < 0.95
        assert "Quantization loss > 5%" in loihi.warnings
        assert "Spike fidelity < 0.95" in loihi.warnings

        akida = next(t for t in result.targets if t.target_id == "akida")
        # 10% loss > 5%
        assert "Quantization loss > 5%" in akida.warnings
        assert "Spike fidelity < 0.95" not in akida.warnings


def test_metric_value_uses_zero_for_missing_and_none(target_comparator: TargetComparator) -> None:
    assert target_comparator._metric_value({}, "accuracy") == 0.0
    assert target_comparator._metric_value({"accuracy": None}, "accuracy") == 0.0


def test_compare_targets_uses_canonical_fallback_metrics(target_comparator: TargetComparator) -> None:
    baseline = create_mock_result(accuracy=0.95)

    canonical_target = BenchmarkResult(
        id="res2",
        benchmark_id="b",
        network_spec_hash="h",
        timestamp="2023-01-01T00:00:00Z",
        params={},
        metrics={
            "accuracy": 0.90,
            "energy_uj": 22.0,
            "latency_ms": 7.5,
            "spike_fidelity": 0.97,
        },
        wall_time_seconds=1.0,
        seed=1,
    )

    with patch("app.services.target_comparator.benchmark_runner.run_benchmark") as mock_run:
        mock_run.side_effect = [
            baseline,
            canonical_target,
            canonical_target,
            canonical_target,
            canonical_target,
        ]

        result = target_comparator.compare_targets(cnl_spec_path="dummy.cnl")

    loihi = next(t for t in result.targets if t.target_id == "loihi2")
    assert loihi.estimated_power_mw == 22.0
    assert loihi.estimated_latency_us == 7.5


def test_target_comparator_import_does_not_require_benchmark_runner() -> None:
    module_name = "app.services.target_comparator"
    old_module = sys.modules.pop(module_name, None)

    original_import = builtins.__import__

    def guarded_import(
        name: str,
        globals: dict[str, Any] | None = None,
        locals: dict[str, Any] | None = None,
        fromlist: tuple[str, ...] = (),
        level: int = 0,
    ) -> ModuleType:
        if name == "app.services.benchmark_runner":
            raise AssertionError("target_comparator imported benchmark_runner eagerly")
        return original_import(name, globals, locals, fromlist, level)

    try:
        with patch("builtins.__import__", side_effect=guarded_import):
            module = importlib.import_module(module_name)

        assert hasattr(module, "TargetComparator")
    finally:
        if old_module is not None:
            sys.modules[module_name] = old_module


def test_benchmark_runner_import_does_not_require_neurobench_executor() -> None:
    module_name = "app.services.benchmark_runner"
    old_module = sys.modules.pop(module_name, None)

    original_import = builtins.__import__

    def guarded_import(
        name: str,
        globals: dict[str, Any] | None = None,
        locals: dict[str, Any] | None = None,
        fromlist: tuple[str, ...] = (),
        level: int = 0,
    ) -> ModuleType:
        if name == "app.services.neurobench_executor":
            raise AssertionError("benchmark_runner imported neurobench_executor eagerly")
        return original_import(name, globals, locals, fromlist, level)

    try:
        with patch("builtins.__import__", side_effect=guarded_import):
            module = importlib.import_module(module_name)

        assert hasattr(module, "BenchmarkRunner")
    finally:
        if old_module is not None:
            sys.modules[module_name] = old_module


def test_benchmark_runner_reports_missing_optional_neurobench_dependencies() -> None:
    module = importlib.import_module("app.services.benchmark_runner")
    missing_dependency = ModuleNotFoundError("No module named 'neurobench'")
    missing_dependency.name = "neurobench"

    with patch("builtins.__import__", side_effect=missing_dependency):
        with pytest.raises(OptionalDependencyError, match="executor' extra") as exc_info:
            module._get_neurobench_executor()

    assert "Missing module: neurobench" in str(exc_info.value)
