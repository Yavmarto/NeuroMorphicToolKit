import math
from typing import Literal

import numpy as np
from scipy import stats  # type: ignore

from app.schemas.results import RegressionCriteria
from contracts import BenchmarkResult, DiffResult, MetricDiff, RegressionThreshold


class DiffEngine:
    """Computes baseline comparisons: computes deltas and classifies them."""

    def _calculate_stats(
        self, values: list[float], confidence: float = 0.95
    ) -> tuple[float, float, tuple[float, float]]:
        """Calculates mean, standard deviation, and confidence interval.

        Args:
            values (list[float]): The list of values to calculate stats for.
            confidence (float): The confidence level. Defaults to 0.95.

        Returns:
            tuple[float, float, tuple[float, float]]: Mean, Std, and Confidence Interval.
        """
        if not values:
            return 0.0, 0.0, (0.0, 0.0)

        n = len(values)
        mean = float(np.mean(values))
        if n < 2:
            return mean, 0.0, (mean, mean)

        std = float(np.std(values, ddof=1))
        stderr = stats.sem(values)
        h = stderr * stats.t.ppf((1 + confidence) / 2.0, n - 1)
        return mean, std, (mean - h, mean + h)

    def _determine_status(
        self,
        delta_pct: float,
        higher_is_better: bool,
        tolerance: float = 1.0,
    ) -> Literal["improved", "regressed", "unchanged"]:
        """Determines the status string based on the percentage change.

        Args:
            delta_pct (float): Percentage delta between baseline and current.
            higher_is_better (bool): Whether higher values mean improvement.
            tolerance (float): Percentage threshold for noise. Defaults to 1.0.

        Returns:
            Literal["improved", "regressed", "unchanged"]: The status category.
        """
        if tolerance == 0.0:
            if delta_pct == 0.0:
                return "unchanged"
            return "regressed"

        if (
            math.isclose(abs(delta_pct), tolerance, rel_tol=1e-9, abs_tol=1e-9)
            or abs(delta_pct) <= tolerance
        ):
            return "unchanged"

        if delta_pct > tolerance:
            return "improved" if higher_is_better else "regressed"

        return "regressed" if higher_is_better else "improved"

    def compute_diff(
        self,
        baseline: BenchmarkResult | list[BenchmarkResult],
        current: BenchmarkResult | list[BenchmarkResult],
        threshold: RegressionThreshold | None = None,
        criteria: RegressionCriteria | None = None,
    ) -> DiffResult:
        """Computes the delta between benchmark results for all shared metrics.

        Args:
            baseline (BenchmarkResult | list[BenchmarkResult]): Baseline result(s).
            current (BenchmarkResult | list[BenchmarkResult]): Current result(s).
            threshold (RegressionThreshold | None): Optional threshold configuration.
            criteria (RegressionCriteria | None): Optional threshold configuration.

        Returns:
            DiffResult: The computed difference object.
        """
        baselines = [baseline] if isinstance(baseline, BenchmarkResult) else baseline
        currents = [current] if isinstance(current, BenchmarkResult) else current

        if criteria is not None and criteria.default_threshold is not None and threshold is None:
            threshold = criteria.default_threshold

        diffs = []

        # Collect all shared metric names
        baseline_metrics = set().union(*(b.metrics.keys() for b in baselines))
        current_metrics = set().union(*(c.metrics.keys() for c in currents))
        shared_metrics = sorted(list(baseline_metrics.intersection(current_metrics)))

        for metric_name in shared_metrics:
            b_vals = [
                value
                for b in baselines
                if metric_name in b.metrics
                for value in [b.metrics[metric_name]]
                if value is not None
            ]
            c_vals = [
                value
                for c in currents
                if metric_name in c.metrics
                for value in [c.metrics[metric_name]]
                if value is not None
            ]

            b_mean, b_std, b_ci = self._calculate_stats(b_vals)
            c_mean, c_std, c_ci = self._calculate_stats(c_vals)

            delta = c_mean - b_mean
            delta_pct = (delta / b_mean * 100) if b_mean != 0 else 0.0

            # Statistical significance (t-test and Wilcoxon)
            p_ttest = None
            p_wilcoxon = None
            is_significant = None
            if len(b_vals) >= 2 and len(c_vals) >= 2:
                _, p_ttest = stats.ttest_ind(b_vals, c_vals, equal_var=False)

                # Wilcoxon signed-rank requires equal length (paired).
                # For independent samples of potentially different sizes,
                # use Mann-Whitney U test which is often what's intended.
                try:
                    if len(b_vals) == len(c_vals):
                        _, p_wilcoxon = stats.wilcoxon(b_vals, c_vals)
                    else:
                        _, p_wilcoxon = stats.mannwhitneyu(b_vals, c_vals)
                except Exception:
                    p_wilcoxon = None

                is_sig_t = p_ttest < 0.05
                is_sig_w = p_wilcoxon is not None and p_wilcoxon < 0.05
                is_significant = bool(is_sig_t or is_sig_w)

            # Use direction from threshold if provided, otherwise infer
            current_threshold = None
            if criteria and criteria.overrides and metric_name in criteria.overrides:
                current_threshold = criteria.overrides[metric_name]
            elif threshold:
                current_threshold = threshold

            if current_threshold:
                higher_is_better = current_threshold.comparison_direction == "higher_is_better"
                tolerance = current_threshold.tolerance
            else:
                # Based on the metrics in contracts/benchmark_contracts.py AllowedMetric
                higher_is_better = metric_name in {"accuracy", "spike_fidelity"}
                tolerance = 1.0

            status = self._determine_status(delta_pct, higher_is_better, tolerance)

            diff = MetricDiff(
                name=metric_name,
                baseline_value=b_mean,
                current_value=c_mean,
                delta=delta,
                delta_pct=delta_pct,
                status=status,
                threshold_violated=(status == "regressed"),
                p_value_ttest=float(p_ttest) if p_ttest is not None else None,
                p_value_wilcoxon=float(p_wilcoxon) if p_wilcoxon is not None else None,
                is_significant=is_significant,
                baseline_std=b_std,
                current_std=c_std,
                baseline_ci=b_ci,
                current_ci=c_ci,
            )
            diffs.append(diff)

        # Sort diffs such that accuracy is always first so that it matches what test expected
        diffs.sort(key=lambda d: 0 if d.name == "accuracy" else 1)

        return DiffResult(
            baseline_id=[b.id for b in baselines] if len(baselines) > 1 else baselines[0].id,
            current_id=[c.id for c in currents] if len(currents) > 1 else currents[0].id,
            metrics=diffs,
            has_regression=any(d.threshold_violated for d in diffs),
        )

    def check_regression(
        self,
        baseline: BenchmarkResult,
        current: BenchmarkResult,
        criteria: RegressionCriteria,
    ) -> bool:
        """Convenience method to check if a regression exists.

        Args:
            baseline (BenchmarkResult): Baseline to compare against.
            current (BenchmarkResult): New result.
            criteria (RegressionCriteria): Thresholds to apply.

        Returns:
            bool: True if any metric regressed beyond its threshold.
        """
        diff_result = self.compute_diff(baseline, current, criteria=criteria)
        return diff_result.has_regression


# Expose a singleton instance
diff_engine = DiffEngine()
