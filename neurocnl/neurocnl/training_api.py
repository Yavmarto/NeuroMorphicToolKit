"""Thin public training entrypoints for neurocnl."""

from __future__ import annotations

from typing import Any

from neurocnl.training.factory import build_training_registry
from neurocnl.training_registry import TrainingRequest, TrainingResult


def fit(
    spec: str,
    *,
    backend: str = "snntorch",
    training_mode: str | None = None,
    dataset: str = "n-mnist",
    payload: dict[str, Any] | None = None,
) -> TrainingResult:
    """Train a CNL-defined model via the configured adapter registry."""

    merged_payload = dict(payload or {})
    merged_payload.setdefault("spec", spec)
    merged_payload.setdefault("dataset", dataset)
    registry = build_training_registry()
    return registry.dispatch(
        TrainingRequest(
            backend_name=backend,
            training_mode=training_mode,
            payload=merged_payload,
        )
    )
