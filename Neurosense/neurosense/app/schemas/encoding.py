from __future__ import annotations

from collections.abc import Mapping
from typing import Any, Literal, cast

from neurosense.contracts.encoding_contracts import EncodingConfig

EncodingMethod = Literal["rate", "temporal", "delta"]


def build_encoding_config(
    method: EncodingMethod,
    *,
    refractory_period: float = 0.001,
    temporal_resolution: float = 0.001,
    rate_max_hz: float | None = None,
    temporal_phase_bins: int | None = None,
    delta_threshold: float | None = None,
) -> EncodingConfig:
    """Build an EncodingConfig with stable method-specific defaults."""
    resolved_rate_max_hz = rate_max_hz
    resolved_temporal_phase_bins = temporal_phase_bins
    resolved_delta_threshold = delta_threshold

    if method == "rate" and resolved_rate_max_hz is None:
        resolved_rate_max_hz = 200.0
    if method == "temporal" and resolved_temporal_phase_bins is None:
        resolved_temporal_phase_bins = 8
    if method == "delta" and resolved_delta_threshold is None:
        resolved_delta_threshold = 10.0

    return EncodingConfig(
        method=method,
        refractory_period=refractory_period,
        temporal_resolution=temporal_resolution,
        rate_max_hz=resolved_rate_max_hz,
        temporal_phase_bins=resolved_temporal_phase_bins,
        delta_threshold=resolved_delta_threshold,
    )


def encoding_config_from_mapping(
    payload: Mapping[str, Any] | None,
    *,
    default_method: EncodingMethod = "rate",
) -> EncodingConfig:
    """Normalize persisted metadata into a valid EncodingConfig."""
    raw = dict(payload or {})
    method_value = raw.get("method", default_method)
    method: EncodingMethod
    if method_value in {"rate", "temporal", "delta"}:
        method = cast(EncodingMethod, method_value)
    else:
        method = default_method

    return build_encoding_config(
        method,
        refractory_period=float(raw.get("refractory_period", 0.001)),
        temporal_resolution=float(raw.get("temporal_resolution", 0.001)),
        rate_max_hz=float(raw["rate_max_hz"]) if raw.get("rate_max_hz") is not None else None,
        temporal_phase_bins=(
            int(raw["temporal_phase_bins"]) if raw.get("temporal_phase_bins") is not None else None
        ),
        delta_threshold=(
            float(raw["delta_threshold"]) if raw.get("delta_threshold") is not None else None
        ),
    )


# Re-exporting for compatibility if needed, but the application should prefer the contracts
__all__ = [
    "EncodingConfig",
    "EncodingMethod",
    "build_encoding_config",
    "encoding_config_from_mapping",
]
