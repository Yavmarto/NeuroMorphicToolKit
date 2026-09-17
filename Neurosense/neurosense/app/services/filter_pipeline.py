"""
Signal filtering service using scipy.signal for bandpass, notch,
and artifact rejection processing.
"""

from __future__ import annotations

import importlib
import logging
import time
from typing import Any, cast

import numpy as np

from ..schemas.presets import FilterConfig

logger = logging.getLogger(__name__)


def _load_scipy_signal() -> Any | None:
    """Load scipy.signal lazily so type checking does not require stubs."""
    try:
        return cast(Any, importlib.import_module("scipy.signal"))
    except ImportError:
        return None


class FilterPipeline:
    """Applies configurable filter chain to raw biosignal data."""

    def __init__(self) -> None:
        self._config: FilterConfig | None = None
        self._sampling_rate: float = 250.0
        # Cached filter coefficients
        self._bp_sos: np.ndarray[Any, Any] | None = None
        self._notch_b: np.ndarray[Any, Any] | None = None
        self._notch_a: np.ndarray[Any, Any] | None = None

    def configure(self, config: FilterConfig, sampling_rate: float) -> None:
        """Set the filter configuration and precompute coefficients."""
        self._config = config
        self._sampling_rate = sampling_rate
        self._bp_sos = None
        self._notch_b = None
        self._notch_a = None

        scipy_signal = _load_scipy_signal()
        if scipy_signal is not None:
            butter = scipy_signal.butter
            iirnotch = scipy_signal.iirnotch

            # Bandpass filter (second-order sections for stability)
            if config.bandpass_low_hz is not None and config.bandpass_high_hz is not None:
                nyq = sampling_rate / 2.0
                low = config.bandpass_low_hz / nyq
                high = config.bandpass_high_hz / nyq
                # Clamp to valid range
                low = max(low, 1e-5)
                high = min(high, 1.0 - 1e-5)
                if low < high:
                    self._bp_sos = butter(4, [low, high], btype="band", output="sos")
            elif config.bandpass_high_hz is not None:
                # Low-pass only (DC-coupled)
                nyq = sampling_rate / 2.0
                high = min(config.bandpass_high_hz / nyq, 1.0 - 1e-5)
                self._bp_sos = butter(4, high, btype="low", output="sos")
            elif config.bandpass_low_hz is not None:
                nyq = sampling_rate / 2.0
                low = max(config.bandpass_low_hz / nyq, 1e-5)
                self._bp_sos = butter(4, low, btype="high", output="sos")

            # Notch filter
            if config.notch_hz is not None:
                quality_factor = 30.0
                self._notch_b, self._notch_a = iirnotch(
                    config.notch_hz, quality_factor, sampling_rate
                )

    def apply(self, data: np.ndarray[Any, Any]) -> np.ndarray[Any, Any]:
        """Apply the configured filter chain to a (channels x samples) array.

        Enforces the following order:
        1. Bandpass / Lowpass / Highpass
        2. Notch (50/60 Hz)
        3. Artifact Rejection (amplitude-based)

        If scipy is not available or no filter is configured, returns
        the input data unchanged.
        """
        if self._config is None or data.size == 0:
            return data

        start_time_total = time.perf_counter()
        timings: dict[str, float] = {}

        scipy_signal = _load_scipy_signal()
        if scipy_signal is not None:
            lfilter = scipy_signal.lfilter
            sosfilt = scipy_signal.sosfilt

            # 0. Sanitize input (handle NaN/Inf)
            filtered: Any = self._sanitize(data)

            # 1. Apply bandpass / lowpass / highpass
            if self._bp_sos is not None:
                start_time = time.perf_counter()
                filtered = sosfilt(self._bp_sos, filtered, axis=-1)
                timings["bandpass_ms"] = round((time.perf_counter() - start_time) * 1000, 3)

            # 2. Apply notch filter
            if self._notch_b is not None and self._notch_a is not None:
                start_time = time.perf_counter()
                filtered = lfilter(self._notch_b, self._notch_a, filtered, axis=-1)
                timings["notch_ms"] = round((time.perf_counter() - start_time) * 1000, 3)

            # 3. Apply artifact rejection (amplitude-based)
            if self._config.artifact_rejection:
                start_time = time.perf_counter()
                filtered = self._reject_artifacts(filtered)
                timings["artifact_rejection_ms"] = round(
                    (time.perf_counter() - start_time) * 1000, 3
                )

            total_duration_ms = round((time.perf_counter() - start_time_total) * 1000, 3)
            logger.debug(
                f"Filter pipeline applied in {total_duration_ms}ms",
                extra={
                    "extra_fields": {
                        "total_duration_ms": total_duration_ms,
                        "breakdown": timings,
                        "channels": data.shape[0],
                        "samples": data.shape[1],
                    }
                },
            )

            return cast(np.ndarray[Any, Any], filtered)

        return data

    @staticmethod
    def _sanitize(data: np.ndarray[Any, Any]) -> np.ndarray[Any, Any]:
        """Replace non-finite values (NaN, Inf) with zero to prevent pipeline crash."""
        sanitized = data.copy()
        non_finite = ~np.isfinite(sanitized)
        if np.any(non_finite):
            sanitized[non_finite] = 0.0
        return sanitized

    @staticmethod
    def _reject_artifacts(
        data: np.ndarray[Any, Any], threshold_uv: float = 500.0
    ) -> np.ndarray[Any, Any]:
        """Replace samples exceeding the amplitude threshold with interpolated values.

        Uses a simple median-based replacement: samples whose absolute
        value exceeds *threshold_uv* are replaced by the channel median.
        This avoids introducing sharp transients while removing large
        movement artifacts.
        """
        # Fast check: if no artifacts in the whole batch, return early
        # This is common in clean recordings and avoids per-channel loops
        if not np.any(np.abs(data) > threshold_uv):
            return data

        cleaned: Any = data.copy()
        for ch in range(cleaned.shape[0]):
            channel = cleaned[ch]
            bad_mask = np.abs(channel) > threshold_uv
            if np.any(bad_mask):
                median_val = np.median(channel)
                # Replace artifacts with linear interpolation between good neighbours
                good_indices = np.where(~bad_mask)[0]
                bad_indices = np.where(bad_mask)[0]
                if len(good_indices) >= 2:
                    channel[bad_indices] = np.interp(
                        bad_indices, good_indices, channel[good_indices]
                    )
                else:
                    channel[bad_mask] = median_val
        return cast(np.ndarray[Any, Any], cleaned)

    def apply_single_channel(self, samples: np.ndarray[Any, Any]) -> np.ndarray[Any, Any]:
        """Convenience method to filter a single 1-D array."""
        reshaped = samples.reshape(1, -1)
        # Type ignore is necessary because mypy doesn't correctly track the type
        # after indexing into the result of self.apply()
        result = self.apply(reshaped)[0]
        return cast(np.ndarray[Any, Any], result)


# ---------------------------------------------------------------------------
# Module-level singleton
# ---------------------------------------------------------------------------
filter_pipeline = FilterPipeline()
