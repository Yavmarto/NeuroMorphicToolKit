from app.services.result_store import result_store
from contracts import TrendAnalysisResult, TrendPoint


class RegressionService:
    """Service for historical trend analysis and regression detection."""

    def get_trends(self, benchmark_id: str) -> TrendAnalysisResult:
        """Fetch all historical results for a benchmark and format as trends.

        Args:
            benchmark_id (str): The ID of the benchmark to analyze.

        Returns:
            TrendAnalysisResult: The historical trend data.
        """
        all_results = result_store.get_all_results()
        benchmark_results = [r for r in all_results if r.benchmark_id == benchmark_id]

        # Sort by timestamp
        benchmark_results.sort(key=lambda x: x.timestamp)

        history: list[TrendPoint] = []
        metric_names: set[str] = set()
        for r in benchmark_results:
            history.append(
                TrendPoint(
                    timestamp=r.timestamp,
                    result_id=r.id,
                    metrics={name: value for name, value in r.metrics.items() if value is not None},
                )
            )
            metric_names.update(r.metrics.keys())

        return TrendAnalysisResult(
            benchmark_id=benchmark_id,
            metric_names=sorted(list(metric_names)),
            history=history,
        )


# Expose a singleton instance
regression_service = RegressionService()
