"""Property-based tests for NeuroSense signal processing contracts.

To run:
    pytest properties/ -v --hypothesis-seed=0
"""

from __future__ import annotations

import pytest
from hypothesis import given
from hypothesis import strategies as st

import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "contracts"))

from signal_contracts import (
    EncodingConfigContract,
    DeviceContract,
    DisplayLatencyContract,
    PipelineLatencyContract,
    ApplicationPresetContract,
    SignalQualityContract,
)


class TestEncodingProperties:

    @given(method=st.sampled_from(["rate", "temporal", "delta"]))
    def test_all_encoding_methods_accepted(self, method: str):
        """PROPERTY: All three encoding methods are valid."""
        EncodingConfigContract(method=method)

    @given(rate=st.floats(min_value=-100.0, max_value=0.0))
    def test_zero_or_negative_rate_rejected(self, rate: float):
        """PROPERTY: rate_max_hz <= 0 is rejected."""
        with pytest.raises(Exception):
            EncodingConfigContract(method="rate", rate_max_hz=rate)


class TestDeviceProperties:

    @given(n_ch=st.integers(min_value=1, max_value=8))
    def test_valid_channel_count_accepted(self, n_ch: int):
        """PROPERTY: 1-8 channels is valid for all devices."""
        DeviceContract(
            device_type="openbci_ganglion",
            n_channels=n_ch,
            sample_rate_hz=200,
        )

    @given(n_ch=st.integers(min_value=9, max_value=100))
    def test_over_8_channels_rejected(self, n_ch: int):
        """PROPERTY: > 8 channels is rejected (NSe-SA1 limit)."""
        with pytest.raises(Exception):
            DeviceContract(
                device_type="openbci_ganglion",
                n_channels=n_ch,
                sample_rate_hz=200,
            )


class TestLatencyProperties:

    @given(lat=st.floats(min_value=0.0, max_value=50.0))
    def test_display_under_50ms_accepted(self, lat: float):
        """PROPERTY: Display latency <= 50ms is accepted."""
        DisplayLatencyContract(acquisition_to_display_ms=lat)

    @given(lat=st.floats(min_value=50.1, max_value=1000.0))
    def test_display_over_50ms_rejected(self, lat: float):
        """PROPERTY: Display latency > 50ms violates NSe-SA1."""
        with pytest.raises(Exception):
            DisplayLatencyContract(acquisition_to_display_ms=lat)

    @given(lat=st.floats(min_value=0.0, max_value=100.0))
    def test_pipeline_under_100ms_accepted(self, lat: float):
        """PROPERTY: Pipeline latency <= 100ms is accepted."""
        PipelineLatencyContract(end_to_end_ms=lat)


class TestPresetProperties:

    @given(
        low=st.floats(min_value=0.1, max_value=50.0),
        high=st.floats(min_value=51.0, max_value=500.0),
    )
    def test_valid_bandpass_accepted(self, low: float, high: float):
        """PROPERTY: Any bandpass with low < high is valid."""
        ApplicationPresetContract(
            name="test",
            filter_bandpass_low_hz=low,
            filter_bandpass_high_hz=high,
            encoding_method="rate",
            channel_mapping={"ch0": 0},
        )

    @given(freq=st.floats(min_value=1.0, max_value=100.0))
    def test_equal_bandpass_rejected(self, freq: float):
        """PROPERTY: Equal low and high bandpass is rejected."""
        with pytest.raises(Exception):
            ApplicationPresetContract(
                name="test",
                filter_bandpass_low_hz=freq,
                filter_bandpass_high_hz=freq,
                encoding_method="rate",
                channel_mapping={"ch0": 0},
            )


class TestSignalQualityProperties:

    @given(
        snr=st.floats(min_value=21.0, max_value=60.0),
        noise=st.floats(min_value=0.1, max_value=4.9),
    )
    def test_good_quality_classification(self, snr: float, noise: float):
        """PROPERTY: High SNR + low noise = 'good' quality."""
        sq = SignalQualityContract(snr_db=snr, noise_floor_uv_rms=noise)
        assert sq.quality_level == "good"
