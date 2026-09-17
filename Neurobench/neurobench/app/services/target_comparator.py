from types import SimpleNamespace

from app.schemas.comparison import TargetComparisonResult, TargetMetrics
from app.schemas.results import BenchmarkResult


def _run_benchmark(
    benchmark_id: str,
    network_path: str | None = None,
    network_content: str | None = None,
    params: dict[str, object] | None = None,
    seed: int | None = None,
    target: str = "simulation",
) -> BenchmarkResult:
    """Resolve the benchmark runner only when target comparison is executed."""
    from app.services.benchmark_runner import benchmark_runner as runner

    return runner.run_benchmark(
        benchmark_id=benchmark_id,
        network_path=network_path,
        network_content=network_content,
        params=params,
        seed=seed,
        target=target,
    )


benchmark_runner = SimpleNamespace(run_benchmark=_run_benchmark)

_TARGET_CONFIGS: list[tuple[str, str, int]] = [
    ("loihi2", "Loihi 2", 8),
    ("akida", "Akida 1.0", 4),
    ("teensy", "Teensy 4.1", 16),
    ("spinnaker2", "SpiNNaker2", 32),
]


class TargetComparator:
    """Calls NeuroChip API for per-target quantization and metrics."""

    @staticmethod
    def _metric_value(metrics: dict[str, float | None], name: str) -> float:
        value = metrics.get(name)
        return float(value) if value is not None else 0.0

    @classmethod
    def _metric_value_with_fallbacks(cls, metrics: dict[str, float | None], *names: str) -> float:
        for name in names:
            if name in metrics and metrics[name] is not None:
                return cls._metric_value(metrics, name)
        return 0.0

    def compare_targets(
        self,
        cnl_spec_path: str,
        benchmark_id: str = "mock_benchmark",
        network_spec_hash: str = "abcdef123456",
    ) -> TargetComparisonResult:
        """Runs a cross-target comparison.

        Args:
            cnl_spec_path (str): Path to the .cnl network specification file.
            benchmark_id (str): The ID of the benchmark.
            network_spec_hash (str): The hash of the network specification.

        Returns:
            TargetComparisonResult: The generated cross-target metrics.
        """
        # Get baseline simulation accuracy
        baseline_res = benchmark_runner.run_benchmark(
            benchmark_id, cnl_spec_path, target="simulation"
        )
        baseline_acc = self._metric_value(baseline_res.metrics, "accuracy")

        targets = []
        for target_id, target_name, quantization_bits in _TARGET_CONFIGS:
            res = benchmark_runner.run_benchmark(
                benchmark_id,
                cnl_spec_path,
                target=target_id,
            )
            m = res.metrics

            acc = self._metric_value(m, "accuracy")
            acc_loss = (baseline_acc - acc) * 100.0
            power = self._metric_value_with_fallbacks(m, "estimated_power_mw", "energy_uj")
            latency = self._metric_value_with_fallbacks(m, "estimated_latency_us", "latency_ms")
            mem = self._metric_value(m, "memory_kb")
            fidelity = self._metric_value(m, "spike_fidelity")

            warnings = []
            if acc_loss > 5.0:
                warnings.append("Quantization loss > 5%")
            if fidelity < 0.95:
                warnings.append("Spike fidelity < 0.95")

            targets.append(
                TargetMetrics(
                    target_id=target_id,
                    target_name=target_name,
                    quantization_bits=quantization_bits,
                    accuracy=acc,
                    accuracy_loss_pct=acc_loss,
                    estimated_power_mw=power,
                    estimated_latency_us=latency,
                    memory_kb=mem,
                    spike_fidelity=fidelity,
                    warnings=warnings,
                )
            )

        pareto_ids = self._calculate_pareto(targets)

        return TargetComparisonResult(
            benchmark_id=benchmark_id,
            network_spec_hash=baseline_res.network_spec_hash,
            targets=targets,
            pareto_optimal=pareto_ids,
        )

    def _calculate_pareto(self, targets: list[TargetMetrics]) -> list[str]:
        """Identifies Pareto-optimal targets based on accuracy, power, and latency.

        A target is Pareto-optimal if no other target is strictly better in all three
        dimensions: accuracy (higher is better), power (lower), and latency (lower).
        """
        pareto_ids = []
        for t1 in targets:
            is_dominated = False
            for t2 in targets:
                if t1 == t2:
                    continue

                # t2 dominates t1 if:
                # t2 is at least as good as t1 in all objectives AND
                # t2 is strictly better than t1 in at least one objective.

                # Objectives: Accuracy (max), Power (min), Latency (min)

                t2_better_or_equal = (
                    t2.accuracy >= t1.accuracy
                    and t2.estimated_power_mw <= t1.estimated_power_mw
                    and t2.estimated_latency_us <= t1.estimated_latency_us
                )

                t2_strictly_better = (
                    t2.accuracy > t1.accuracy
                    or t2.estimated_power_mw < t1.estimated_power_mw
                    or t2.estimated_latency_us < t1.estimated_latency_us
                )

                if t2_better_or_equal and t2_strictly_better:
                    is_dominated = True
                    break

            if not is_dominated:
                pareto_ids.append(t1.target_id)

        return pareto_ids


# Expose a singleton instance
target_comparator = TargetComparator()
