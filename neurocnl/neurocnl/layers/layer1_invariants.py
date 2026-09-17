"""Layer 1 Physical Invariants for LIF Neuron Model.

Each invariant is a Python function that validates neuron parameters against
non-negotiable biological constraints sourced from NeuroML's LIF definition
(iafTauCell / iafTauRefCell).

Merged from v-copilot (sophisticated decay check, registry, documentation)
and v-jules (defensive .get() parameter access).
"""

from __future__ import annotations

from collections.abc import Callable
from typing import Any

import numpy as np


def threshold_above_resting(params: dict[str, Any]) -> bool:
    """Threshold must be greater than resting membrane potential.

    NeuroML parameter: thresh > leakReversal
    A neuron that is already above threshold at rest would fire continuously
    without input, which is physically meaningless.
    """
    threshold = params.get("threshold")
    resting_potential = params.get("resting_potential")
    if threshold is None or resting_potential is None:
        return False
    return bool(threshold > resting_potential)


def refractory_period_positive(params: dict[str, Any]) -> bool:
    """Refractory period must be greater than zero.

    NeuroML parameter: refract > 0
    A zero refractory period means the neuron can spike at infinite frequency,
    which is biologically impossible.
    """
    refractory_period = params.get("refractory_period")
    if refractory_period is None:
        return False
    return bool(refractory_period > 0)


def time_constant_positive(params: dict[str, Any]) -> bool:
    """Time constant tau must be greater than zero.

    NeuroML parameter: tau > 0
    A non-positive time constant produces undefined or divergent membrane
    dynamics.
    """
    tau = params.get("tau")
    if tau is None:
        return False
    return bool(tau > 0)


def reset_at_or_below_threshold(params: dict[str, Any]) -> bool:
    """Reset potential must be less than or equal to threshold.

    NeuroML parameter: reset <= thresh
    Resetting above threshold would cause immediate re-firing, creating an
    unphysical infinite-frequency loop.
    """
    reset_potential = params.get("reset_potential")
    threshold = params.get("threshold")
    if reset_potential is None or threshold is None:
        return False
    return bool(reset_potential <= threshold)


def membrane_potential_decays_toward_rest(params: dict[str, Any]) -> bool:
    """Membrane potential must decay toward resting potential during inactivity.

    NeuroML dynamics: dv/dt = (leakReversal - v) / tau
    This is guaranteed when tau > 0 and dynamics follow the standard LIF
    equation. Validates that tau > 0 and that the voltage would move toward
    resting potential given no input.
    """
    tau = params.get("tau")
    if tau is None or tau <= 0:
        return False
    resting_potential = params.get("resting_potential", 0.0)
    v = params.get("current_voltage", resting_potential + 0.1)
    # dv/dt = (rest - v) / tau
    # If v > rest, dv/dt < 0 (voltage decreases toward rest)
    # If v < rest, dv/dt > 0 (voltage increases toward rest)
    # If v == rest, dv/dt == 0 (at rest)
    dv_dt = (resting_potential - v) / tau
    if v > resting_potential:
        return bool(dv_dt < 0)
    elif v < resting_potential:
        return bool(dv_dt > 0)
    else:
        return bool(dv_dt == 0)


def axonal_delay_in_range(params: dict[str, Any]) -> bool:
    """Axonal/synaptic transmission delay must be non-negative and bounded.

    Biological constraint: axonal delays range from ~0.1ms (local cortical)
    to ~150ms (longest peripheral nerves). A negative delay is unphysical.
    """
    delay = params.get("axonal_delay")
    if delay is None:
        return True  # delay is optional; absence is valid
    max_delay = params.get("max_axonal_delay", 0.150)  # 150ms default
    return bool(0 <= delay <= max_delay)


