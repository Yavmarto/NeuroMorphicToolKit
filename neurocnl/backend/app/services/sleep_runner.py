"""Deprecated: sleep training service.

This module is kept as a thin compatibility wrapper that delegates
to the SleepPesAdapter. Use training_service.submit_training_job()
or submit_training_job_forced() instead.
"""

from __future__ import annotations

import warnings
from dataclasses import asdict

import structlog

from backend.app.schemas.prosthetic import SleepTrainRequest
from neurocnl.training.sleep_pes_adapter import SleepPesAdapter
from neurocnl.training_registry import TrainingRequest

logger = structlog.get_logger(__name__)

# Keep these names for backward compatibility with tests that import them
_HAS_SLEEP = True


def run_sleep_training(req: SleepTrainRequest) -> dict:
    """Run offline PES sleep training.

    .. deprecated::
        Use SleepPesAdapter.run() directly or submit via training_service.
    """
    warnings.warn(
        "run_sleep_training is deprecated; use SleepPesAdapter directly.",
        DeprecationWarning,
        stacklevel=2,
    )
    adapter = SleepPesAdapter()
    training_request = TrainingRequest(
        backend_name="sleep_pes",
        training_mode="offline_sleep",
        payload=req.model_dump(),
    )
    result = adapter.run(training_request)
    return asdict(result)
