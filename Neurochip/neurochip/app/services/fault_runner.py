"""Fault injection service — simulates hardware fault impact on network accuracy."""

import random
from typing import Any

from neurochip.contracts.fault_contracts import FaultSweepResult

from ..schemas.estimation import NetworkInput


def _simulate_fault_impact(
    network: NetworkInput,
    fault_type: str,
    fault_rate: float,
    baseline_accuracy: float = 0.98,
    num_trials: int = 20,
    seed: int = 42,
) -> dict[str, Any]:
    """
    Simulate the impact of a given fault rate on network accuracy.

    In production, this would wrap neurodreamhand's fault_injector
    to run actual fault simulations on the network model.
    """
    random.seed(seed + int(fault_rate * 1000))

    if fault_rate == 0.0:
        return {
            "mean": baseline_accuracy,
            "ci_lower": baseline_accuracy - 0.005,
            "ci_upper": min(1.0, baseline_accuracy + 0.005),
        }

    # Degradation model depends on fault type
    if fault_type == "dead_neuron":
        # Graceful degradation — networks are somewhat robust to dead neurons
        degradation = fault_rate * 1.5  # linear-ish with acceleration
        degradation += (fault_rate**2) * 3.0  # quadratic term kicks in at high rates
    elif fault_type == "stuck_at_zero":
        # Similar to dead neuron but slightly worse
        degradation = fault_rate * 1.8 + (fault_rate**2) * 3.5
    elif fault_type == "stuck_at_max":
        # Stuck-at-max is more disruptive (injects noise)
        degradation = fault_rate * 2.5 + (fault_rate**2) * 4.0
    elif fault_type == "weight_noise":
        # Gaussian noise: gentler degradation
        degradation = fault_rate * 1.0 + (fault_rate**2) * 2.0
    else:
        degradation = fault_rate * 2.0

    # Simulate multiple trials for confidence intervals
    trial_results = []
    for _ in range(num_trials):
        noise = random.gauss(0, 0.02 * (1 + fault_rate * 5))
        acc = baseline_accuracy - degradation + noise
        acc = max(0.0, min(1.0, acc))
        trial_results.append(acc)

    mean_acc = sum(trial_results) / len(trial_results)
    sorted_trials = sorted(trial_results)
    ci_lower = sorted_trials[int(num_trials * 0.05)]
    ci_upper = sorted_trials[int(num_trials * 0.95) - 1]

    return {
        "mean": round(mean_acc, 4),
        "ci_lower": round(ci_lower, 4),
        "ci_upper": round(ci_upper, 4),
    }


def sweep_faults(
    network: NetworkInput,
    fault_type: str = "dead_neuron",
    fault_rates: list[float] | None = None,
    baseline_accuracy: float = 0.98,
) -> FaultSweepResult:
    """Run fault injection sweep across multiple fault rates."""
    if fault_rates is None:
        fault_rates = [0.0, 0.05, 0.10, 0.15, 0.20, 0.25, 0.30]

    accuracies = []
    ci_lower_list = []
    ci_upper_list = []

    for rate in fault_rates:
        result = _simulate_fault_impact(network, fault_type, rate, baseline_accuracy)
        accuracies.append(result["mean"])
        ci_lower_list.append(result["ci_lower"])
        ci_upper_list.append(result["ci_upper"])

    # Find threshold where accuracy drops below 90%
    threshold_90 = None
    for i, acc in enumerate(accuracies):
        if acc < 0.90:
            if i > 0:
                # Linear interpolation between the two points
                prev_rate = fault_rates[i - 1]
                prev_acc = accuracies[i - 1]
                slope = (acc - prev_acc) / (fault_rates[i] - prev_rate)
                if slope != 0:
                    threshold_90 = prev_rate + (0.90 - prev_acc) / slope
                else:
                    threshold_90 = fault_rates[i]
            else:
                threshold_90 = fault_rates[i]
            threshold_90 = round(threshold_90, 4)
            break

    return FaultSweepResult(
        fault_type=fault_type,
        fault_rates=fault_rates,
        accuracies=accuracies,
        accuracy_ci_lower=ci_lower_list,
        accuracy_ci_upper=ci_upper_list,
        threshold_90pct=threshold_90,
        method="synthetic_degradation_curve",
        is_estimate=True,
    )
