"""Snapshot tests for Neuro-Dream-Hand adapter — power profiler and EMG encoder.

Neuro-Dream-Hand is a library (no HTTP port) imported by neurocnl and
Neurochip for prosthetic simulation.  These tests pin the output of its
two primary numerical entry points:

  * `PowerProfiler.estimate_picojoules` — energy estimation from spike counts
  * `EMGSpikeEncoder.encode`            — EMG window → spike-probability vector

Both functions are pure numpy computations with no hardware or timing
dependencies, so their output is perfectly reproducible.

PYTHONPATH must include NeuroMorphicToolKit/Neuro-Dream-Hand (or the
package must be importable as `neurodreamhand`).
"""

from __future__ import annotations

import numpy as np
import pytest


# ---------------------------------------------------------------------------
# 1. PowerProfiler — pure arithmetic, no randomness
# ---------------------------------------------------------------------------


def test_power_profiler_estimate_uniform_spikes_snapshot(snapshot: object) -> None:
    """Pin the PowerEstimate for 10 neurons each firing 5 times with 100 synapses."""
    from neurodreamhand.analytics.power_profiler import PowerProfiler

    profiler = PowerProfiler(energy_per_sop_pj=10.0, clock_hz=1_000.0)
    spike_counts = np.full(10, 5, dtype=np.int64)
    estimate = profiler.estimate_picojoules(spike_counts, n_synapses=100, duration_s=1.0)

    # Convert NamedTuple to dict for human-readable snapshot
    assert estimate._asdict() == snapshot


def test_power_profiler_estimate_sparse_spikes_snapshot(snapshot: object) -> None:
    """Pin the PowerEstimate for a sparse network (most neurons silent)."""
    from neurodreamhand.analytics.power_profiler import PowerProfiler

    profiler = PowerProfiler(energy_per_sop_pj=10.0, clock_hz=1_000.0)
    # 50 neurons: 48 silent, 2 firing 10 spikes each
    spike_counts = np.zeros(50, dtype=np.int64)
    spike_counts[0] = 10
    spike_counts[1] = 10
    estimate = profiler.estimate_picojoules(spike_counts, n_synapses=50, duration_s=0.5)

    assert estimate._asdict() == snapshot


def test_power_profiler_inferred_duration_snapshot(snapshot: object) -> None:
    """Pin the PowerEstimate when duration_s=None (inferred from clock and neuron count)."""
    from neurodreamhand.analytics.power_profiler import PowerProfiler

    profiler = PowerProfiler(energy_per_sop_pj=23.0, clock_hz=1_000.0)
    spike_counts = np.array([3, 7, 2, 8], dtype=np.int64)
    # duration_s=None → duration_s = len(spike_counts) / clock_hz = 4 / 1000 = 0.004 s
    estimate = profiler.estimate_picojoules(spike_counts, n_synapses=200)

    assert estimate._asdict() == snapshot


# ---------------------------------------------------------------------------
# 2. EMGSpikeEncoder — scipy filter on fixed seed data
# ---------------------------------------------------------------------------


def test_emg_encoder_output_shape_and_range_snapshot(snapshot: object) -> None:
    """Pin the spike-probability vector for a 2-channel, 100-sample EMG window.

    The encoder produces np.full(n_neurons, normalized_value), so all
    elements are identical.  We snapshot the shape and the unique value.
    """
    from neurodreamhand.hardware.emg_encoder import EMGSpikeEncoder

    rng = np.random.default_rng(seed=42)
    # Shape: (n_channels=2, window_samples=100), amplitude ±200 µV
    emg_frame = rng.normal(0, 200, (2, 100))

    encoder = EMGSpikeEncoder(n_neurons=8, sample_rate=200.0)
    output = encoder.encode(emg_frame)

    # Snapshot shape + rounded scalar value for stability across float repr
    assert {
        "shape": list(output.shape),
        "all_equal": bool(np.all(output == output[0])),
        "value_rounded_4dp": round(float(output[0]), 4),
    } == snapshot


def test_emg_encoder_zero_signal_snapshot(snapshot: object) -> None:
    """Pin the encoder output for a flat-zero EMG signal (no muscle activity)."""
    from neurodreamhand.hardware.emg_encoder import EMGSpikeEncoder

    encoder = EMGSpikeEncoder(n_neurons=4, sample_rate=200.0)
    zero_frame = np.zeros((2, 80))
    output = encoder.encode(zero_frame)

    assert {
        "shape": list(output.shape),
        "value_rounded_4dp": round(float(output[0]), 4),
    } == snapshot


def test_emg_encoder_high_amplitude_clamps_to_one_snapshot(snapshot: object) -> None:
    """Pin that a very high-amplitude signal does not exceed 1.0 (clip guard)."""
    from neurodreamhand.hardware.emg_encoder import EMGSpikeEncoder

    rng = np.random.default_rng(seed=7)
    emg_frame = rng.normal(0, 2_000_000, (2, 100))  # extreme amplitude

    encoder = EMGSpikeEncoder(n_neurons=4, sample_rate=200.0)
    # Prime the running_max so the normalization adapts
    encoder.update_running_stats(emg_frame)
    output = encoder.encode(emg_frame)

    assert {
        "shape": list(output.shape),
        "max_value": round(float(output.max()), 4),
        "all_in_range": bool((output >= 0.0).all() and (output <= 1.0).all()),
    } == snapshot
