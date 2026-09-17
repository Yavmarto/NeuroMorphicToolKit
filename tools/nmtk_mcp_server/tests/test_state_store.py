from __future__ import annotations

import json
from pathlib import Path

import pytest

from tools.nmtk_mcp_server.state_store import (
    DeerFlowPacket,
    JsonStateStore,
    StateStoreError,
)


def test_state_store_loads_empty_default_for_missing_file(tmp_path: Path) -> None:
    store = JsonStateStore(tmp_path / "state.json")

    state = store.load()

    assert state.active_packet_id is None
    assert state.packets == {}


def test_state_store_saves_and_loads_round_trip(tmp_path: Path) -> None:
    store = JsonStateStore(tmp_path / "state.json")
    packet = DeerFlowPacket(
        packet_id="packet-1",
        title="Demo packet",
        payload={"spec": "neuron A spikes."},
    )

    state = store.upsert_packet(packet, activate=True)
    loaded = JsonStateStore(tmp_path / "state.json").load()

    assert state.active_packet_id == "packet-1"
    assert loaded.active_packet_id == "packet-1"
    assert loaded.packets["packet-1"].payload == {"spec": "neuron A spikes."}


def test_state_store_get_and_clear_active_packet(tmp_path: Path) -> None:
    store = JsonStateStore(tmp_path / "state.json")
    packet = DeerFlowPacket(packet_id="packet-1", title="Demo")
    store.upsert_packet(packet, activate=True)

    assert store.get_packet("packet-1") == packet

    state = store.clear_active_packet()

    assert state.active_packet_id is None
    assert store.load().active_packet_id is None


def test_state_store_invalid_json_raises(tmp_path: Path) -> None:
    path = tmp_path / "state.json"
    path.write_text("{bad json", encoding="utf-8")

    with pytest.raises(StateStoreError, match="Invalid JSON"):
        JsonStateStore(path).load()


def test_state_store_invalid_schema_raises(tmp_path: Path) -> None:
    path = tmp_path / "state.json"
    path.write_text(json.dumps({"packets": []}), encoding="utf-8")

    with pytest.raises(StateStoreError, match="did not match"):
        JsonStateStore(path).load()
