# Interfaces

Document only signatures, types, schemas, and stub bodies here.

## Target Surface 1: `metric_normalizer.py`

```python
from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Mapping


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
    raise NotImplementedError


def normalize_metrics(payload: Mapping[str, Any]) -> NormalizedMetrics:
    """Return the canonical metric dictionary for one backend payload."""
    raise NotImplementedError
```

## Target Surface 2: `benchmark_runner.py`

Expected integration behavior:

- the runner calls `normalize_metrics(...)`
- hardware-target callers still receive a plain canonical `dict[str, float]`
- invalid metric payloads remain wrapped by the runner's normal error surface

## Target Surface 3: `test_metric_normalizer.py` and adjacent runner tests

Expected test themes:

- `results` precedence
- `metrics` fallback
- defaults for missing keys
- string numeric coercion
- invalid string rejection
- boolean rejection
- integration through the benchmark runner

# Reference Notes

- The canonical helper is intentionally narrow and should not absorb unrelated benchmark logic.
- This slice may clean up a small adjacent extraction helper if it directly reduces duplication, but it should not broaden into report generation or UI work.
