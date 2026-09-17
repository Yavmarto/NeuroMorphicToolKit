import json
import os
import uuid
from datetime import datetime
from pathlib import Path
from unittest.mock import MagicMock, patch

from py.path import local  # type: ignore

from app.schemas.results import BenchmarkResult
from app.services.report_generator import ReportGenerator


def test_generate_report_json(tmpdir: local) -> None:
    """Test generating a JSON report."""
    with patch("os.getcwd", return_value=str(tmpdir)):
        generator = ReportGenerator()
        result = generator.generate_report(format="json", summary="Test JSON")
        assert result.status == "completed"
        assert result.format == "json"

        file_path = os.path.join(str(tmpdir), "data", "reports", f"{result.report_id}.json")
        assert Path(file_path).exists()

        with open(file_path) as f:
            data = json.load(f)
            assert data["summary"] == "Test JSON"


def test_generate_report_html(tmpdir: local) -> None:
    """Test generating an HTML report."""
    with patch("os.getcwd", return_value=str(tmpdir)):
        generator = ReportGenerator()
        result = generator.generate_report(format="html", summary="Test HTML")
        assert result.status == "completed"
        assert result.format == "html"

        file_path = os.path.join(str(tmpdir), "data", "reports", f"{result.report_id}.html")
        assert Path(file_path).exists()

        with open(file_path) as f:
            data = f.read()
            assert "Test HTML" in data


def test_generate_report_pdf(tmpdir: local) -> None:
    """Test generating a PDF report."""
    with patch("os.getcwd", return_value=str(tmpdir)):
        generator = ReportGenerator()
        # Mock HTML object directly since weasyprint might fail in some environments
        with patch("app.services.report_generator.HTML", create=True) as mock_html:
            mock_write_pdf = MagicMock()
            mock_html.return_value.write_pdf = mock_write_pdf

            with patch("app.services.report_generator.WEASYPRINT_AVAILABLE", True):
                result = generator.generate_report(format="pdf")
                assert result.status == "completed"
                assert result.format == "pdf"
                mock_write_pdf.assert_called_once()


def test_generate_chart_base64(tmpdir: local) -> None:
    """Test generating a chart and returning it as base64."""
    generator = ReportGenerator()
    results = {"accuracy": 0.95, "latency_ms": 12.5}
    chart_base64 = generator._generate_chart_base64(results)

    assert chart_base64 is not None
    assert isinstance(chart_base64, str)
    assert len(chart_base64) > 100

    # Test empty results
    empty_chart = generator._generate_chart_base64({})
    assert empty_chart is None


def test_generate_report_json_with_benchmark_result(tmpdir: local) -> None:
    """Test JSON report export for a result with NaN, inf, UUID, and datetime values."""
    # Ensure isolation
    from app.services.result_store import ResultStore

    db_path = os.path.join(str(tmpdir), "test_neurobench.sqlite")
    temp_store = ResultStore(db_path=db_path)

    with patch("app.services.report_generator.result_store", temp_store):
        generator = ReportGenerator()
        generator.output_dir = os.path.join(str(tmpdir), "data", "reports")
        os.makedirs(generator.output_dir, exist_ok=True)

        # Create a benchmark result with edge-case types
        test_uuid = uuid.uuid4()
        test_dt = datetime.now()
        br = BenchmarkResult(
            id="res_test_export",
            benchmark_id="bench_x",
            network_spec_hash="hash123",
            timestamp="2026-04-01T12:00:00Z",
            target_id="loihi2",
            quantization_bits=8,
            encoding_method="rate",
            params={"uuid_val": test_uuid, "dt_val": test_dt, "nested": {"nested_uuid": test_uuid}},
            metrics={
                "accuracy": 0.95,
                "latency_nan": float("nan"),
                "power_inf": float("inf"),
            },
            wall_time_seconds=1.5,
            seed=42,
        )

        # Save it to our patched store
        temp_store.save_result(br)

        result = generator.generate_report(
            format="json",
            summary="Exporting benchmark result",
            result_id="res_test_export",
            new_baseline=True,
        )

        assert result.status == "completed"

        # Verify the file output
        file_path = os.path.join(generator.output_dir, f"{result.report_id}.json")
        assert Path(file_path).exists()

        with open(file_path) as f:
            data = json.load(f)

        assert data["new_baseline"] is True
        assert data["network_spec_hash"] == "hash123"
        assert "benchmark_result" in data

        # Verify custom serialization behavior
        payload = data["benchmark_result"]

        # NaN and Inf should become null
        assert payload["metrics"]["latency_nan"] is None
        assert payload["metrics"]["power_inf"] is None
        assert payload["metrics"]["accuracy"] == 0.95

        # UUIDs should be plain strings
        assert payload["params"]["uuid_val"] == str(test_uuid)
        assert payload["params"]["nested"]["nested_uuid"] == str(test_uuid)

        # Datetime should be ISO-8601 string
        # Pydantic formats it ending with Z
        dt_str = payload["params"]["dt_val"]
        assert isinstance(dt_str, str)
        assert "T" in dt_str

        # Ensure it was saved as a baseline
        baseline = temp_store.get_all_baselines()
        assert len(baseline) == 1
        assert baseline[0].id == "res_test_export"
