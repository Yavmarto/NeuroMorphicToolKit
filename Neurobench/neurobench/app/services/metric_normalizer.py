from __future__ import annotations

from collections.abc import Mapping
from dataclasses import dataclass
from typing import Any


class MetricNormalizationError(ValueError):
    """Raised when a present metric cannot be normalized safely."""


CANONICAL_KEYS = (
    "assertions_passed",
    "assertions_failed",
    "latency_ms",
    "energy_uj",
    "accuracy",
    "mujoco_steps",
)


@dataclass(frozen=True, slots=True)
class NormalizedMetrics:
    values: dict[str, float]


def select_metrics_container(payload: Mapping[str, Any]) -> Mapping[str, Any]:
    """Return the mapping that should be treated as the metric source."""
    results = payload.get("results")
    if isinstance(results, Mapping):
        return results

    metrics = payload.get("metrics")
    if isinstance(metrics, Mapping):
        return metrics

    return payload


def normalize_metrics(payload: Mapping[str, Any]) -> NormalizedMetrics:
    """Return the canonical metric dictionary for one backend payload."""
    container = select_metrics_container(payload)
    normalized: dict[str, float] = {}

    for key in CANONICAL_KEYS:
        if key not in container:
            normalized[key] = 0.0
            continue

        raw_value = container[key]
        if isinstance(raw_value, bool):
            raise MetricNormalizationError(
                f"Metric '{key}' has boolean value {raw_value!r}, which is not a valid numeric metric."
            )

        try:
            normalized[key] = float(raw_value)
        except (TypeError, ValueError) as exc:
            raise MetricNormalizationError(
                f"Metric '{key}' has value {raw_value!r} that cannot be coerced to float."
            ) from exc

    return NormalizedMetrics(values=normalized)
