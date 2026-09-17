import base64
import importlib
import io
import json
import logging
import os
import uuid
from collections.abc import Mapping
from datetime import datetime
from typing import Any, Literal, cast

from jinja2 import Environment, FileSystemLoader

from app.schemas.reports import ReportGenerationResult
from app.services.result_store import result_store

try:
    from weasyprint import HTML  # type: ignore

    WEASYPRINT_AVAILABLE = True
except ImportError:
    WEASYPRINT_AVAILABLE = False


logger = logging.getLogger(__name__)


def _load_matplotlib_pyplot() -> Any | None:
    """Load matplotlib lazily so report extras do not block server startup."""
    try:
        matplotlib = importlib.import_module("matplotlib")
        matplotlib.use("Agg")
        return cast(Any, importlib.import_module("matplotlib.pyplot"))
    except ImportError:
        logger.warning("matplotlib unavailable; report charts will be omitted")
        return None


class ReportGenerator:
    """Handles PDF/HTML benchmark report generation."""

    def __init__(self) -> None:
        """Initialize the report generator."""
        self.output_dir = os.path.join(
            os.environ.get(
                "NEUROBENCH_DATA_DIR",
                os.environ.get("NEUROCNL_DATA_DIR", os.path.join(os.getcwd(), "data")),
            ),
            "reports",
        )
        # ponytail: created on write, not here — this class is instantiated at import time,
        # so an unwritable NEUROCNL_DATA_DIR used to kill the whole suite_api worker.
        template_dir = os.path.join(os.path.dirname(os.path.dirname(__file__)), "templates")
        self.env = Environment(loader=FileSystemLoader(template_dir))

    @staticmethod
    def _sanitize_metrics(results: Mapping[str, float | None]) -> dict[str, float]:
        """Drop unset metric values before charting or serializing typed result maps."""
        return {name: value for name, value in results.items() if value is not None}

    def _generate_chart_base64(self, results: dict[str, float]) -> str | None:
        """Generates a bar chart of the results and returns it as a base64 encoded string.

        Args:
            results: A dictionary of metric names and their values.

        Returns:
            str | None: Base64 encoded string of the PNG chart, or None if error.
        """
        if not results:
            return None

        try:
            plt = _load_matplotlib_pyplot()
            if plt is None:
                return None

            metrics = list(results.keys())
            values = list(results.values())

            fig, ax = plt.subplots(figsize=(8, 4))
            ax.bar(metrics, values, color="skyblue")
            ax.set_ylabel("Value")
            ax.set_title("Benchmark Results")
            plt.xticks(rotation=45, ha="right")
            plt.tight_layout()

            buf = io.BytesIO()
            plt.savefig(buf, format="png")
            plt.close(fig)
            buf.seek(0)

            return base64.b64encode(buf.read()).decode("utf-8")
        except Exception:
            logger.exception("Error generating chart")
            return None

    def generate_report(
        self,
        format: Literal["pdf", "html", "json"] = "pdf",
        summary: str = "Executive summary of the benchmark run.",
        methodology: str = "Standard SNN evaluation methodology used.",
        results: dict[str, float] | None = None,
        recommendations: str = "Consider deploying to target hardware.",
        result_id: str | None = None,
        new_baseline: bool = False,
    ) -> ReportGenerationResult:
        """Generate a benchmark report in the specified format.

        Args:
            format: The format of the report to generate (pdf, html, or json).
            summary: The executive summary section content.
            methodology: The methodology section content.
            results: A dictionary of metric names and their values.
            recommendations: The recommendations section content.
            result_id: The ID of the benchmark result to include.
            new_baseline: Whether this result should establish a new baseline.

        Returns:
            ReportGenerationResult: A response containing report location and status.
        """
        logger.info(
            "Starting report generation in format: %s",
            format,
            extra={"format": format},
        )

        report_id = f"rep_{uuid.uuid4().hex[:8]}"
        timestamp = datetime.now().isoformat()

        benchmark_result = None
        if result_id:
            benchmark_result = result_store.get_result(result_id)
            if benchmark_result and new_baseline:
                result_store.save_baseline(benchmark_result)

        if results is None:
            if benchmark_result:
                results = self._sanitize_metrics(benchmark_result.metrics)
            else:
                results = {"accuracy": 0.95, "latency_ms": 12.5}
        else:
            results = self._sanitize_metrics(results)

        chart_base64 = self._generate_chart_base64(results)

        report_data: dict[str, Any] = {
            "report_id": report_id,
            "timestamp": timestamp,
            "summary": summary,
            "methodology": methodology,
            "results": results,
            "recommendations": recommendations,
            "chart_base64": chart_base64,
        }

        if benchmark_result:
            # We dump to a primitive dict handling NaN/Inf per ConfigDict and UUID/datetime natively
            report_data["benchmark_result"] = json.loads(benchmark_result.model_dump_json())
            report_data["network_spec_hash"] = benchmark_result.network_spec_hash

        if new_baseline:
            report_data["new_baseline"] = True

        os.makedirs(self.output_dir, exist_ok=True)
        file_path = os.path.join(self.output_dir, f"{report_id}.{format}")
        status: Literal["pending", "completed", "failed"] = "completed"

        try:
            if format == "json":
                # Exclude the heavy base64 string from the json output for clarity
                json_data = report_data.copy()
                json_data.pop("chart_base64", None)
                with open(file_path, "w") as f:
                    json.dump(json_data, f, indent=2)
            elif format == "html" or format == "pdf":
                template = self.env.get_template("report.html")
                html_content = template.render(**report_data)

                if format == "html":
                    with open(file_path, "w") as f:
                        f.write(html_content)
                elif format == "pdf":
                    if not WEASYPRINT_AVAILABLE:
                        logger.error("WeasyPrint is not available for PDF generation.")
                        status = "failed"
                    else:
                        HTML(string=html_content).write_pdf(file_path)
        except Exception:
            logger.exception("Error generating %s report", format)
            status = "failed"

        result = ReportGenerationResult(
            report_id=report_id,
            status=status,
            download_url=f"/reports/{report_id}.{format}" if status == "completed" else None,
            format=format,
            timestamp=timestamp,
        )

        logger.info(
            "Report generation completed: %s",
            report_id,
            extra={
                "report_id": report_id,
                "format": format,
                "status": result.status,
            },
        )

        return result


# Expose a singleton instance
report_generator = ReportGenerator()
