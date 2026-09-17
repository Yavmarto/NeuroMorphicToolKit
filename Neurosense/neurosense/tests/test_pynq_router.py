from __future__ import annotations

import json
from pathlib import Path

import httpx
import pytest

from neurosense.app.main import app
from neurosense.app.routers import pynq
from neurosense.app.schemas.runtime import PynqDeviceInfo


@pytest.mark.anyio
async def test_devices_endpoint_lists_registered_real_board(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(
        pynq,
        "load_pynq_registry",
        lambda: [{"device_id": "pynq", "address": "192.168.2.103"}],
    )

    def _fake_probe(device: dict, _timeout_s: float = pynq._PROBE_TIMEOUT_S) -> PynqDeviceInfo:
        return PynqDeviceInfo(
            device_id=str(device["device_id"]),
            ip_address="192.168.2.103",
            status="online",
            sensors=["spikes"],
        )

    monkeypatch.setattr(pynq, "_probe_node", _fake_probe)

    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.get("/api/neurosense/sense/pynq/devices")

    assert response.status_code == 200
    devices = response.json()["devices"]
    ids = [device["device_id"] for device in devices]
    assert ids == ["pynq_sim_01", "pynq"]
    real = next(device for device in devices if device["device_id"] == "pynq")
    assert real["status"] == "online"
    assert real["ip_address"] == "192.168.2.103"


def test_load_pynq_registry_from_env(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("NEUROSENSE_PYNQ_DEVICES", "pynq@192.168.2.103, edge2 ")
    monkeypatch.delenv("NEUROSENSE_PYNQ_REGISTRY", raising=False)
    nodes = pynq.load_pynq_registry()
    by_id = {node["device_id"]: node for node in nodes}
    assert set(by_id) == {"pynq", "edge2"}
    assert pynq.node_address(by_id["pynq"]) == "192.168.2.103"
    assert pynq.node_address(by_id["edge2"]) == "edge2.local"


def test_load_pynq_registry_from_file(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    registry = tmp_path / "pynq_devices.json"
    registry.write_text(
        json.dumps({"devices": [{"device_id": "pynq", "host": "pynq.local"}]}),
        encoding="utf-8",
    )
    monkeypatch.delenv("NEUROSENSE_PYNQ_DEVICES", raising=False)
    monkeypatch.setenv("NEUROSENSE_PYNQ_REGISTRY", str(registry))

    nodes = pynq.load_pynq_registry()
    assert nodes == [{"device_id": "pynq", "host": "pynq.local"}]
    assert pynq.stream_host("pynq") == "pynq.local"
    assert pynq.stream_host("unknown") == "unknown.local"


def test_probe_node_marks_offline_when_unreachable() -> None:
    info = pynq._probe_node({"device_id": "pynq", "address": "127.0.0.1"}, timeout_s=0.3)
    assert info.device_id == "pynq"
    assert info.status == "offline"
    assert info.sensors == ["spikes"]
