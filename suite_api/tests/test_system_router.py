"""`GET /api/suite/system/resources` exposes live host stats for the launcher."""

import asyncio
from typing import Any

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from suite_api.routers import system

_test_app = FastAPI()
_test_app.include_router(system.router, prefix="/api/suite")


def test_system_resources_endpoint_returns_expected_shape(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    class FakeMemory:
        total = 16_000_000_000
        used = 8_000_000_000
        percent = 50.0

    monkeypatch.setattr(system.psutil, "virtual_memory", lambda: FakeMemory())
    monkeypatch.setattr(system.psutil, "cpu_percent", lambda interval=0.1: 42.5)
    monkeypatch.setattr(system.psutil, "cpu_count", lambda logical=True: 8)
    monkeypatch.setattr(system.psutil, "boot_time", lambda: 1_000.0)
    monkeypatch.setattr(system.time, "time", lambda: 1100.0)
    monkeypatch.setattr(system.socket, "gethostname", lambda: "nmtk-host")
    monkeypatch.setattr(system.platform, "platform", lambda: "Linux-6.8-x86_64")
    monkeypatch.setattr(system, "_collect_gpu_stats", lambda: None)

    response = TestClient(_test_app).get("/api/suite/system/resources")

    assert response.status_code == 200
    payload = response.json()
    assert payload["cpu"] == {"percent": 42.5, "cores": 8}
    assert payload["memory"] == {
        "total": 16_000_000_000,
        "used": 8_000_000_000,
        "percent": 50.0,
    }
    assert payload["gpu"] is None
    assert payload["host"]["hostname"] == "nmtk-host"
    assert payload["host"]["platform"] == "Linux-6.8-x86_64"
    assert payload["host"]["uptime"] == 100.0


def test_system_resources_moves_collection_off_event_loop(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    calls: list[tuple[Any, tuple[Any, ...]]] = []

    async def tracked_to_thread(function: Any, *args: Any) -> Any:
        calls.append((function, args))
        return {
            "cpu": {"percent": 1.0, "cores": 1},
            "memory": {"total": 1, "used": 1, "percent": 1.0},
            "gpu": None,
            "host": {
                "hostname": "host",
                "platform": "test",
                "uptime": 1.0,
            },
        }

    monkeypatch.setattr(system.asyncio, "to_thread", tracked_to_thread)

    payload = asyncio.run(system.system_resources())

    assert calls == [(system._collect_resources, ())]
    assert payload["gpu"] is None
