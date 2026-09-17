"""Shared training-registry construction."""

from __future__ import annotations

from neurocnl.training.sleep_pes_adapter import SleepPesAdapter
from neurocnl.training_registry import TrainingAdapterRegistry


def build_training_registry() -> TrainingAdapterRegistry:
    return TrainingAdapterRegistry(
        [
            SleepPesAdapter(),
        ]
    )
