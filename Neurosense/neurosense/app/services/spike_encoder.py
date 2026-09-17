"""
Spike encoding service wrapping encoding methods (rate, temporal, delta).

When the neurocnl package is available it delegates to its spike_encoding
module; otherwise a pure-numpy fallback is used so the API is functional
during development.
"""

from __future__ import annotations

import importlib
from typing import Any, cast

import numpy as np

from neurosense.contracts.encoding_contracts import EncodingConfig


def _load_scipy_signal() -> Any | None:
    """Load scipy.signal lazily so type checking does not require stubs."""
    try:
        return cast(Any, importlib.import_module("scipy.signal"))
    except ImportError:
        return None


class SpikeEncoder:
    """Encodes analog biosignal data into spike trains."""

    def __init__(self) -> None:
        self._config: EncodingConfig | None = None
        self._sampling_rate: float = 250.0
        self._rng = np.random.default_rng()

    def configure(
        self, config: EncodingConfig, sampling_rate: float = 250.0, seed: int | None = None
    ) -> None:
        self._config = config
        self._sampling_rate = sampling_rate
        if seed is not None:
            self._rng = np.random.default_rng(seed)

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def encode(self, data: np.ndarray[Any, Any]) -> dict[str, Any]:
        """Encode a (channels x samples) array into spike events.

        Returns a dict with:
            spike_trains: list of per-channel spike time arrays
            spike_counts: list of per-channel spike counts
            method: encoding method used
        """
        if self._config is None:
            raise RuntimeError("Encoder not configured. Call configure() first.")

        method = self._config.method
        if method == "rate":
            return self._rate_encode(data)
        if method == "temporal":
            return self._temporal_encode(data)
        if method == "delta":
            return self._delta_encode(data)
        raise ValueError(f"Unknown encoding method: {method}")

    def encode_batch(
        self,
        data: list[list[float]],
        config: EncodingConfig,
        sampling_rate: float = 250.0,
    ) -> dict[str, Any]:
        """One-shot encode for the /encode endpoint (no prior configure needed)."""
        self.configure(config, sampling_rate)
        arr = np.array(data, dtype=np.float64)
        if arr.ndim == 1:
            arr = arr.reshape(1, -1)
        return self.encode(arr)

    # ------------------------------------------------------------------
    # Encoding methods
    # ------------------------------------------------------------------

    def _apply_refractory(self, spike_times: np.ndarray[Any, Any]) -> list[float]:
        """Apply refractory period to spike times."""
        if len(spike_times) == 0:
            return []
        if self._config is None:
            return cast(list[float], spike_times.tolist())

        refractory_period = self._config.refractory_period

        # This is the non-vectorized part, but it's much faster
        # as it only runs on spike events, not every sample.
        final_spikes = []
        last_spike_time = -refractory_period
        for t in spike_times:
            if t - last_spike_time >= refractory_period:
                final_spikes.append(float(t))
                last_spike_time = t
        return final_spikes

    def _rate_encode(self, data: np.ndarray[Any, Any]) -> dict[str, Any]:
        """Rate encoding: spike probability proportional to signal amplitude."""
        if self._config is None:
            raise RuntimeError("Encoder not configured.")
        max_rate = self._config.rate_max_hz or 200.0
        dt = 1.0 / self._sampling_rate

        sig_min = data.min(axis=-1, keepdims=True)
        sig_max = data.max(axis=-1, keepdims=True)
        range_val = sig_max - sig_min

        normalized = np.zeros_like(data)
        valid_mask = range_val.squeeze(axis=-1) > 0
        if np.any(valid_mask):
            normalized[valid_mask] = (data[valid_mask] - sig_min[valid_mask]) / range_val[
                valid_mask
            ]

        rates = normalized * max_rate
        spike_probs = rates * dt

        raw_spikes = (spike_probs > self._rng.random(spike_probs.shape)).astype(np.float64)

        spike_trains = []
        spike_counts = []

        for ch in range(data.shape[0]):
            raw_times = np.where(raw_spikes[ch] > 0)[0] / self._sampling_rate
            times = self._apply_refractory(raw_times)
            spike_trains.append(times)
            spike_counts.append(len(times))

        return {
            "spike_trains": spike_trains,
            "spike_counts": spike_counts,
            "method": "rate",
        }

    def _temporal_encode(self, data: np.ndarray[Any, Any]) -> dict[str, Any]:
        """Temporal encoding: spike timing encodes phase within oscillation cycles."""
        if self._config is None:
            raise RuntimeError("Encoder not configured.")
        phase_bins = self._config.temporal_phase_bins or 8
        spike_trains = []
        spike_counts = []

        scipy_signal = _load_scipy_signal()
        hilbert = scipy_signal.hilbert if scipy_signal is not None else None

        if hilbert is not None:
            analytic = hilbert(data, axis=-1)
            phase = np.angle(analytic)
        else:
            # Fallback: simple zero-crossing phase estimation
            phase = np.zeros_like(data)
            for ch in range(data.shape[0]):
                for i in range(1, data.shape[1]):
                    if data[ch, i - 1] <= 0 < data[ch, i]:
                        phase[ch, i] = 0.0
                    else:
                        phase[ch, i] = phase[ch, i - 1] + 2 * np.pi / phase_bins

        bin_indices = ((phase + np.pi) / (2 * np.pi) * phase_bins).astype(int) % phase_bins
        transitions = np.diff(bin_indices, axis=-1) != 0

        for ch in range(data.shape[0]):
            raw_times = np.where(transitions[ch])[0] / self._sampling_rate
            times = self._apply_refractory(raw_times)
            spike_trains.append(times)
            spike_counts.append(len(times))

        return {
            "spike_trains": spike_trains,
            "spike_counts": spike_counts,
            "method": "temporal",
        }

    def _delta_encode(self, data: np.ndarray[Any, Any]) -> dict[str, Any]:
        """Delta modulation: spike when signal change exceeds threshold.
        Delta encoding is inherently sequential, so we stick to the loop but
        ensure units are consistent.
        """
        if self._config is None:
            raise RuntimeError("Encoder not configured.")
        threshold = self._config.delta_threshold or 10.0
        refractory_period = self._config.refractory_period
        spike_trains = []
        spike_counts = []

        for ch in range(data.shape[0]):
            signal = data[ch]
            times = []
            reference = signal[0] if len(signal) > 0 else 0.0
            last_spike_time = -refractory_period

            for i in range(1, len(signal)):
                current_time = i / self._sampling_rate
                diff = signal[i] - reference
                if abs(diff) >= threshold and current_time - last_spike_time >= refractory_period:
                    times.append(float(current_time))
                    last_spike_time = current_time
                    reference = signal[i]

            spike_trains.append(times)
            spike_counts.append(len(times))

        return {
            "spike_trains": spike_trains,
            "spike_counts": spike_counts,
            "method": "delta",
        }


# ---------------------------------------------------------------------------
# Module-level singleton
# ---------------------------------------------------------------------------
spike_encoder = SpikeEncoder()
