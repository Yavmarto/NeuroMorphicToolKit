from collections.abc import Iterator
from unittest.mock import MagicMock, patch

import pytest

from app.schemas.comparison import EncodingComparisonResult, TargetComparisonResult
from app.schemas.reports import ReportGenerationResult
from app.schemas.results import BenchmarkResult
from app.schemas.robustness import PerturbationCurve, RobustnessCurve
from app.services.encoding_comparator import encoding_comparator
from app.services.fault_sweeper import fault_sweeper
from app.services.perturbation_sweeper import perturbation_sweeper
from app.services.report_generator import report_generator
from app.services.target_comparator import target_comparator


@pytest.mark.contract_only
def test_report_generator_pdf() -> None:
    with (
        patch("app.services.report_generator.WEASYPRINT_AVAILABLE", True),
        patch("app.services.report_generator.HTML", create=True),
    ):
        result = report_generator.generate_report(format="pdf")
        assert isinstance(result, ReportGenerationResult)
        assert result.format == "pdf"
        assert result.status == "completed"


@pytest.mark.contract_only
def test_report_generator_html() -> None:
    """Test HTML report generation."""
    result = report_generator.generate_report(format="html")
    assert result.format == "html"
    if result.download_url:
        assert result.download_url.endswith(".html")


@pytest.mark.contract_only
def test_report_generator_json() -> None:
    """Test JSON report generation."""
    result = report_generator.generate_report(format="json")
    assert result.format == "json"
    if result.download_url:
        assert result.download_url.endswith(".json")


@pytest.mark.contract_only
def test_fault_sweeper_default(sample_benchmark_result: BenchmarkResult) -> None:
    """Test default fault sweep."""
    with patch("app.services.fault_sweeper.benchmark_runner.run_benchmark") as mock_run:
        mock_run.return_value = sample_benchmark_result.model_copy(
            update={"metrics": {"accuracy": 0.95}}
        )
        result = fault_sweeper.sweep_faults(cnl_spec_path="dummy.cnl", benchmark_id="test_bench")
        assert isinstance(result, RobustnessCurve)
        assert result.fault_type == "dead_neuron"
        assert len(result.fault_rates) == len(result.accuracies_mean)


@pytest.mark.contract_only
def test_fault_sweeper_custom_type(sample_benchmark_result: BenchmarkResult) -> None:
    """Test fault sweep with custom fault type."""
    with patch("app.services.fault_sweeper.benchmark_runner.run_benchmark") as mock_run:
        mock_run.return_value = sample_benchmark_result.model_copy(
            update={"metrics": {"accuracy": 0.95}}
        )
        result = fault_sweeper.sweep_faults(
            cnl_spec_path="dummy.cnl", benchmark_id="test_bench", fault_type="stuck_at"
        )
        assert result.fault_type == "stuck_at"


