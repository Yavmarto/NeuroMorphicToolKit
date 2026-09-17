from unittest.mock import patch

import pytest

from app.schemas.comparison import EncodingComparisonResult
from app.services.encoding_comparator import EncodingComparator


@pytest.fixture
def comparator() -> EncodingComparator:
    """Fixture to provide an EncodingComparator instance."""
    return EncodingComparator()


def test_compare_encoding_real_pipeline(comparator: EncodingComparator) -> None:
    """Verify that compare_encoding iterates through all 4 methods and calls run_pipeline."""
    mock_reports = {
        "rate": {
            "accuracy": 0.9,
            "latency_ms": 10.0,
            "spike_rate_hz": 500.0,
            "efficiency_bits_per_spike": 0.5,
        },
        "temporal": {
            "accuracy": 0.85,
            "latency_ms": 5.0,
            "spike_rate_hz": 100.0,
            "efficiency_bits_per_spike": 2.5,
        },
        "phase": {
            "accuracy": 0.8,
            "latency_ms": 12.0,
            "spike_rate_hz": 50.0,
            "efficiency_bits_per_spike": 3.0,
        },
        "burst": {
            "accuracy": 0.88,
            "latency_ms": 8.0,
            "spike_rate_hz": 200.0,
            "efficiency_bits_per_spike": 1.5,
        },
    }

    with patch("app.services.encoding_comparator.run_pipeline") as mock_run:
        mock_run.side_effect = lambda path, encoding_override, dataset_path: mock_reports[
            encoding_override
        ]

        result = comparator.compare_encoding(benchmark_id="test_bench", dataset_path="custom_data/")

        assert isinstance(result, EncodingComparisonResult)
        assert len(result.metrics) == 4
        assert mock_run.call_count == 4

        for call in mock_run.call_args_list:
            assert call.kwargs["dataset_path"] == "custom_data/"

        methods_called = [call.kwargs["encoding_override"] for call in mock_run.call_args_list]
        assert set(methods_called) == {"rate", "temporal", "phase", "burst"}


def test_recommendation_logic_accuracy_favored(comparator: EncodingComparator) -> None:
    """Verify recommendation when accuracy is heavily weighted."""
    mock_reports = {
        "rate": {
            "accuracy": 0.95,
            "latency_ms": 100.0,
            "spike_rate_hz": 1000.0,
        },  # Best accuracy, poor efficiency
        "temporal": {
            "accuracy": 0.70,
            "latency_ms": 5.0,
            "spike_rate_hz": 10.0,
        },  # Poor accuracy, best efficiency
        "phase": {"accuracy": 0.80, "latency_ms": 20.0, "spike_rate_hz": 50.0},
        "burst": {"accuracy": 0.85, "latency_ms": 30.0, "spike_rate_hz": 100.0},
    }

    with patch("app.services.encoding_comparator.run_pipeline") as mock_run:
        mock_run.side_effect = lambda path, encoding_override, dataset_path: mock_reports.get(
            encoding_override, {}
        )

        # High weight on accuracy
        weights = {"accuracy": 0.9, "latency": 0.05, "sparsity": 0.05}
        result = comparator.compare_encoding(weights=weights)
        assert "rate" in result.recommendation


def test_recommendation_logic_efficiency_favored(comparator: EncodingComparator) -> None:
    """Verify recommendation when efficiency (latency/sparsity) is heavily weighted."""
    mock_reports = {
        "rate": {
            "accuracy": 0.95,
            "latency_ms": 100.0,
            "spike_rate_hz": 1000.0,
        },  # Best accuracy, poor efficiency
        "temporal": {
            "accuracy": 0.70,
            "latency_ms": 1.0,
            "spike_rate_hz": 5.0,
        },  # Poor accuracy, best efficiency
        "phase": {"accuracy": 0.80, "latency_ms": 20.0, "spike_rate_hz": 50.0},
        "burst": {"accuracy": 0.85, "latency_ms": 30.0, "spike_rate_hz": 100.0},
    }

    with patch("app.services.encoding_comparator.run_pipeline") as mock_run:
        mock_run.side_effect = lambda path, encoding_override, dataset_path: mock_reports.get(
            encoding_override, {}
        )

        # High weight on latency and sparsity
        weights = {"accuracy": 0.1, "latency": 0.45, "sparsity": 0.45}
        result = comparator.compare_encoding(weights=weights)
        assert "temporal" in result.recommendation


def test_unsupported_encoding_raises_error(comparator: EncodingComparator) -> None:
    """Verify that an unsupported encoding method raises ValueError."""
    with patch("app.services.encoding_comparator.run_pipeline"):
        with pytest.raises(ValueError, match="Unsupported encoding method"):
            comparator.compare_encoding(methods_override=["invalid_method"])