def stdp_window_positive(params: dict[str, Any]) -> bool:
    """STDP timing window must be positive and biologically reasonable.

    Biological constraint: STDP windows are typically 10–100ms.
    A zero or negative window is unphysical.
    """
    window = params.get("stdp_window")
    if window is None:
        return True  # STDP is optional; absence is valid
    max_window = params.get("max_stdp_window", 0.100)  # 100ms default
    return bool(0 < window <= max_window)


def stdp_weight_bounds_valid(params: dict[str, Any]) -> bool:
    """STDP weight bounds must define a valid range.

    Biological constraint: synaptic weights must be bounded to prevent
    runaway excitation or total silencing.
    """
    w_min = params.get("stdp_weight_min")
    w_max = params.get("stdp_weight_max")
    if w_min is None and w_max is None:
        return True  # bounds are optional
    if w_min is not None and w_max is not None:
        return bool(w_min < w_max and w_min >= 0)
    if w_min is not None:
        return bool(w_min >= 0)
    return True  # w_max alone is always valid


# === Concept 7: Inhibitory Connection Invariants ===


def inhibitory_weight_negative(params: dict[str, Any]) -> bool:
    """Inhibitory connection weight must be negative (or zero).

    If a connection is marked inhibitory, its weight must not be positive.
    """
    weight = params.get("inhibitory_weight")
    if weight is None:
        return True
    return float(weight) <= 0


# === Concept 8: Population Coding Invariants ===


def population_neuron_count_within_bounds(params: dict[str, Any]) -> bool:
    """Population neuron count must be a positive integer within bounds.

    Nengo ensembles require at least 1 neuron. Upper bound of 10,000 neurons.
    """
    n = params.get("population_n_neurons")
    if n is None:
        return True
    return 0 < int(n) <= 10000


def population_dimensions_positive(params: dict[str, Any]) -> bool:
    """Population dimensionality must be positive.

    Nengo ensembles represent at least 1-dimensional signals.
    """
    d = params.get("population_dimensions")
    if d is None:
        return True
    return int(d) > 0


def population_radius_positive(params: dict[str, Any]) -> bool:
    """Population radius (representation range) must be positive.

    The radius defines the range of values the ensemble can represent.
    """
    r = params.get("population_radius")
    if r is None:
        return True
    return float(r) > 0


def learning_rate_positive(params: dict[str, Any]) -> bool:
    """Learning rate must be positive."""
    lr = params.get("learning_rate")
    if lr is None:
        return True  # optional
    return bool(lr > 0)


def learning_rule_valid(params: dict[str, Any]) -> bool:
    """Learning rule type must be one of the supported types."""
    rule_type = params.get("learning_rule_type")
    if rule_type is None:
        return True  # optional
    return rule_type.upper() in {"PES", "BCM", "OJA", "STDP"}


def network_timestep_positive(params: dict[str, Any]) -> bool:
    """Global network timestep must be positive."""
    timestep = params.get("network_timestep")
    if timestep is None:
        return True
    return float(timestep) > 0


def delay_quantization_step_positive(params: dict[str, Any]) -> bool:
    """Delay quantization step must be positive."""
    step = params.get("delay_quantization_step")
    if step is None:
        return True
    return float(step) > 0


def biological_speed_multiplier_positive(params: dict[str, Any]) -> bool:
    """Biological speed multiplier must be positive."""
    multiplier = params.get("biological_speed_multiplier")
    if multiplier is None:
        return True
    return float(multiplier) > 0


def delay_quantization_not_finer_than_timestep(params: dict[str, Any]) -> bool:
    """Delay quantization should not be finer than the declared network timestep."""
    timestep = params.get("network_timestep")
    quantization = params.get("delay_quantization_step")
    if timestep is None or quantization is None:
        return True
    return float(quantization) >= float(timestep)


# === Concept 10: Lateral Inhibition Invariants ===


def lateral_inhibition_radius_positive(params: dict[str, Any]) -> bool:
    """Lateral inhibition radius must be positive."""
    radius = params.get("lateral_inhibition_radius")
    if radius is None:
        return True
    return float(radius) > 0


