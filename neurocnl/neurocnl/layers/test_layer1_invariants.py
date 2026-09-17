"""Tests for the Layer 1 invariant registries.

Guards against regression on the 2026-07-04 hardware-invariant cleanup
(see current tasks/2026-07-04/validation-deploy-readiness/audit.md):
dead LOIHI/AKIDA/SPINNAKER/TEENSY invariant groups must stay gone, while
ALL_INVARIANTS (live via the canvas lif_population/adaptive_lif validation
path) and the NIR-native groups must stay intact.
"""

import neurocnl.layers.layer1_invariants as layer1_invariants
from neurocnl.layers.layer1_invariants import (
    ALL_INVARIANTS,
    NIR_CUBALIF_INVARIANTS,
    NIR_LIF_INVARIANTS,
)


def test_dropped_hardware_invariant_groups_no_longer_exist() -> None:
    for name in (
        "LOIHI_INVARIANTS",
        "AKIDA_INVARIANTS",
        "SPINNAKER_INVARIANTS",
        "SPINNAKER2_INVARIANTS",
        "TEENSY_INVARIANTS",
    ):
        assert not hasattr(layer1_invariants, name)


def test_dropped_loihi_functions_no_longer_exist() -> None:
    for name in (
        "loihi_weight_quantizable",
        "loihi_ensemble_size_within_limits",
        "loihi_delay_in_range",
        "loihi_delay_ticks_within_limits",
    ):
        assert not hasattr(layer1_invariants, name)


def test_all_invariants_unchanged() -> None:
    assert len(ALL_INVARIANTS) == 26
    assert "threshold_above_resting" in ALL_INVARIANTS
    assert "spatial_connectivity_radius_positive" in ALL_INVARIANTS
    assert all(callable(fn) for fn in ALL_INVARIANTS.values())


def test_nir_native_registries_unaffected() -> None:
    assert set(NIR_LIF_INVARIANTS) == {
        "nir_lif_time_constant_positive",
        "nir_lif_resistance_positive",
        "nir_lif_threshold_above_leak",
    }
    assert set(NIR_CUBALIF_INVARIANTS) == {
        "nir_cubalif_synaptic_time_constant_positive",
        "nir_cubalif_membrane_time_constant_positive",
        "nir_cubalif_resistance_positive",
        "nir_cubalif_threshold_above_leak",
    }
