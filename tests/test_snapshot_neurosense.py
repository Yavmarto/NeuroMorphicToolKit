"""Snapshot tests for Neurosense adapter — spike encoding service.

`SpikeEncoder` is the core data-processing boundary: raw biosignal arrays
in → structured spike-train dicts out.  Snapshots guard against changes to
encoding logic, threshold handling, or output key names.

Delta encoding is used for most tests because it is fully sequential and
contains no random number generation, making it 100% deterministic.
Temporal encoding is included to pin the Hilbert-transform branch.

PYTHONPATH must include NeuroMorphicToolKit/Neurosense so that
`neurosense.app.*` and `neurosense.contracts.*` are importable.
"""

from __future__ import annotations

import numpy as np

# ---------------------------------------------------------------------------
# Fixed test signal: 2 channels × 50 samples, amplitude 0–100 µV
# ---------------------------------------------------------------------------
_RNG = np.random.default_rng(seed=0)
_SIGNAL_2CH_50S: list[list[float]] = _RNG.uniform(0, 100, (2, 50)).tolist()
_SIGNAL_1CH_80S: list[list[float]] = (_RNG.uniform(-50, 50, (1, 80))).tolist()


# ---------------------------------------------------------------------------
# EncodingConfig helpers
# ---------------------------------------------------------------------------


def _delta_config(threshold: float = 15.0) -> object:
    from neurosense.contracts.encoding_contracts import EncodingConfig

    return EncodingConfig(
        method="delta",
        delta_threshold=threshold,
        refractory_period=0.004,
    )


def _temporal_config() -> object:
    from neurosense.contracts.encoding_contracts import EncodingConfig

    return EncodingConfig(
        method="temporal",
        temporal_phase_bins=8,
        refractory_period=0.004,
    )


def _rate_config(max_hz: float = 200.0) -> object:
    from neurosense.contracts.encoding_contracts import EncodingConfig

    return EncodingConfig(
        method="rate",
        rate_max_hz=max_hz,
        refractory_period=0.004,
    )


# ---------------------------------------------------------------------------
# 1. Delta encoding (fully deterministic — no RNG)
# ---------------------------------------------------------------------------


def test_spike_encoder_delta_two_channel_snapshot(snapshot: object) -> None:
    """Pin delta-encoded spike trains for a 2-channel, 50-sample signal."""
    from neurosense.app.services.spike_encoder import SpikeEncoder

    enc = SpikeEncoder()
    result = enc.encode_batch(_SIGNAL_2CH_50S, _delta_config(), sampling_rate=250.0)
    assert result == snapshot


def test_spike_encoder_delta_one_channel_snapshot(snapshot: object) -> None:
    """Pin delta-encoded spike trains for a 1-channel, 80-sample signal."""
    from neurosense.app.services.spike_encoder import SpikeEncoder

    enc = SpikeEncoder()
    result = enc.encode_batch(_SIGNAL_1CH_80S, _delta_config(), sampling_rate=250.0)
    assert result == snapshot


def test_spike_encoder_delta_high_threshold_snapshot(snapshot: object) -> None:
    """Pin delta-encoded output when threshold is near-max (near-zero spikes).

    EncodingConfig clamps delta_threshold to [0, 100], so 95.0 is the
    practical upper bound for the near-zero spike scenario.
    """
    from neurosense.app.services.spike_encoder import SpikeEncoder

    enc = SpikeEncoder()
    result = enc.encode_batch(_SIGNAL_2CH_50S, _delta_config(threshold=95.0), sampling_rate=250.0)
    assert result == snapshot


# ---------------------------------------------------------------------------
# 2. Temporal encoding (uses Hilbert transform — deterministic for fixed input)
# ---------------------------------------------------------------------------


def test_spike_encoder_temporal_two_channel_snapshot(snapshot: object) -> None:
    """Pin temporally-encoded spike trains for the 2-channel signal."""
    from neurosense.app.services.spike_encoder import SpikeEncoder

    enc = SpikeEncoder()
    result = enc.encode_batch(_SIGNAL_2CH_50S, _temporal_config(), sampling_rate=250.0)
    assert result == snapshot


# ---------------------------------------------------------------------------
# 3. Rate encoding — seeded RNG for reproducibility
# ---------------------------------------------------------------------------


def test_spike_encoder_rate_seeded_snapshot(snapshot: object) -> None:
    """Pin rate-encoded spike trains with a fixed RNG seed."""
    from neurosense.app.services.spike_encoder import SpikeEncoder

    enc = SpikeEncoder()
    # configure() accepts a seed to fix the internal numpy RNG
    enc.configure(_rate_config(), sampling_rate=250.0, seed=42)
    data = np.array(_SIGNAL_2CH_50S, dtype=np.float64)
    result = enc.encode(data)
    assert result == snapshot
