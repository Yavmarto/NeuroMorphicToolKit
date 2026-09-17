from __future__ import annotations

from typing import cast

import numpy as np
import numpy.typing as npt
from hypothesis import HealthCheck, given, settings
from hypothesis import strategies as st

from neurosense.app.schemas.encoding import EncodingMethod, build_encoding_config
from neurosense.app.services.spike_encoder import SpikeEncoder
from neurosense.contracts.encoding_contracts import EncodingConfig


@st.composite
def encoding_test_data(
    draw: st.DrawFn,
) -> tuple[EncodingConfig, float, npt.NDArray[np.float64]]:
    method = cast(EncodingMethod, draw(st.sampled_from(["rate", "temporal", "delta"])))
    config = build_encoding_config(
        method,
        rate_max_hz=draw(st.floats(min_value=1, max_value=1000)) if method == "rate" else None,
        temporal_phase_bins=(
            draw(st.integers(min_value=2, max_value=32)) if method == "temporal" else None
        ),
        delta_threshold=(
            draw(st.floats(min_value=0.01, max_value=100.0)) if method == "delta" else None
        ),
        refractory_period=draw(st.floats(min_value=0.001, max_value=0.1)),
        temporal_resolution=0.001,
    )

    sampling_rate = draw(st.floats(min_value=1000, max_value=10000))
    channels = draw(st.integers(min_value=1, max_value=8))
    samples = draw(st.integers(min_value=100, max_value=500))

    # Generate data manually instead of using st.arrays if not available or just to be safe
    data_list = []
    for _ in range(channels):
        channel_data = draw(
            st.lists(
                st.floats(min_value=-1000, max_value=1000, allow_nan=False, allow_infinity=False),
                min_size=samples,
                max_size=samples,
            )
        )
        data_list.append(channel_data)

    data = np.array(data_list, dtype=np.float64)

    return config, sampling_rate, data


@settings(max_examples=200, deadline=None, suppress_health_check=[HealthCheck.data_too_large])
@given(test_data=encoding_test_data())
def test_spike_ordering_preservation(
    test_data: tuple[EncodingConfig, float, npt.NDArray[np.float64]],
) -> None:
    """
    NSE-S2: Spike ordering always preserved through encoding pipeline.
    Verify that for any generated signal and EncodingConfig,
    the resulting spike_trains are strictly non-decreasing.
    """
    config, sampling_rate, data = test_data

    encoder = SpikeEncoder()
    encoder.configure(config, sampling_rate=sampling_rate)

    result = encoder.encode(data)
    spike_trains = result["spike_trains"]

    for ch_spikes in spike_trains:
        # Check if spikes are in non-decreasing order
        ch_spikes_arr = np.array(ch_spikes)
        if len(ch_spikes_arr) > 1:
            # We use >= because multiple spikes could technically happen
            # at the same time if the encoder allows it.
            diffs = np.diff(ch_spikes_arr)
            assert np.all(diffs >= 0), f"Spikes out of order in channel! {ch_spikes}"


@settings(max_examples=200, deadline=None, suppress_health_check=[HealthCheck.data_too_large])
@given(test_data=encoding_test_data())
def test_refractory_period_violation(
    test_data: tuple[EncodingConfig, float, npt.NDArray[np.float64]],
) -> None:
    """
    NSE-S3: Spikes should respect the refractory period.
    All methods (rate, temporal, delta) are now updated to respect it.
    """
    config, sampling_rate, data = test_data

    encoder = SpikeEncoder()
    encoder.configure(config, sampling_rate=sampling_rate)

    result = encoder.encode(data)
    spike_trains = result["spike_trains"]

    for ch_spikes in spike_trains:
        ch_spikes_arr = np.array(ch_spikes)
        if len(ch_spikes_arr) > 1:
            diffs = np.diff(ch_spikes_arr)
            # Refractory period is in seconds
            # Use a small epsilon for float comparison
            assert np.all(
                diffs >= config.refractory_period - 1e-9
            ), f"Refractory period violation! Diff: {diffs.min()}, Refractory: {config.refractory_period}"


@settings(max_examples=200, deadline=None, suppress_health_check=[HealthCheck.data_too_large])
@given(test_data=encoding_test_data())
def test_encoding_determinism(
    test_data: tuple[EncodingConfig, float, npt.NDArray[np.float64]],
) -> None:
    """
    NSE-S4: Encoding should be deterministic for the same input and config.
    """
    config, sampling_rate, data = test_data

    encoder1 = SpikeEncoder()
    encoder1.configure(config, sampling_rate=sampling_rate)

    encoder2 = SpikeEncoder()
    encoder2.configure(config, sampling_rate=sampling_rate)

    if config.method == "rate":
        # Rate encoding is stochastic, so we must fix the seed to test determinism
        encoder1.configure(config, sampling_rate=sampling_rate, seed=42)
        result1 = encoder1.encode(data)
        encoder2.configure(config, sampling_rate=sampling_rate, seed=42)
        result2 = encoder2.encode(data)
    else:
        result1 = encoder1.encode(data)
        result2 = encoder2.encode(data)

    assert result1["method"] == result2["method"]
    assert len(result1["spike_trains"]) == len(result2["spike_trains"])

    for st1, st2 in zip(result1["spike_trains"], result2["spike_trains"], strict=True):
        assert np.allclose(st1, st2), f"Non-deterministic encoding in channel! {st1} vs {st2}"
