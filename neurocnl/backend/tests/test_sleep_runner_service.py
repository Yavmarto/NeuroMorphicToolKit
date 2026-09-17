"""Tests for sleep_runner.py (deprecated wrapper)."""

import warnings
from unittest.mock import patch

import pytest

from backend.app.schemas.prosthetic import SleepTrainRequest
from backend.app.services.sleep_runner import run_sleep_training


def test_run_sleep_training_delegates_to_adapter():
    """The deprecated wrapper delegates to SleepPesAdapter.run()."""
    from neurocnl.training_registry import TrainingResult

    mock_result = TrainingResult(
        adapter_name="sleep_pes",
        training_mode="offline_sleep",
        status="completed",
        n_epochs=5,
        final_loss=0.05,
        loss_curve=(1.0, 0.5, 0.2, 0.1, 0.05),
        learned_weights=[[0.1, 0.2], [0.3, 0.4]],
    )

    with (
        patch(
            "neurocnl.training.sleep_pes_adapter.SleepPesAdapter.run",
            return_value=mock_result,
        ),
        warnings.catch_warnings(record=True) as w,
    ):
        warnings.simplefilter("always")
        req = SleepTrainRequest(
            spec="test_spec",
            memory_buffer=[{"slip_vz": 0.01, "grip": 0.5, "error": 0.1}],
            n_epochs=5,
            homeostasis_factor=0.01,
        )
        result = run_sleep_training(req)
        assert result["n_epochs"] == 5
        assert result["final_loss"] == 0.05
        # Should emit DeprecationWarning
        assert any(issubclass(warning.category, DeprecationWarning) for warning in w)


@pytest.mark.anyio
async def test_run_sleep_training_fallback():
    """The wrapper surfaces an honest failure when neurodreamhand is unavailable.

    SleepPesAdapter._run_fallback used to fake a "completed" result with a
    synthetic loss curve when the runtime was missing; it now reports status
    "failed" with an OPTIONAL_DEPENDENCY_MISSING reason instead, so the UI
    shows a real "install the runtime" message rather than a fake success.
    """
    req = SleepTrainRequest(
        spec="test_spec",
        memory_buffer=[],
        n_epochs=5,
        homeostasis_factor=0.01,
    )
    # This will exercise the real SleepPesAdapter._run_fallback path
    # since neurodreamhand is not installed in test environment
    with warnings.catch_warnings(record=True):
        warnings.simplefilter("always")
        result = run_sleep_training(req)
        assert result["status"] == "failed"
        assert result["metadata"]["unavailable_reason_code"] == "optional_dependency_missing"
        assert result["metadata"]["dependency_name"] == "neurodreamhand"
        assert "neurodreamhand" in result["error"]
