from __future__ import annotations

import numpy as np
import numpy.typing as npt

from neurosense.app.services.quality_analyzer import QualityAnalyzer


def test_quality_analysis(sample_signal: npt.NDArray[np.float64]) -> None:
    analyzer = QualityAnalyzer()
    analyzer.set_channel_labels({0: "EMG1", 1: "EMG2"})

    result = analyzer.analyze(sample_signal, sampling_rate=250.0)

    assert len(result.channels) == sample_signal.shape[0]
    assert result.channels[0].label == "EMG1"
    assert result.channels[1].label == "EMG2"
    assert isinstance(result.channels[0].snr_db, float)
    assert result.channels[0].status in ["good", "marginal", "unusable"]


def test_analyze_with_impedance(sample_signal: npt.NDArray[np.float64]) -> None:
    analyzer = QualityAnalyzer()
    impedance_values = {0: 10.0, 1: 150.0}  # 150kOhm should be unusable/marginal

    result = analyzer.analyze(sample_signal, impedance_values=impedance_values)

    assert result.channels[0].impedance_kohm == 10.0
    assert result.channels[1].impedance_kohm == 150.0
    # Channel with 150kOhm impedance should be unusable or marginal
    assert result.channels[1].status in ["marginal", "unusable"]
    assert result.channels[1].suggestion is not None


def test_estimate_snr() -> None:
    analyzer = QualityAnalyzer()
    rng = np.random.default_rng()
    # High SNR: Clean sine wave
    t_val = np.linspace(0, 1, 250)
    clean_signal = np.sin(2 * np.pi * 10 * t_val)
    snr_clean = analyzer._estimate_snr(clean_signal)

    # Low SNR: Noisy signal
    noisy_signal = clean_signal + 5 * rng.standard_normal(250)
    snr_noisy = analyzer._estimate_snr(noisy_signal)

    assert snr_clean > snr_noisy


def test_estimate_noise_floor() -> None:
    analyzer = QualityAnalyzer()
    rng = np.random.default_rng()
    _ = np.linspace(0, 1, 250)
    # Low noise
    low_noise = 0.01 * rng.standard_normal(250)
    nf_low = analyzer._estimate_noise_floor(low_noise, 250.0)

    # High noise
    high_noise = 1.0 * rng.standard_normal(250)
    nf_high = analyzer._estimate_noise_floor(high_noise, 250.0)

    assert nf_high > nf_low


def test_estimate_power_line() -> None:
    analyzer = QualityAnalyzer()
    fs = 250.0
    t = np.linspace(0, 1, int(fs))
    # Signal with 50Hz interference
    signal_50hz = np.sin(2 * np.pi * 50 * t)
    pli_high = analyzer._estimate_power_line(signal_50hz, fs)

    # Signal with 10Hz only
    signal_10hz = np.sin(2 * np.pi * 10 * t)
    pli_low = analyzer._estimate_power_line(signal_10hz, fs)

    assert pli_high > pli_low


def test_artifact_detection() -> None:
    analyzer = QualityAnalyzer()
    # Clean signal
    clean = np.zeros((1, 100))
    res_clean = analyzer.analyze(clean)
    assert res_clean.channels[0].artifact_detected is False

    # Large artifact
    noisy = np.zeros((1, 100))
    noisy[0, 50] = 1000.0
    res_noisy = analyzer.analyze(noisy)
    assert res_noisy.channels[0].artifact_detected is True

    # NaN artifact
    nan_signal = np.zeros((1, 100))
    nan_signal[0, 50] = np.nan
    res_nan = analyzer.analyze(nan_signal)
    assert res_nan.channels[0].artifact_detected is True


def test_quality_score() -> None:
    analyzer = QualityAnalyzer()
    # Excellent signal: high SNR (20dB), low PLI (0dB), low noise floor (2uV)
    score_best = analyzer._calculate_quality_score(20.0, 0.0, 2.0)
    assert score_best == 1.0

    # Poor signal: low SNR (0dB), high PLI (30dB), high noise floor (50uV)
    score_worst = analyzer._calculate_quality_score(0.0, 30.0, 50.0)
    assert score_worst == 0.0

    # Intermediate score
    score_mid = analyzer._calculate_quality_score(10.0, 15.0, 10.0)
    assert 0 < score_mid < 1.0
