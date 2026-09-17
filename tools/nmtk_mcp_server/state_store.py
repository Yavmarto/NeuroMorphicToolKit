from __future__ import annotations

import json
import os
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

from pydantic import BaseModel, ConfigDict, Field


class StateStoreError(RuntimeError):
    """Raised when local MCP state cannot be loaded or saved."""


class DeerFlowPacket(BaseModel):
    model_config = ConfigDict(extra="allow")

    packet_id: str
    title: str | None = None
    payload: dict[str, Any] = Field(default_factory=dict)
    metadata: dict[str, Any] = Field(default_factory=dict)
    created_at: str = Field(default_factory=lambda: _utc_now_iso())
    updated_at: str = Field(default_factory=lambda: _utc_now_iso())


class LocalMcpState(BaseModel):
    active_packet_id: str | None = None
    packets: dict[str, DeerFlowPacket] = Field(default_factory=dict)
    metadata: dict[str, Any] = Field(default_factory=dict)


class JsonStateStore:
    def __init__(self, path: Path | str) -> None:
        self.path = Path(path)

    def load(self) -> LocalMcpState:
        if not self.path.exists():
            return LocalMcpState()

        try:
            data = json.loads(self.path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            raise StateStoreError(f"Invalid JSON in local MCP state: {self.path}") from exc
        except OSError as exc:
            raise StateStoreError(f"Could not read local MCP state: {self.path}") from exc

        try:
            return LocalMcpState.model_validate(data)
        except Exception as exc:
            raise StateStoreError(
                f"Local MCP state did not match the expected schema: {exc}"
            ) from exc

    def save(self, state: LocalMcpState) -> LocalMcpState:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        tmp_path = self.path.with_name(f"{self.path.name}.tmp")
        try:
            tmp_path.write_text(
                json.dumps(state.model_dump(mode="json"), indent=2, sort_keys=True),
                encoding="utf-8",
            )
            os.replace(tmp_path, self.path)
        except OSError as exc:
            raise StateStoreError(f"Could not write local MCP state: {self.path}") from exc
        return state

    def upsert_packet(
        self,
        packet: DeerFlowPacket,
        *,
        activate: bool = False,
    ) -> LocalMcpState:
        state = self.load()
        now = _utc_now_iso()
        existing = state.packets.get(packet.packet_id)
        if existing is not None:
            packet = packet.model_copy(
                update={"created_at": existing.created_at, "updated_at": now}
            )
        state.packets[packet.packet_id] = packet
        if activate:
            state.active_packet_id = packet.packet_id
        return self.save(state)

    def get_packet(self, packet_id: str) -> DeerFlowPacket | None:
        return self.load().packets.get(packet_id)

    def clear_active_packet(self) -> LocalMcpState:
        state = self.load()
        state.active_packet_id = None
        return self.save(state)


def _utc_now_iso() -> str:
    return datetime.now(UTC).isoformat()
