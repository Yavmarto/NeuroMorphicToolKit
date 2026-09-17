from unittest.mock import patch

from app.schemas.comparison import EncodingComparisonResult
from app.schemas.reports import ReportGenerationResult
from app.schemas.results import BenchmarkResult
from app.schemas.robustness import PerturbationCurve
from app.services.diff_engine import DiffEngine
from app.services.encoding_comparator import encoding_comparator
from app.services.fault_sweeper import fault_sweeper
from app.services.perturbation_sweeper import perturbation_sweeper
from app.services.report_generator import report_generator
from app.services.target_comparator import target_comparator


def test_diff_engine_improved(sample_benchmark_result: BenchmarkResult) -> None:
    """Tests that DiffEngine correctly identifies improved metrics."""
    engine = DiffEngine()
    baseline = sample_benchmark_result.model_copy(update={"metrics": {"accuracy": 0.8}})
    current = sample_benchmark_result.model_copy(update={"metrics": {"accuracy": 0.85}})
    diff = engine.compute_diff(baseline, current)
    assert diff.metrics[0].status == "improved"
    assert diff.metrics[0].delta_pct > 0
    assert not diff.metrics[0].threshold_violated


def test_diff_engine_regressed(sample_benchmark_result: BenchmarkResult) -> None:
    """Tests that DiffEngine correctly identifies regressed metrics."""
    engine = DiffEngine()
    baseline = sample_benchmark_result.model_copy(update={"metrics": {"accuracy": 0.8}})
    current = sample_benchmark_result.model_copy(update={"metrics": {"accuracy": 0.7}})
    diff = engine.compute_diff(baseline, current)
    assert diff.metrics[0].status == "regressed"
    assert diff.metrics[0].threshold_violated


def test_diff_engine_unchanged(sample_benchmark_result: BenchmarkResult) -> None:
    """Tests that DiffEngine correctly identifies unchanged metrics within tolerance."""
    engine = DiffEngine()
    baseline = sample_benchmark_result.model_copy(update={"metrics": {"accuracy": 0.8}})
    current = sample_benchmark_result.model_copy(update={"metrics": {"accuracy": 0.805}})
    diff = engine.compute_diff(baseline, current)
    assert diff.metrics[0].status == "unchanged"


def test_mock_services(sample_benchmark_result: BenchmarkResult) -> None:
    """Verifies return structures of current mock service implementations."""
    # benchmark_runner.run_benchmark is no longer mocked to return job_id directly
    # but the router handles the mock for backward compatibility if needed.
    # Service itself now requires arguments for real execution.
    with patch("app.services.encoding_comparator.run_pipeline") as mock_sim:
        mock_sim.return_value = {"accuracy": 0.9, "spike_rate_hz": 100.0}
        assert isinstance(encoding_comparator.compare_encoding(), EncodingComparisonResult)

    with patch("app.services.fault_sweeper.benchmark_runner.run_benchmark") as mock_run_fault:
        mock_run_fault.return_value = sample_benchmark_result.model_copy(
            update={"metrics": {"accuracy": 0.95}}
        )
        assert hasattr(
            fault_sweeper.sweep_faults(cnl_spec_path="dummy.cnl", benchmark_id="test_bench"),
            "fault_type",
        )

    with (
        patch("app.services.perturbation_sweeper.benchmark_runner.run_benchmark") as mock_run_pert,
        patch(
            "app.services.perturbation_sweeper.PerturbationSweeper._load_and_perturb_dataset"
        ) as mock_load,
    ):
        mock_run_pert.return_value = sample_benchmark_result.model_copy(
            update={"metrics": {"accuracy": 0.95}}
        )
        mock_load.return_value = "mock_perturbed.npy"
        assert isinstance(
            perturbation_sweeper.sweep_perturbation(
                cnl_spec_path="dummy.cnl", benchmark_id="test_bench", dataset_path="dummy.npy"
            ),
            PerturbationCurve,
        )

    assert isinstance(report_generator.generate_report(), ReportGenerationResult)

    with patch("app.services.target_comparator.benchmark_runner.run_benchmark") as mock_run:
        mock_run.return_value = sample_benchmark_result.model_copy(
            update={"metrics": {"accuracy": 0.9, "latency_ms": 10.0}}
        )
        assert hasattr(target_comparator.compare_targets(cnl_spec_path="dummy.cnl"), "targets")