@pytest.mark.contract_only
def test_fault_sweeper_threshold(sample_benchmark_result: BenchmarkResult) -> None:
    """Test fault sweep threshold."""
    with patch("app.services.fault_sweeper.benchmark_runner.run_benchmark") as mock_run:
        mock_run.side_effect = [
            sample_benchmark_result.model_copy(
                update={
                    "id": f"res_{i}",
                    "metrics": {"accuracy": 0.95 - (i // 5) * 0.1},
                    "seed": i % 5,
                }
            )
            for i in range(30)  # 6 rates * 5 seeds
        ]
        result = fault_sweeper.sweep_faults(cnl_spec_path="dummy.cnl", benchmark_id="test_bench")
        assert result.threshold_90pct is not None
        assert result.n_seeds >= 5


@pytest.mark.contract_only
def test_perturbation_sweeper_default() -> None:
    result = perturbation_sweeper.sweep_perturbation(
        cnl_spec_path=__import__("os").path.join(
            __import__("os").path.dirname(__file__), "test_network.cnl"
        ),
        benchmark_id="spike_classification",
        dataset_path="tests/test_data.npy",
    )
    assert isinstance(result, PerturbationCurve)
    assert result.noise_type == "gaussian"


@pytest.mark.contract_only
def test_perturbation_sweeper_salt_pepper() -> None:
    result = perturbation_sweeper.sweep_perturbation(
        cnl_spec_path=__import__("os").path.join(
            __import__("os").path.dirname(__file__), "test_network.cnl"
        ),
        benchmark_id="spike_classification",
        dataset_path="tests/test_data.npy",
        noise_type="salt_and_pepper",
    )
    assert result.noise_type == "salt_and_pepper"


@pytest.mark.contract_only
def test_perturbation_sweeper_data_integrity() -> None:
    result = perturbation_sweeper.sweep_perturbation(
        cnl_spec_path=__import__("os").path.join(
            __import__("os").path.dirname(__file__), "test_network.cnl"
        ),
        benchmark_id="spike_classification",
        dataset_path="tests/test_data.npy",
    )
    assert len(result.noise_levels) == len(result.accuracies)
    assert all(0.0 <= acc <= 1.0 for acc in result.accuracies)


@pytest.mark.contract_only
def test_encoding_comparator_default() -> None:
    with patch("app.services.encoding_comparator.run_pipeline") as mock_sim:
        mock_sim.return_value = {"accuracy": 0.9, "spike_rate_hz": 100.0}
        result = encoding_comparator.compare_encoding()
        assert isinstance(result, EncodingComparisonResult)
        assert len(result.metrics) >= 4
        assert any(m.method == "burst" for m in result.metrics)


@pytest.mark.contract_only
def test_encoding_comparator_recommendation() -> None:
    with patch("app.services.encoding_comparator.run_pipeline") as mock_sim:
        mock_sim.return_value = {"accuracy": 0.9, "spike_rate_hz": 100.0}
        result = encoding_comparator.compare_encoding()
        assert isinstance(result.recommendation, str)
        assert len(result.recommendation) > 0


@pytest.mark.contract_only
def test_encoding_comparator_metrics() -> None:
    with patch("app.services.encoding_comparator.run_pipeline") as mock_sim:
        mock_sim.return_value = {"accuracy": 0.9, "spike_rate_hz": 100.0}
        result = encoding_comparator.compare_encoding()
        for m in result.metrics:
            assert m.accuracy >= 0
            assert m.spike_rate_hz > 0


@pytest.fixture
def mock_target_runner(sample_benchmark_result: BenchmarkResult) -> Iterator[MagicMock]:
    """Mock the benchmark runner for target comparison tests."""
    with patch("app.services.target_comparator.benchmark_runner.run_benchmark") as mock_run:
        mock_run.return_value = sample_benchmark_result.model_copy(
            update={
                "metrics": {
                    "accuracy": 0.9,
                    "estimated_latency_us": 100.0,
                    "estimated_power_mw": 0.5,
                    "spike_fidelity": 0.98,
                }
            }
        )
        yield mock_run


@pytest.mark.contract_only
def test_target_comparator_default(mock_target_runner: MagicMock) -> None:
    result = target_comparator.compare_targets(cnl_spec_path="dummy.cnl")
    assert isinstance(result, TargetComparisonResult)
    assert len(result.targets) == 4


@pytest.mark.contract_only
def test_target_comparator_loihi(mock_target_runner: MagicMock) -> None:
    result = target_comparator.compare_targets(cnl_spec_path="dummy.cnl")
    loihi = next(t for t in result.targets if t.target_id == "loihi2")
    assert loihi.accuracy > 0
    assert loihi.quantization_bits == 8


@pytest.mark.contract_only
def test_target_comparator_pareto(mock_target_runner: MagicMock) -> None:
    result = target_comparator.compare_targets(cnl_spec_path="dummy.cnl")
    # All targets have identical metrics in our mock, so all are Pareto-optimal.
    assert "loihi2" in result.pareto_optimal
