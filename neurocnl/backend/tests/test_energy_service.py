"""Tests for energy_service.py."""

import importlib
import sys
from unittest.mock import MagicMock, patch

import numpy as np
import pytest

from backend.app.schemas.prosthetic import EnergyRequest
from backend.app.services import energy_service
from backend.app.services.energy_service import run_energy_profile


@pytest.mark.anyio
async def test_run_energy_profile_no_profiler():
    """Test fallback mock branch when PowerProfiler is unavailable.

    Patches _ensure_profiler directly so the test is independent of whether
    neurodreamhand is installed in the current environment.
    """
    with patch("backend.app.services.energy_service._ensure_profiler", return_value=None):
        req = EnergyRequest(spec="test_spec", n_neurons=50, duration=1.0)
        result = run_energy_profile(req)
        assert result["total_pj"] == 250.0
        assert result["avg_power_uw"] == 0.25
        assert result["per_ensemble_pj"] == {"sensory": 100.0, "motor": 150.0}


@pytest.mark.anyio
async def test_run_energy_profile_with_profiler():
    """Test real-service branch with patched PowerProfiler."""
    mock_profiler = MagicMock()
    mock_estimate = MagicMock()
    mock_estimate.energy_pj = 500.0
    mock_estimate.avg_power_uw = 0.5
    mock_profiler.estimate_picojoules.return_value = mock_estimate

    with (
        patch("backend.app.services.energy_service._HAS_PROFILER", True),
        patch("backend.app.services.energy_service._profiler", mock_profiler),
    ):
        req = EnergyRequest(spec="test_spec", n_neurons=100, duration=2.0)
        result = run_energy_profile(req)

        assert result["total_pj"] == 500.0
        assert result["avg_power_uw"] == 0.5
        assert result["per_ensemble_pj"] == {}

        mock_profiler.estimate_picojoules.assert_called_once()
        _, kwargs = mock_profiler.estimate_picojoules.call_args
        assert np.array_equal(kwargs["spike_counts"], np.ones(100, dtype=int))
        assert kwargs["n_synapses"] == 100
        assert kwargs["duration_s"] == 2.0


@pytest.mark.anyio
async def test_energy_service_import_error():
    """Test the module-level import error for PowerProfiler."""
    with patch.dict(sys.modules, {"neurodreamhand.analytics.power_profiler": None}):
        importlib.reload(energy_service)
        assert energy_service._HAS_PROFILER is False
        assert energy_service._profiler is None
    # Cleanup: reload again with original state (or at least without None)
    importlib.reload(energy_service)
