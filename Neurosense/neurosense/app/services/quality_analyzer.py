"""
Signal quality analysis service -- computes SNR, noise floor,
impedance estimates, and power line interference metrics per channel.
"""

from __future__ import annotations

from typing import Any, Literal

import numpy as np

from ..schemas.quality import ChannelQuality, SignalQuality


class QualityAnalyzer:
    """Computes real-time signal quality metrics for connected devices."""

    def __init__(self) -> None:
        self._channel_labels: dict[int, str] = {}

    def set_channel_labels(self, mapping: dict[int, str]) -> None:
        self._channel_labels = mapping

    def analyze(
        self,
        data: np.ndarray[Any, Any],
        sampling_rate: float = 250.0,
        impedance_values: dict[int, float] | None = None,
    ) -> SignalQuality:
        """Analyze signal quality for a (channels x samples) data array.

        Returns a SignalQuality object with per-channel metrics.
        """
        channels: list[ChannelQuality] = []

        for ch in range(data.shape[0]):
            signal = data[ch]
            label = self._channel_labels.get(ch, f"Ch{ch}")

            # SNR estimation (signal power / noise power)
            snr_db = self._estimate_snr(signal)

            # Noise floor (RMS of high-frequency content)
            noise_floor = self._estimate_noise_floor(signal, sampling_rate)

            # Power line interference (50/60 Hz)
            pli_db = self._estimate_power_line(signal, sampling_rate)

            # Artifact detection (amplitude thresholding and non-finite check)
            artifact_detected = bool(
                not np.all(np.isfinite(signal)) or np.any(np.abs(signal) > 500.0)
            )

            # Impedance from external measurement
            impedance = None
            if impedance_values and ch in impedance_values:
                impedance = impedance_values[ch]

            # Overall quality score
            quality_score = self._calculate_quality_score(snr_db, pli_db, noise_floor)

            # Status classification
            status, suggestion = self._classify(snr_db, noise_floor, pli_db, impedance)

            channels.append(
                ChannelQuality(
                    channel=ch,
                    label=label,
                    snr_db=round(snr_db, 1),
                    noise_floor_uv_rms=round(noise_floor, 2),
                    impedance_kohm=impedance,
                    power_line_interference_db=round(pli_db, 1),
                    artifact_detected=artifact_detected,
                    signal_quality_score=round(quality_score, 2),
                    status=status,
                    suggestion=suggestion,
                )
            )

        return SignalQuality(channels=channels)

    # ------------------------------------------------------------------
    # Private helpers
    # ------------------------------------------------------------------

    @staticmethod
    def _estimate_snr(signal: np.ndarray[Any, Any]) -> float:
        """Estimate SNR in dB using signal variance vs high-freq noise."""
        if len(signal) < 10 or not np.all(np.isfinite(signal)):
            return 0.0
        signal_power = np.var(signal)
        # Estimate noise as variance of first-order difference
        diffs = np.diff(signal)
        if len(diffs) == 0:
            return 0.0
        noise_power = np.var(diffs) / 2.0
        if noise_power < 1e-12:
            return 60.0  # Effectively infinite SNR
        if signal_power < 1e-12:
            return -20.0  # No signal, just noise floor
        return float(10 * np.log10(max(signal_power / noise_power, 1e-12)))

    @staticmethod
    def _calculate_quality_score(snr_db: float, pli_db: float, noise_floor: float) -> float:
        """Calculate a composite quality score from 0.0 to 1.0."""
        # SNR component: 0dB -> 0, 20dB -> 1.0
        snr_score = np.clip(snr_db / 20.0, 0, 1)
        # PLI component: 30dB -> 0, 0dB -> 1.0
        pli_score = np.clip(1.0 - (pli_db / 30.0), 0, 1)
        # Noise floor component: 50uV -> 0, 2uV -> 1.0
        nf_score = np.clip(1.0 - (noise_floor - 2.0) / 48.0, 0, 1)

        return float(0.5 * snr_score + 0.3 * pli_score + 0.2 * nf_score)

    @staticmethod
    def _estimate_noise_floor(signal: np.ndarray[Any, Any], sampling_rate: float) -> float:
        """Estimate noise floor in uV RMS from high-frequency content."""
        if len(signal) < 10:
            return 0.0
        # Use RMS of the signal's high-frequency component (diff approximation)
        noise = np.diff(signal)
        return float(np.sqrt(np.mean(noise**2)))

    @staticmethod
    def _estimate_power_line(signal: np.ndarray[Any, Any], sampling_rate: float) -> float:
        """Estimate power line interference level in dB at 50 Hz."""
        if len(signal) < 64:
            return -60.0
        try:
            fft = np.fft.rfft(signal)
            freqs = np.fft.rfftfreq(len(signal), 1.0 / sampling_rate)
            magnitudes = np.abs(fft)

            # Find power at 50 Hz (+/- 2 Hz)
            mask_50 = (freqs >= 48) & (freqs <= 52)
            if not mask_50.any():
                return -60.0
            power_50 = np.max(magnitudes[mask_50])

            # Compare to median power
            median_power = np.median(magnitudes)
            if median_power < 1e-12:
                return 0.0
            return float(20 * np.log10(max(power_50 / median_power, 1e-12)))
        except Exception:
            return -60.0

    @staticmethod
    def _classify(
        snr_db: float,
        noise_floor: float,
        pli_db: float,
        impedance: float | None,
    ) -> tuple[Literal["good", "marginal", "unusable"], str | None]:
        """Classify channel as good/marginal/unusable with suggestion."""
        suggestions = []

        if snr_db < 5:
            suggestions.append("Very low SNR -- check electrode contact and cable shielding")
        elif snr_db < 10:
            suggestions.append("Low SNR -- reapply electrode gel or press electrode firmly")

        if pli_db > 20:
            suggestions.append("Strong power line interference detected -- enable notch filter")

        if impedance is not None and impedance > 50:
            suggestions.append(
                f"High impedance ({impedance:.0f} kOhm) -- clean skin and reapply electrode"
            )

        if snr_db < 5 or (impedance is not None and impedance > 100):
            return "unusable", "; ".join(suggestions) if suggestions else "Signal unusable"
        if snr_db < 10 or pli_db > 20 or (impedance is not None and impedance > 50):
            return "marginal", "; ".join(suggestions) if suggestions else None
        return "good", None


# ---------------------------------------------------------------------------
# Module-level singleton
# ---------------------------------------------------------------------------
quality_analyzer = QualityAnalyzer()