# === Concept 11: Homeostatic Plasticity Invariants ===


def homeostatic_target_rate_positive(params: dict[str, Any]) -> bool:
    """Homeostatic target firing rate must be positive."""
    rate = params.get("homeostatic_target_rate")
    if rate is None:
        return True
    return float(rate) > 0


# === Concept 12: Neuromodulation Invariants ===


def neuromodulation_factor_positive(params: dict[str, Any]) -> bool:
    """Neuromodulation factor must be positive."""
    factor = params.get("neuromodulation_factor")
    if factor is None:
        return True
    return float(factor) > 0


# === Concept 13: Population Coding Range Invariants ===


def population_coding_range_positive(params: dict[str, Any]) -> bool:
    """Population coding range must be positive."""
    range_val = params.get("population_coding_range")
    if range_val is None:
        return True
    return float(range_val) > 0


# === Concept 14: Adaptive Spiking Invariants ===


def adaptive_spiking_tau_positive(params: dict[str, Any]) -> bool:
    """Adaptive spiking time constant must be positive."""
    tau_n = params.get("adaptation_tau")
    if tau_n is None:
        return True
    return float(tau_n) > 0


# === Concept 16: Short-Term Plasticity Invariants ===


def stp_recovery_time_positive(params: dict[str, Any]) -> bool:
    """STP recovery time must be positive."""
    recovery_time = params.get("stp_recovery_time")
    if recovery_time is None:
        return True
    return float(recovery_time) > 0


# === Concept 17: Background Synaptic Noise Invariants ===


def background_noise_variance_positive(params: dict[str, Any]) -> bool:
    """Background noise variance (or amplitude) must be non-negative."""
    variance = params.get("noise_variance")
    amplitude = params.get("noise_amplitude")
    if variance is not None and float(variance) < 0:
        return False
    return not (amplitude is not None and float(amplitude) < 0)


# === Concept 18: Spatial Connectivity Invariants ===


def spatial_connectivity_radius_positive(params: dict[str, Any]) -> bool:
    """Spatial connectivity radius must be positive."""
    radius = params.get("spatial_radius")
    if radius is None:
        return True
    return float(radius) > 0


# Registry of all invariants for programmatic access
ALL_INVARIANTS = {
    "threshold_above_resting": threshold_above_resting,
    "refractory_period_positive": refractory_period_positive,
    "time_constant_positive": time_constant_positive,
    "reset_at_or_below_threshold": reset_at_or_below_threshold,
    "membrane_potential_decays_toward_rest": membrane_potential_decays_toward_rest,
    "axonal_delay_in_range": axonal_delay_in_range,
    "stdp_window_positive": stdp_window_positive,
    "stdp_weight_bounds_valid": stdp_weight_bounds_valid,
    "inhibitory_weight_negative": inhibitory_weight_negative,
    "population_neuron_count_positive": population_neuron_count_within_bounds,
    "population_dimensions_positive": population_dimensions_positive,
    "population_radius_positive": population_radius_positive,
    "learning_rate_positive": learning_rate_positive,
    "learning_rule_valid": learning_rule_valid,
    "network_timestep_positive": network_timestep_positive,
    "delay_quantization_step_positive": delay_quantization_step_positive,
    "biological_speed_multiplier_positive": biological_speed_multiplier_positive,
    "delay_quantization_not_finer_than_timestep": delay_quantization_not_finer_than_timestep,
    "lateral_inhibition_radius_positive": lateral_inhibition_radius_positive,
    "homeostatic_target_rate_positive": homeostatic_target_rate_positive,
    "neuromodulation_factor_positive": neuromodulation_factor_positive,
    "population_coding_range_positive": population_coding_range_positive,
    "adaptive_spiking_tau_positive": adaptive_spiking_tau_positive,
    "stp_recovery_time_positive": stp_recovery_time_positive,
    "background_noise_variance_positive": background_noise_variance_positive,
    "spatial_connectivity_radius_positive": spatial_connectivity_radius_positive,
}


