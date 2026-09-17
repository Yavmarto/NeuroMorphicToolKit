from neurocnl.simulation.run_simulation import run_pipeline  # type: ignore

from app.schemas.comparison import EncodingComparisonResult, EncodingMetrics


class EncodingComparator:
    """Calls NeuroSense API for encoding variant comparison."""

    def compare_encoding(
        self,
        benchmark_id: str = "mock_bench",
        cnl_spec_path: str = "tests/test_network.cnl",
        dataset_path: str = "data/",
        weights: dict[str, float] | None = None,
        methods_override: list[str] | None = None,
    ) -> EncodingComparisonResult:
        """Runs an encoding strategy comparison.

        Args:
            benchmark_id (str): The ID of the benchmark.
            cnl_spec_path (str): Path to the CNL network specification.
            dataset_path (str): Path to the dataset for evaluation.
            weights (dict[str, float] | None): Weights for accuracy, latency, and spike sparsity.
            methods_override (list[str] | None): Optional list of methods to compare.

        Returns:
            EncodingComparisonResult: The generated encoding comparison metrics.

        Raises:
            ValueError: If an unsupported encoding method is provided.
        """
        allowed_methods = ["rate", "temporal", "phase", "burst"]
        methods = methods_override or allowed_methods
        metrics = []

        for method in methods:
            if method not in allowed_methods:
                raise ValueError(f"Unsupported encoding method: {method}")

            # Run simulation via neurocnl pipeline with encoding override
            # Pass dataset_path as an additional parameter to the pipeline
            report = run_pipeline(
                cnl_spec_path, encoding_override=method, dataset_path=dataset_path
            )

            # Extract metrics from report, using defaults for optional ones
            latency = report.get("latency_ms", 10.0)
            metrics.append(
                EncodingMetrics(
                    method=method,
                    accuracy=float(report.get("accuracy", 0.0)),
                    spike_rate_hz=float(report.get("spike_rate_hz", 100.0)),
                    efficiency_bits_per_spike=float(report.get("efficiency_bits_per_spike", 2.0)),
                    computation_cost_relative=float(latency / 10.0),
                )
            )

        # Default weights if not provided
        if not weights:
            weights = {"accuracy": 0.6, "latency": 0.2, "sparsity": 0.2}

        # Weighted scoring function
        def calculate_score(m: EncodingMetrics) -> float:
            # Normalize and combine: accuracy (higher better), latency (lower better),
            # spike_rate_hz (lower better)
            # Use simple normalization for illustration
            acc_score = m.accuracy
            lat_score = 1.0 / (1.0 + m.computation_cost_relative)
            sparse_score = 1.0 / (1.0 + m.spike_rate_hz / 1000.0)

            return (
                weights.get("accuracy", 0.0) * acc_score
                + weights.get("latency", 0.0) * lat_score
                + weights.get("sparsity", 0.0) * sparse_score
            )

        best_method = max(metrics, key=calculate_score)

        return EncodingComparisonResult(
            benchmark_id=benchmark_id,
            metrics=metrics,
            recommendation=(
                f"For this task and input type, {best_method.method} encoding achieves the best "
                "accuracy/efficiency tradeoff."
            ),
        )


# Expose a singleton instance
encoding_comparator = EncodingComparator()
