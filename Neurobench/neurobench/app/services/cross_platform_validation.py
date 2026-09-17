from __future__ import annotations

import math
from dataclasses import dataclass


class ValidationComparisonError(ValueError):
    """Raised when cross-backend summaries cannot be compared honestly."""


@dataclass(frozen=True, slots=True)
class BackendRunSummary:
    """One backend's metric summary for a shared benchmark case."""

    case_id: str
    backend_name: str
    accuracy: float
    latency_ms: float
    energy_uj: float
    spike_similarity: float


@dataclass(frozen=True, slots=True)
class ValidationReport:
    """Deterministic aggregate comparison across multiple backend summaries."""

    case_id: str
    backend_names: tuple[str, ...]
    accuracy_divergence: float
    latency_spread_ms: float
    energy_spread_uj: float
    minimum_spike_similarity: float


def normalize_backend_name(name: str) -> str:
    """Return the canonical backend label for comparisons."""
    normalized = name.strip().lower()
    if not normalized:
        raise ValidationComparisonError("Backend name is empty after normalization")
    return normalized


def validate_runs(
    runs: list[BackendRunSummary],
) -> tuple[str, tuple[BackendRunSummary, ...]]:
    """Validate a comparison set and return it in deterministic backend order."""
    if len(runs) < 2:
        raise ValidationComparisonError("Comparison requires at least two runs")

    case_ids = {run.case_id for run in runs}
    if len(case_ids) != 1:
        raise ValidationComparisonError(f"Mismatched case_id values: {sorted(case_ids)}")

    normalized_names: list[str] = []
    for run in runs:
        normalized_names.append(normalize_backend_name(run.backend_name))

        if not math.isfinite(run.accuracy):
            raise ValidationComparisonError(f"Non-finite accuracy for backend {run.backend_name!r}")
        if not math.isfinite(run.latency_ms):
            raise ValidationComparisonError(
                f"Non-finite latency_ms for backend {run.backend_name!r}"
            )
        if not math.isfinite(run.energy_uj):
            raise ValidationComparisonError(
                f"Non-finite energy_uj for backend {run.backend_name!r}"
            )
        if not math.isfinite(run.spike_similarity):
            raise ValidationComparisonError(
                f"Non-finite spike_similarity for backend {run.backend_name!r}"
            )
        if not 0.0 <= run.spike_similarity <= 1.0:
            raise ValidationComparisonError(
                f"spike_similarity must stay inside [0.0, 1.0] for backend {run.backend_name!r}"
            )

    if len(set(normalized_names)) != len(normalized_names):
        raise ValidationComparisonError("Duplicate backend names found after normalization")

    sorted_runs = tuple(sorted(runs, key=lambda run: normalize_backend_name(run.backend_name)))
    return runs[0].case_id, sorted_runs


def build_validation_report(runs: list[BackendRunSummary]) -> ValidationReport:
    """Build aggregate divergence metrics for a validated comparison set."""
    case_id, sorted_runs = validate_runs(runs)
    backend_names = tuple(normalize_backend_name(run.backend_name) for run in sorted_runs)

    accuracies = [run.accuracy for run in sorted_runs]
    latencies = [run.latency_ms for run in sorted_runs]
    energies = [run.energy_uj for run in sorted_runs]
    spike_similarities = [run.spike_similarity for run in sorted_runs]

    return ValidationReport(
        case_id=case_id,
        backend_names=backend_names,
        accuracy_divergence=max(accuracies) - min(accuracies),
        latency_spread_ms=max(latencies) - min(latencies),
        energy_spread_uj=max(energies) - min(energies),
        minimum_spike_similarity=min(spike_similarities),
    )
