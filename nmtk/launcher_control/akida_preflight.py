"""Pure Akida preflight and readiness evaluation."""

from __future__ import annotations

import re
from collections.abc import Mapping
from dataclasses import dataclass
from typing import Any

from .hardware_models import (
    _akida_hardware_runtime_ready,
    _akida_user_space_upgrade_message,
)
from .state_contracts import PREFLIGHT_DEGRADED, PREFLIGHT_OK

_RAW_DEVICE_ERROR_PATTERN = re.compile(r"\berr(?:no)?\(\d+\)|\b0x[0-9a-fA-F]{4,}\b")


@dataclass(frozen=True, slots=True)
class AkidaPreflightEvaluation:
    """Persistable outcome derived from remote readiness evidence."""

    state: str
    status: str
    message: str
    readiness_message: str
    sdk_status: str
    runtime_target: str


def readiness_message(message: str) -> str:
    """Replace raw SDK register failures with actionable operator guidance."""
    if not _RAW_DEVICE_ERROR_PATTERN.search(message):
        return message
    return (
        "The Akida board could not be reached. Switch the host fully off "
        "and on again, then re-check."
    )


def evaluate_akida_preflight(
    host: Mapping[str, Any],
    preflight: dict[str, Any],
    *,
    runtime_status: dict[str, Any] | None = None,
    install_status: dict[str, Any] | None = None,
) -> AkidaPreflightEvaluation:
    """Map remote evidence to the stable launcher readiness vocabulary."""
    status = str(preflight.get("preflight_status") or "").strip().lower()
    message = str(preflight.get("preflight_message") or "").strip()
    runtime_target = str(preflight.get("runtime_target") or "").strip()
    sdk_status = str(preflight.get("sdk_status") or "").strip()
    if (
        status == PREFLIGHT_DEGRADED
        and runtime_status is not None
        and _akida_hardware_runtime_ready(runtime_status)
    ):
        status = PREFLIGHT_OK
        message = "Akida hardware runtime is ready."
        runtime_target = str(runtime_status.get("runtime_target") or "").strip()
        sdk_status = str(runtime_status.get("sdk_status") or "").strip()
    state = "preflight_failed"
    if status == PREFLIGHT_OK:
        state = (
            "ready" if runtime_target == "hardware" else "degraded_optional_capability"
        )
    elif status == PREFLIGHT_DEGRADED:
        state = (
            "simulator_only"
            if runtime_target in {"software_fallback", "akd1000_simulator"}
            else "degraded_optional_capability"
        )
    safe_message = readiness_message(message)
    if str((install_status or {}).get("installMode") or "").strip() == "user-space":
        note = _akida_user_space_upgrade_message(str(host.get("username") or ""))
        message = " ".join(part for part in (message, note) if part)
        safe_message = " ".join(part for part in (safe_message, note) if part)
        if state == "ready":
            state = "degraded_optional_capability"
    return AkidaPreflightEvaluation(
        state=state,
        status=status,
        message=message,
        readiness_message=safe_message,
        sdk_status=sdk_status,
        runtime_target=runtime_target,
    )


__all__ = ["AkidaPreflightEvaluation", "evaluate_akida_preflight", "readiness_message"]
