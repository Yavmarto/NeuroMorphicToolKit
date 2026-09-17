"""Settings-backed persistence boundary for paired PYNQ boards."""

from __future__ import annotations

from collections.abc import Callable, Mapping, MutableMapping
from contextlib import AbstractContextManager
from typing import Any, cast

from .hardware_models import _normalize_pynq_board
from .pynq_status import serialize_pynq_board
from .state_contracts import LauncherSettingsRecord, PynqBoardRecord


class PynqBoardRepository:
    """Own paired-board CRUD without changing the launcher settings layout."""

    def __init__(
        self,
        *,
        settings: LauncherSettingsRecord,
        lock: AbstractContextManager[Any],
        persist: Callable[[], None],
    ) -> None:
        self._settings = settings
        self._lock = lock
        self._persist = persist

    def list(self) -> list[dict[str, Any]]:
        """Return serialized board records with secrets removed."""
        with self._lock:
            return [
                serialize_pynq_board(board) for board in self._settings["pynqBoards"]
            ]

    def get_serialized(self, board_id: str) -> dict[str, Any]:
        """Return one serialized board record."""
        with self._lock:
            return dict(serialize_pynq_board(self.get(board_id)))

    def create(self, payload: dict[str, Any]) -> dict[str, Any]:
        """Normalize, persist, and serialize a new board."""
        board = _normalize_pynq_board(payload)
        if not board["host"]:
            raise ValueError("PYNQ board host is required")
        with self._lock:
            boards = self._settings["pynqBoards"]
            if any(existing["id"] == board["id"] for existing in boards):
                raise ValueError(f"PYNQ board '{board['id']}' already exists")
            if board.get("isDefault"):
                for existing in boards:
                    existing["isDefault"] = False
            boards.append(board)
            if not self._settings.get("selectedPynqBoardId"):
                self._settings["selectedPynqBoardId"] = board["id"]
            self._persist()
            return dict(serialize_pynq_board(board))

    def update(self, board_id: str, payload: dict[str, Any]) -> dict[str, Any]:
        """Merge and persist user-provided board fields."""
        with self._lock:
            board = self.get(board_id)
            normalized = self.normalize_update(board, {"id": board_id, **payload})
            if normalized.get("isDefault"):
                for existing in self._settings["pynqBoards"]:
                    if existing["id"] != board_id:
                        existing["isDefault"] = False
            mutable_board = self._mutable_record(board)
            mutable_board.clear()
            mutable_board.update(normalized)
            self._persist()
            return dict(serialize_pynq_board(board))

    def delete(self, board_id: str) -> None:
        """Delete one board and repair the selected-board pointer."""
        with self._lock:
            boards = self._settings["pynqBoards"]
            next_boards = [board for board in boards if board["id"] != board_id]
            if len(next_boards) == len(boards):
                raise KeyError(f"Unknown PYNQ board '{board_id}'")
            self._settings["pynqBoards"] = next_boards
            if self._settings.get("selectedPynqBoardId") == board_id:
                self._settings["selectedPynqBoardId"] = (
                    next_boards[0]["id"] if next_boards else None
                )
            self._persist()

    def get(self, board_id: str) -> PynqBoardRecord:
        """Return the mutable internal record owned by launcher settings."""
        for board in self._settings["pynqBoards"]:
            if board["id"] == board_id:
                return board
        raise KeyError(f"Unknown PYNQ board '{board_id}'")

    def update_fields(self, board_id: str, **fields: Any) -> PynqBoardRecord:
        """Persist trusted coordinator fields and return an isolated copy."""
        with self._lock:
            board = self.get(board_id)
            normalized = self.normalize_update(board, {"id": board_id, **fields})
            mutable_board = self._mutable_record(board)
            mutable_board.clear()
            mutable_board.update(normalized)
            self._persist()
            return PynqBoardRecord(**board)

    @staticmethod
    def normalize_update(
        board: Mapping[str, Any],
        updates: dict[str, Any],
    ) -> PynqBoardRecord:
        """Apply compatibility merge rules before normalizing a board record."""
        merged: dict[str, Any] = dict(board)
        merged.update(updates)
        if (
            "runtimeApiUrlOverride" not in updates
            and "runtimeApiUrl" not in updates
            and not str(board.get("runtimeApiUrlOverride") or "").strip()
        ):
            merged.pop("runtimeApiUrl", None)
        return _normalize_pynq_board(merged)

    @staticmethod
    def _mutable_record(board: PynqBoardRecord) -> MutableMapping[str, Any]:
        # TypedDict models key shape but typeshed does not expose dict.clear();
        # persisted board records are ordinary mutable dictionaries at runtime.
        return cast(MutableMapping[str, Any], board)


__all__ = ["PynqBoardRepository"]
