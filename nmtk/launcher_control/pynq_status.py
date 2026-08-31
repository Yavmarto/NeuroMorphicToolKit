"""Pure PYNQ board status mapping and wire serialization."""

from __future__ import annotations

from collections.abc import Mapping
from typing import Any

from .config import MODULES_MANIFEST
from .pynq_preflight import evaluate_pynq_preflight
from .runtime_contracts import load_neurochip_launcher_runtime_contract
from .state_contracts import PynqBoardRecord, PynqBoardState


def _default_runtime_api_url(host: str, port: int | None = None) -> str:
    """Return the manifest-defined PYNQ runtime URL for a board host."""
    resolved_port = port
    if resolved_port is None:
        resolved_port = load_neurochip_launcher_runtime_contract(
            MODULES_MANIFEST
        ).pynq.runtime_port
    return f"http://{host}:{resolved_port}"


def _effective_runtime_api_url(
    host: str,
    runtime_api_url_override: str,
    runtime_port: int,
) -> str:
    """Resolve the public runtime URL while preserving explicit overrides."""
    normalized_override = str(runtime_api_url_override or "").strip()
    if normalized_override:
        return normalized_override
    normalized_host = host.strip()
    return (
        _default_runtime_api_url(normalized_host, runtime_port)
        if normalized_host
        else ""
    )


def serialize_pynq_board(board: Mapping[str, Any]) -> dict[str, Any]:
    """Return the stable launcher wire record without persisted credentials."""
    payload = dict(board)
    payload["runtimeApiUrlOverride"] = str(
        payload.get("runtimeApiUrlOverride") or ""
    ).strip()
    runtime_port = load_neurochip_launcher_runtime_contract(
        MODULES_MANIFEST
    ).pynq.runtime_port
    payload["runtimeApiUrl"] = _effective_runtime_api_url(
        str(payload.get("host") or "").strip(),
        str(payload.get("runtimeApiUrlOverride") or "").strip(),
        runtime_port,
    )
    payload.pop("password", None)
    payload["hasPassword"] = bool(board.get("password"))
    return payload


def preflight_board_fields(
    preflight: dict[str, Any],
    *,
    fallback_error_state: PynqBoardState = "error",
) -> PynqBoardRecord:
    """Map runtime preflight evidence to fields safe to persist on a board."""
    evaluation = evaluate_pynq_preflight(
        preflight,
        fallback_error_state=fallback_error_state,
    )
    fields: PynqBoardRecord = {
        "state": evaluation.state,
        "lastPreflightStatus": evaluation.status,
        "lastPreflightMessage": evaluation.message,
        "lastRuntimeMode": evaluation.runtime_mode,
    }
    if evaluation.overlay_version:
        fields["overlayVersion"] = evaluation.overlay_version
    return fields


def runtime_status_board_fields(status: dict[str, Any]) -> PynqBoardRecord:
    """Map one runtime status response to the persisted status snapshot."""
    return {
        "lastStatus": status,
        "lastRuntimeMode": str(status.get("runtime_mode") or "").strip(),
    }


# Compatibility name retained for one release while internal imports migrate.
_serialize_pynq_board = serialize_pynq_board


__all__ = [
    "preflight_board_fields",
    "runtime_status_board_fields",
    "serialize_pynq_board",
]
