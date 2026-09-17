from __future__ import annotations

import numpy as np
import numpy.typing as npt

from neurosense.app.schemas.presets import FilterConfig
from neurosense.app.services.filter_pipeline import FilterPipeline


def test_filter_configuration(filter_config: FilterConfig) -> None:
    pipeline = FilterPipeline()
    pipeline.configure(filter_config, sampling_rate=250.0)

    assert pipeline._config == filter_config
    assert pipeline._bp_sos is not None
    assert pipeline._notch_b is not None
    assert pipeline._notch_a is not None


def test_apply_filter(sample_signal: npt.NDArray[np.float64], filter_config: FilterConfig) -> None:
    pipeline = FilterPipeline()
    pipeline.configure(filter_config, sampling_rate=250.0)

    filtered = pipeline.apply(sample_signal)

    assert filtered.shape == sample_signal.shape
    assert not np.array_equal(filtered, sample_signal)


def test_artifact_rejection(sample_signal: npt.NDArray[np.float64]) -> None:
    # Add a huge artifact to the signal
    signal_with_artifact = sample_signal.copy()
    signal_with_artifact[0, 100] = 1000.0

    config = FilterConfig(
        bandpass_low_hz=None,
        bandpass_high_hz=None,
        notch_hz=None,
        artifact_rejection=True,
    )
    pipeline = FilterPipeline()
    pipeline.configure(config, sampling_rate=250.0)

    cleaned = pipeline.apply(signal_with_artifact)

    assert abs(cleaned[0, 100]) < 1000.0
    assert cleaned.shape == sample_signal.shape


def test_unconfigured_apply(sample_signal: npt.NDArray[np.float64]) -> None:
    pipeline = FilterPipeline()
    # Should return original data if not configured
    filtered = pipeline.apply(sample_signal)
    assert np.array_equal(filtered, sample_signal)


def test_apply_single_channel(
    sample_signal: npt.NDArray[np.float64], filter_config: FilterConfig
) -> None:
    pipeline = FilterPipeline()
    pipeline.configure(filter_config, sampling_rate=250.0)

    single_ch = sample_signal[0]
    filtered = pipeline.apply_single_channel(single_ch)

    assert filtered.shape == single_ch.shape
    assert not np.array_equal(filtered, single_ch)


def test_lowpass_only_configuration() -> None:
    pipeline = FilterPipeline()
    config = FilterConfig(
        bandpass_low_hz=None, bandpass_high_hz=40.0, notch_hz=None, artifact_rejection=False
    )
    pipeline.configure(config, sampling_rate=250.0)
    assert pipeline._bp_sos is not None


def test_highpass_only_configuration() -> None:
    pipeline = FilterPipeline()
    config = FilterConfig(
        bandpass_low_hz=1.0, bandpass_high_hz=None, notch_hz=None, artifact_rejection=False
    )
    pipeline.configure(config, sampling_rate=250.0)
    assert pipeline._bp_sos is not None


def test_sanitize_nan_inf() -> None:
    pipeline = FilterPipeline()
    data = np.array([[1.0, np.nan, 3.0], [np.inf, -np.inf, 2.0]])
    sanitized = pipeline._sanitize(data)

    assert np.all(np.isfinite(sanitized))
    assert sanitized[0, 1] == 0.0
    assert sanitized[1, 0] == 0.0
    assert sanitized[1, 1] == 0.0
    assert sanitized[0, 0] == 1.0


def test_apply_empty_data() -> None:
    pipeline = FilterPipeline()
    pipeline.configure(
        FilterConfig(
            bandpass_low_hz=None,
            bandpass_high_hz=None,
            notch_hz=None,
            artifact_rejection=False,
        ),
        sampling_rate=250.0,
    )
    empty_data = np.array([[], []])
    result = pipeline.apply(empty_data)
    assert result.size == 0
    assert result.shape == (2, 0)