# NOTE: Loihi-specific invariants (LOIHI_INVARIANTS, loihi_* functions) were
# removed 2026-07-04 as dead code — validate()'s backend=="loihi" branch that
# consumed them has no live caller (see
# current tasks/2026-07-04/validation-deploy-readiness/audit.md).


# ---------------------------------------------------------------------------
# NIR-native invariants — operate on NIR parameter names directly.
# nir.LIF uses: tau, r, v_leak, v_threshold
# NOTE: NIR LIF has NO refractory_period or v_reset — do not add those here.
# ---------------------------------------------------------------------------


def nir_lif_time_constant_positive(params: dict[str, Any]) -> bool:
    """tau must be strictly positive (time constant cannot be zero or negative)."""
    tau = params.get("tau")
    if tau is None:
        return True  # missing param is caught by compiler; skip gracefully
    return float(np.atleast_1d(tau)[0]) > 0.0


def nir_lif_resistance_positive(params: dict[str, Any]) -> bool:
    """r must be strictly positive."""
    r = params.get("r")
    if r is None:
        return True
    return float(np.atleast_1d(r)[0]) > 0.0


def nir_lif_threshold_above_leak(params: dict[str, Any]) -> bool:
    """v_threshold must be above v_leak (leak voltage = resting potential)."""
    v_threshold = params.get("v_threshold")
    v_leak = params.get("v_leak")
    if v_threshold is None or v_leak is None:
        return True
    return float(np.atleast_1d(v_threshold)[0]) > float(np.atleast_1d(v_leak)[0])


NIR_LIF_INVARIANTS: dict[str, Callable[[dict[str, Any]], bool]] = {
    "nir_lif_time_constant_positive": nir_lif_time_constant_positive,
    "nir_lif_resistance_positive": nir_lif_resistance_positive,
    "nir_lif_threshold_above_leak": nir_lif_threshold_above_leak,
}


# ---------------------------------------------------------------------------
# NIR CubaLIF invariants
# nir.CubaLIF uses: tau_syn, tau_mem, r, v_leak, v_threshold, w_in
# ---------------------------------------------------------------------------


def nir_cubalif_synaptic_time_constant_positive(params: dict[str, Any]) -> bool:
    """tau_syn must be strictly positive."""
    tau_syn = params.get("tau_syn")
    if tau_syn is None:
        return True
    return float(np.atleast_1d(tau_syn)[0]) > 0.0


def nir_cubalif_membrane_time_constant_positive(params: dict[str, Any]) -> bool:
    """tau_mem must be strictly positive."""
    tau_mem = params.get("tau_mem")
    if tau_mem is None:
        return True
    return float(np.atleast_1d(tau_mem)[0]) > 0.0


def nir_cubalif_resistance_positive(params: dict[str, Any]) -> bool:
    """r must be strictly positive."""
    r = params.get("r")
    if r is None:
        return True
    return float(np.atleast_1d(r)[0]) > 0.0


def nir_cubalif_threshold_above_leak(params: dict[str, Any]) -> bool:
    """v_threshold must be above v_leak."""
    v_threshold = params.get("v_threshold")
    v_leak = params.get("v_leak")
    if v_threshold is None or v_leak is None:
        return True
    return float(np.atleast_1d(v_threshold)[0]) > float(np.atleast_1d(v_leak)[0])


NIR_CUBALIF_INVARIANTS: dict[str, Callable[[dict[str, Any]], bool]] = {
    "nir_cubalif_synaptic_time_constant_positive": nir_cubalif_synaptic_time_constant_positive,
    "nir_cubalif_membrane_time_constant_positive": nir_cubalif_membrane_time_constant_positive,
    "nir_cubalif_resistance_positive": nir_cubalif_resistance_positive,
    "nir_cubalif_threshold_above_leak": nir_cubalif_threshold_above_leak,
}
