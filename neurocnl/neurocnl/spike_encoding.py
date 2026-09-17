"""Spike Encoding Utilities.

Convert continuous analog signals into discrete spike trains for
spiking neural networks. Three encoding strategies are provided:

- **Rate coding**: Spike rate proportional to signal amplitude.
  Best for slow signals (force, temperature).
- **Temporal coding**: Spike timing encodes signal phase.
  Best for fast signals (EMG, vibration).
- **Delta modulation**: Spike on signal change exceeding threshold.
  Best for event-driven sensors.

All functions return NumPy arrays compatible with Nengo input nodes.
"""

from typing import Any

import numpy as np


def rate_encode(
    signal: np.ndarray[Any, Any], dt: float, max_rate: float = 100.0
) -> np.ndarray[Any, Any]:
    """Convert analog signal to spike train using rate coding.

    The spike rate at each timestep is proportional to the normalized
    signal amplitude. Higher amplitude → higher spike probability per timestep.

    Parameters
    ----------
    signal : np.ndarray
        1-D analog signal, shape (n_timesteps,). Values should be non-negative.
        Negative values are clipped to 0.
    dt : float
        Simulation timestep in seconds (e.g., 0.001 for 1ms).
    max_rate : float
        Maximum spike rate in Hz when signal is at its peak. Default 100 Hz.

    Returns
    -------
    np.ndarray
        Binary spike train, shape (n_timesteps,). 1.0 where spike occurs,
        0.0 otherwise.
    """
    clipped = np.clip(signal, 0.0, None)
    if clipped.max() == 0.0:
        return np.zeros_like(signal, dtype=float)
    rng = np.random.default_rng(42)
    prob = np.clip(clipped * max_rate * dt, 0.0, 1.0)
    spikes: np.ndarray[Any, Any] = (rng.random(len(signal)) < prob).astype(float)
    return spikes


def temporal_encode(
    signal: np.ndarray[Any, Any], dt: float, n_phases: int = 8
) -> np.ndarray[Any, Any]:
    """Convert analog signal to spike train using temporal/phase coding.

    Signal is divided into phase bins. Each bin boundary triggers a spike
    whose timing (position within the bin) encodes the signal amplitude.
    Higher amplitude → earlier spike within the phase window.

    Parameters
    ----------
    signal : np.ndarray
        1-D analog signal, shape (n_timesteps,).
    dt : float
        Simulation timestep in seconds.
    n_phases : int
        Number of phase bins to divide the signal into. Default 8.

    Returns
    -------
    np.ndarray
        Binary spike train, shape (n_timesteps,). 1.0 where spike occurs,
        0.0 otherwise.
    """
    n = len(signal)
    spikes = np.zeros(n, dtype=float)

    sig_min = signal.min()
    sig_max = signal.max()
    if sig_max == sig_min:
        normalized = np.full(n, 0.5)
    else:
        normalized = (signal - sig_min) / (sig_max - sig_min)

    window_size = n // n_phases
    if window_size == 0:
        return spikes

    for i in range(n_phases):
        start = i * window_size
        end = start + window_size

        avg_amp = normalized[start:end].mean()
        spike_offset = int((1.0 - avg_amp) * (window_size - 1))
        spike_idx = start + spike_offset
        spikes[spike_idx] = 1.0

    return spikes


def delta_encode(
    signal: np.ndarray[Any, Any], dt: float, threshold: float = 0.1
) -> np.ndarray[Any, Any]:
    """Convert analog signal to spike train using delta modulation.

    A spike is emitted whenever the signal change since the last spike
    exceeds the threshold. Produces sparse spike trains for slowly-varying
    signals and dense trains for rapidly-changing signals.

    Parameters
    ----------
    signal : np.ndarray
        1-D analog signal, shape (n_timesteps,).
    dt : float
        Simulation timestep in seconds (used for documentation consistency;
        delta modulation is threshold-based, not rate-based).
    threshold : float
        Minimum absolute change in signal value to trigger a spike. Default 0.1.

    Returns
    -------
    np.ndarray
        Binary spike train, shape (n_timesteps,). 1.0 where spike occurs,
        0.0 otherwise.
    """
    n = len(signal)
    spikes = np.zeros(n, dtype=float)
    reference = signal[0]

    for t in range(1, n):
        if abs(signal[t] - reference) >= threshold:
            spikes[t] = 1.0
            reference = signal[t]

    return spikes
