"""Snapshot tests for neurocnl adapter — energy service & fault injection service.

These tests pin the exact output shape of the two primary data-processing
services that sit at the neurocnl → Flutter boundary.  Any future change
that silently alters field names, values, or structure will break here.

PYTHONPATH must include NeuroMorphicToolKit/neurocnl (set by verify_backend.sh
and pytest.ini so that `backend.app.*` and `neurocnl.*` are importable).
"""

from __future__ import annotations

from unittest.mock import patch


# ---------------------------------------------------------------------------
# Valid CNL specifications — these match the neurocnl grammar
# ---------------------------------------------------------------------------

# Minimal spec using constraint-style sentences (grammar-compliant)
_REFLEX_ARC_SPEC = (
    "The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0\n"
    "The sensory neuron MUST NOT fire DURING the refractory period of 0.002 seconds\n"
    "The sensory neuron membrane potential MUST decay WITH time constant of 0.02 seconds\n"
    "The connection from sensory neuron to motor neuron MUST have WITH synaptic weight of 1.0\n"
)


# ---------------------------------------------------------------------------
# 1. Energy service — mock-fallback path (no neurodreamhand hardware)
# ---------------------------------------------------------------------------


def test_energy_profile_mock_fallback_snapshot(snapshot: object) -> None:
    """Pin the mock-path EnergyResult returned when neurodreamhand is absent.

    The mock branch in energy_service.py returns a hard-coded EnergyResult.
    This snapshot guards against accidental mutation of those mock values.
    """
    # Patch _HAS_PROFILER to False so the deterministic mock branch is taken
    with patch("backend.app.services.energy_service._HAS_PROFILER", False):
        from backend.app.schemas.prosthetic import EnergyRequest
        from backend.app.services.energy_service import run_energy_profile

        req = EnergyRequest(spec=_REFLEX_ARC_SPEC, n_neurons=50, duration=1.0)
        result = run_energy_profile(req)

    assert result == snapshot


# ---------------------------------------------------------------------------
# 2. Fault injection service — deterministic structural analysis
# ---------------------------------------------------------------------------


def test_fault_injection_low_error_rate_snapshot(snapshot: object) -> None:
    """Pin the FaultInjectionResult for a two-population CNL spec at 10% error."""
    from backend.app.schemas.prosthetic import FaultInjectionRequest
    from backend.app.services.fault_injection_service import run_fault_injection_analysis

    req = FaultInjectionRequest(spec=_REFLEX_ARC_SPEC, error_rate=0.1)
    result = run_fault_injection_analysis(req)

    assert result == snapshot


def test_fault_injection_high_error_rate_snapshot(snapshot: object) -> None:
    """Pin the FaultInjectionResult at 80% error — resilience_score should drop."""
    from backend.app.schemas.prosthetic import FaultInjectionRequest
    from backend.app.services.fault_injection_service import run_fault_injection_analysis

    req = FaultInjectionRequest(spec=_REFLEX_ARC_SPEC, error_rate=0.8)
    result = run_fault_injection_analysis(req)

    assert result == snapshot


def test_fault_injection_zero_error_rate_snapshot(snapshot: object) -> None:
    """Pin the FaultInjectionResult when error_rate=0 (no injected faults)."""
    from backend.app.schemas.prosthetic import FaultInjectionRequest
    from backend.app.services.fault_injection_service import run_fault_injection_analysis

    req = FaultInjectionRequest(spec=_REFLEX_ARC_SPEC, error_rate=0.0)
    result = run_fault_injection_analysis(req)

    assert result == snapshot
