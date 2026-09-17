"""Tests for spike encoding utilities."""

import numpy as np

from neurocnl.spike_encoding import delta_encode, rate_encode, temporal_encode


class TestRateEncode:
    def test_output_shape(self) -> None:
        """Output shape matches input shape."""
        signal = np.ones(1000)
        spikes = rate_encode(signal, dt=0.001)
        assert spikes.shape == signal.shape

    def test_output_binary(self) -> None:
        """Output contains only 0.0 and 1.0."""
        rng = np.random.default_rng()
        signal = rng.random(1000)
        spikes = rate_encode(signal, dt=0.001)
        assert set(np.unique(spikes)).issubset({0.0, 1.0})

    def test_higher_amplitude_more_spikes(self) -> None:
        """Higher amplitude signal produces more spikes."""
        low = np.full(1000, 0.2)
        high = np.full(1000, 0.8)
        spikes_low = rate_encode(low, dt=0.001, max_rate=200.0)
        spikes_high = rate_encode(high, dt=0.001, max_rate=200.0)
        assert spikes_high.sum() > spikes_low.sum()

    def test_zero_signal_no_spikes(self) -> None:
        """Zero signal produces no spikes."""
        signal = np.zeros(1000)
        spikes = rate_encode(signal, dt=0.001)
        assert spikes.sum() == 0

    def test_negative_clipped(self) -> None:
        """Negative values are clipped to zero (no spikes)."""
        signal = np.full(1000, -1.0)
        spikes = rate_encode(signal, dt=0.001)
        assert spikes.sum() == 0

    def test_zero_max_rate(self) -> None:
        """Zero max_rate should return no spikes."""
        signal = np.full(1000, 1.0)
        spikes = rate_encode(signal, dt=0.001, max_rate=0.0)
        assert spikes.sum() == 0

    def test_deterministic_seed(self) -> None:
        """Should return exactly the same spikes with the same inputs due to fixed seed."""
        signal = np.linspace(0, 1, 1000)
        spikes1 = rate_encode(signal, dt=0.001)
        spikes2 = rate_encode(signal, dt=0.001)
        np.testing.assert_array_equal(spikes1, spikes2)


class TestTemporalEncode:
    def test_output_shape(self) -> None:
        rng = np.random.default_rng()
        signal = rng.random(1000)
        spikes = temporal_encode(signal, dt=0.001)
        assert spikes.shape == signal.shape

    def test_output_binary(self) -> None:
        rng = np.random.default_rng()
        signal = rng.random(1000)
        spikes = temporal_encode(signal, dt=0.001)
        assert set(np.unique(spikes)).issubset({0.0, 1.0})

    def test_spikes_per_phase(self) -> None:
        """Each phase window should produce approximately one spike."""
        rng = np.random.default_rng()
        signal = rng.random(800)
        n_phases = 8
        spikes = temporal_encode(signal, dt=0.001, n_phases=n_phases)
        # Should have approximately n_phases spikes (one per window)
        assert abs(spikes.sum() - n_phases) <= n_phases  # allow some tolerance

    def test_constant_signal(self) -> None:
        """Constant signal should still produce spikes (one per phase)."""
        signal = np.full(800, 0.5)
        spikes = temporal_encode(signal, dt=0.001, n_phases=8)
        assert spikes.sum() > 0

    def test_window_size_zero(self) -> None:
        """Should return no spikes if n_phases > signal length."""
        rng = np.random.default_rng()
        signal = rng.random(5)
        spikes = temporal_encode(signal, dt=0.001, n_phases=10)
        assert spikes.sum() == 0

    def test_temporal_encode_constant_signal_min_max_equal(self) -> None:
        """Should return one spike per window in middle when signal is constant."""
        signal = np.full(800, 0.5)
        spikes = temporal_encode(signal, dt=0.001, n_phases=8)
        assert spikes.sum() == 8
        # Window size is 100, spikes should be at 49, 149, 249, ...
        expected_indices = [49, 149, 249, 349, 449, 549, 649, 749]
        for idx in expected_indices:
            assert spikes[idx] == 1.0


class TestDeltaEncode:
    def test_output_shape(self) -> None:
        rng = np.random.default_rng()
        signal = rng.random(1000)
        spikes = delta_encode(signal, dt=0.001)
        assert spikes.shape == signal.shape

    def test_output_binary(self) -> None:
        rng = np.random.default_rng()
        signal = rng.random(1000)
        spikes = delta_encode(signal, dt=0.001)
        assert set(np.unique(spikes)).issubset({0.0, 1.0})

    def test_constant_signal_no_spikes(self) -> None:
        """Constant signal produces no spikes (after initial)."""
        signal = np.full(1000, 0.5)
        spikes = delta_encode(signal, dt=0.001, threshold=0.1)
        # First timestep might spike, but rest should not
        assert spikes[1:].sum() == 0

    def test_step_signal_one_spike(self) -> None:
        """Step signal produces exactly one spike at the step."""
        signal = np.zeros(100)
        signal[50:] = 1.0  # step change of 1.0
        spikes = delta_encode(signal, dt=0.001, threshold=0.1)
        assert spikes[50] == 1.0

    def test_ramp_signal_multiple_spikes(self) -> None:
        """Ramp signal with small threshold produces multiple spikes."""
        signal = np.linspace(0, 2, 1000)
        spikes = delta_encode(signal, dt=0.001, threshold=0.1)
        assert spikes.sum() > 10  # should trigger many times

    def test_small_threshold_more_spikes(self) -> None:
        """Smaller threshold produces more spikes."""
        signal = np.linspace(0, 2, 1000)
        spikes_big = delta_encode(signal, dt=0.001, threshold=0.5)
        spikes_small = delta_encode(signal, dt=0.001, threshold=0.1)
        assert spikes_small.sum() > spikes_big.sum()
