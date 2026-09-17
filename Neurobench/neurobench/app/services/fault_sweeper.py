import numpy as np
from scipy import stats  # type: ignore

from app.schemas.robustness import RobustnessCurve
from app.services.benchmark_runner import benchmark_runner


class FaultSweeper:
    """Wraps neurodreamhand fault injection.

    Sweeps across rates and aggregates robustness curves by executing real SNN simulations.
    """

    def sweep_faults(
        self,
        cnl_spec_path: str,
        benchmark_id: str,
        fault_type: str = "dead_neuron",
        fault_rates: list[float] | None = None,
    ) -> RobustnessCurve:
        """Runs a fault injection sweep.

        Args:
            cnl_spec_path (str): Path to the .cnl network specification file.
            benchmark_id (str): The ID of the benchmark definition to run.
            fault_type (str): The type of fault to inject (e.g., dead_neuron, stuck_at).
            fault_rates (list[float] | None): List of fault rates to sweep.

        Returns:
            RobustnessCurve: The generated robustness curve for the given fault type.
        """
        if fault_rates is None:
            fault_rates = [0.0, 0.05, 0.1, 0.15, 0.2, 0.3]

        n_seeds = 5
        accuracies_mean = []
        accuracies_ci_lower = []
        accuracies_ci_upper = []

        for rate in fault_rates:
            seed_accuracies = []
            for seed in range(n_seeds):
                result = benchmark_runner.run_benchmark(
                    benchmark_id=benchmark_id,
                    network_path=cnl_spec_path,
                    params={
                        "fault_type": fault_type,
                        "fault_rate": rate,
                    },
                    seed=seed,
                )
                accuracy = result.metrics.get("accuracy")
                seed_accuracies.append(float(accuracy) if accuracy is not None else 0.0)

            # Statistical aggregation
            mean = np.mean(seed_accuracies)
            std = np.std(seed_accuracies, ddof=1) if n_seeds > 1 else 0.0

            # 95% CI using t-distribution
            t_val = stats.t.ppf(0.975, n_seeds - 1)
            margin_of_error = t_val * (std / np.sqrt(n_seeds))

            accuracies_mean.append(float(mean))
            accuracies_ci_lower.append(float(max(0.0, mean - margin_of_error)))
            accuracies_ci_upper.append(float(min(1.0, mean + margin_of_error)))

        # Derive threshold_90pct via linear interpolation
        threshold_90pct = self._interpolate_threshold(fault_rates, accuracies_mean, 0.90)

        return RobustnessCurve(
            fault_type=fault_type,
            fault_rates=fault_rates,
            accuracies_mean=accuracies_mean,
            accuracies_ci_lower=accuracies_ci_lower,
            accuracies_ci_upper=accuracies_ci_upper,
            threshold_90pct=threshold_90pct,
            n_seeds=n_seeds,
        )

    def _interpolate_threshold(
        self, x: list[float], y: list[float], target_y: float
    ) -> float | None:
        """Finds the x value where y first drops below target_y using linear interpolation."""
        for i in range(len(y) - 1):
            y1, y2 = y[i], y[i + 1]
            x1, x2 = x[i], x[i + 1]

            if y1 >= target_y > y2:
                # Linear interpolation: y = y1 + (target_y - y1) * (x2 - x1) / (y2 - y1)
                return x1 + (target_y - y1) * (x2 - x1) / (y2 - y1)

            if y1 < target_y:
                # Already below threshold at the start of this interval
                # If it's the very first point, we might want to return that rate
                if i == 0:
                    return x1
                return x1

        # If it never drops below target_y
        if y[-1] >= target_y:
            return None

        return x[-1]


# Expose a singleton instance
fault_sweeper = FaultSweeper()
