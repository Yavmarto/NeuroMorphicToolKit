"""PYNQ runtime request orchestration separated from launcher state."""

from __future__ import annotations

from typing import Any, Protocol

from .hardware_models import _resolve_pynq_run_timeout


class PynqRuntimeProxyOwnerProtocol(Protocol):
    """State compatibility surface required by runtime proxy orchestration."""

    def _get_pynq_board(self, board_id: str) -> dict[str, Any]: ...

    def _runtime_json_request(
        self,
        board: dict[str, Any],
        method: str,
        path: str,
        payload: dict[str, Any] | None = None,
        *,
        timeout: float = 15.0,
    ) -> dict[str, Any]: ...


class PynqRuntimeProxyService:
    """Forward deployment and execution requests to one paired board."""

    def __init__(self, owner: PynqRuntimeProxyOwnerProtocol) -> None:
        self._owner = owner

    def deploy(self, board_id: str, payload: dict[str, Any]) -> dict[str, Any]:
        board = self._owner._get_pynq_board(board_id)
        return self._owner._runtime_json_request(
            board, "POST", "/hardware/pynq/deploy", payload, timeout=120.0
        )

    def verify(self, board_id: str, payload: dict[str, Any]) -> dict[str, Any]:
        board = self._owner._get_pynq_board(board_id)
        return self._owner._runtime_json_request(
            board, "POST", "/hardware/pynq/verify", payload
        )

    def run(self, board_id: str, payload: dict[str, Any]) -> dict[str, Any]:
        board = self._owner._get_pynq_board(board_id)
        return self._owner._runtime_json_request(
            board,
            "POST",
            "/hardware/pynq/run",
            payload,
            timeout=_resolve_pynq_run_timeout(),
        )

    def status(self, board_id: str) -> dict[str, Any]:
        board = self._owner._get_pynq_board(board_id)
        return self._owner._runtime_json_request(board, "GET", "/hardware/pynq/status")


__all__ = ["PynqRuntimeProxyOwnerProtocol", "PynqRuntimeProxyService"]
