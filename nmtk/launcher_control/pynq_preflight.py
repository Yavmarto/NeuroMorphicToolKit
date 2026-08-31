"""Pure PYNQ preflight evaluation for persisted launcher readiness."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from .state_contracts import (
    PREFLIGHT_DEGRADED,
    PREFLIGHT_FAILED,
    PREFLIGHT_OK,
    PynqBoardState,
)


@dataclass(frozen=True, slots=True)
class PynqPreflightEvaluation:
    """Persistable outcome derived from one runtime preflight response."""

    state: PynqBoardState
    status: str
    message: str
    runtime_mode: str
    overlay_version: str


def evaluate_pynq_preflight(
    preflight: dict[str, Any],
    *,
    fallback_error_state: PynqBoardState = "error",
) -> PynqPreflightEvaluation:
    """Map runtime evidence to the stable launcher readiness vocabulary."""
    status = str(preflight.get("preflight_status") or "").strip().lower()
    message = str(preflight.get("preflight_message") or "").strip()
    runtime_mode = str(preflight.get("runtime_mode") or "").strip()
    overlay_assets = preflight.get("overlay_assets")
    overlay_missing = isinstance(overlay_assets, dict) and not overlay_assets.get(
        "ready_for_hardware", False
    )
    state = fallback_error_state
    if overlay_missing:
        state = "overlay_missing"
    elif status == PREFLIGHT_OK:
        state = "ready"
    elif status == PREFLIGHT_DEGRADED:
        state = "degraded_optional_capability"
    elif status == PREFLIGHT_FAILED:
        state = "preflight_failed"
    overlay_version = ""
    if isinstance(overlay_assets, dict):
        overlay_version = str(overlay_assets.get("overlay_version") or "").strip()
    return PynqPreflightEvaluation(
        state=state,
        status=status,
        message=message,
        runtime_mode=runtime_mode,
        overlay_version=overlay_version,
    )


__all__ = ["PynqPreflightEvaluation", "evaluate_pynq_preflight"]
