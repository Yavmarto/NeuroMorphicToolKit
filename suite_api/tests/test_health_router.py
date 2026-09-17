"""`GET /api/suite/health` is the contract the in-app backend update rests on.

The launcher reads `version` from it to decide whether to offer an update, so
the field has to be present and has to fall back to something that means "not a
release" rather than to a version-shaped lie.
"""

import asyncio
import importlib
import sqlite3
from pathlib import Path
from typing import Any

import httpx
import pytest

from suite_api.routers import health


def _reload_with_version(monkeypatch: pytest.MonkeyPatch, raw: str | None) -> str:
    if raw is None:
        monkeypatch.delenv("NMTK_VERSION", raising=False)
    else:
        monkeypatch.setenv("NMTK_VERSION", raw)
    importlib.reload(health)
    return health.BACKEND_VERSION


def test_unstamped_build_reports_dev(monkeypatch: pytest.MonkeyPatch) -> None:
    assert _reload_with_version(monkeypatch, None) == "dev"


def test_release_build_reports_its_tag(monkeypatch: pytest.MonkeyPatch) -> None:
    # What .github/workflows/release-docker.yml stamps via the Dockerfile ARG.
    assert _reload_with_version(monkeypatch, "1.2.0") == "1.2.0"


def test_blank_version_falls_back_to_dev(monkeypatch: pytest.MonkeyPatch) -> None:
    # An empty build-arg must not read as a release with an empty version —
    # the launcher would then compare "" against a real tag and offer an update
    # against an unknown build.
    assert _reload_with_version(monkeypatch, "   ") == "dev"


def test_health_payload_carries_the_version(monkeypatch: pytest.MonkeyPatch) -> None:
    _reload_with_version(monkeypatch, "1.2.0")
    payload = asyncio.run(health.suite_health())
    assert payload == {
        "status": "ok",
        "service": "suite_api",
        "version": "1.2.0",
    }
    # Restore the module for any test importing it afterwards.
    _reload_with_version(monkeypatch, None)


def test_suite_doctor_checks_storage_databases_and_jupyter(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    monkeypatch.setenv("NEUROCNL_DATA_DIR", str(tmp_path))
    for name in ("datasets.db", "jobs.db"):
        with sqlite3.connect(tmp_path / name) as connection:
            connection.execute("CREATE TABLE health (id INTEGER PRIMARY KEY)")

    async def jupyter_ok(_capabilities: list[str]) -> dict[str, Any]:
        return {
            "overall": "ok",
            "checks": [
                {
                    "id": "framework-snntorch",
                    "label": "snnTorch",
                    "status": "ok",
                    "detail": "Kernel starts.",
                }
            ],
        }

    monkeypatch.setattr(health, "probe_jupyter_doctor", jupyter_ok)
    report = asyncio.run(
        health.suite_doctor(health.DoctorRequest(capabilities=["snntorch"]))
    )

    assert report.overall == health.DoctorStatus.OK
    assert {check.id for check in report.checks} >= {
        "suite-api",
        "dataset-storage",
        "suite-databases",
        "framework-snntorch",
    }
    assert list((tmp_path / "pipeline_uploads").iterdir()) == []


def test_suite_doctor_fails_when_storage_is_unwritable(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    blocked = tmp_path / "blocked"
    blocked.write_text("not a directory")
    monkeypatch.setenv("NEUROCNL_DATA_DIR", str(blocked))

    async def jupyter_ok(_capabilities: list[str]) -> dict[str, Any]:
        return {"overall": "ok", "checks": []}

    monkeypatch.setattr(health, "probe_jupyter_doctor", jupyter_ok)
    report = asyncio.run(health.suite_doctor(health.DoctorRequest()))

    storage = next(check for check in report.checks if check.id == "dataset-storage")
    assert storage.status == health.DoctorStatus.FAILED
    assert report.overall == health.DoctorStatus.FAILED


def test_suite_doctor_moves_storage_probe_off_event_loop(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    monkeypatch.setenv("NEUROCNL_DATA_DIR", str(tmp_path))
    calls: list[tuple[Any, tuple[Any, ...]]] = []

    async def tracked_to_thread(function: Any, *args: Any) -> Any:
        calls.append((function, args))
        return function(*args)

    async def jupyter_ok(_capabilities: list[str]) -> dict[str, Any]:
        return {"overall": "ok", "checks": []}

    monkeypatch.setattr(health.asyncio, "to_thread", tracked_to_thread)
    monkeypatch.setattr(health, "probe_jupyter_doctor", jupyter_ok)

    asyncio.run(health.suite_doctor(health.DoctorRequest()))

    assert calls == [(health._storage_checks, (tmp_path,))]


def test_module_health_redacts_private_response_and_transport_details(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(
        health,
        "MODULE_URLS",
        {
            "degraded": "http://10.0.0.8:8002/health",
            "offline": "http://10.0.0.9:8003/health",
        },
    )

    class FakeClient:
        def __init__(self, **_kwargs: Any) -> None:
            pass

        async def __aenter__(self) -> "FakeClient":
            return self

        async def __aexit__(self, *_args: Any) -> None:
            return None

        async def get(
            self, url: str, headers: dict[str, str] | None = None
        ) -> httpx.Response:
            if "8002" in url:
                return httpx.Response(503, text="database at /private/jobs.db failed")
            raise httpx.ConnectError("connection refused for http://10.0.0.9:8003")

    monkeypatch.setattr(health.httpx, "AsyncClient", FakeClient)

    payload = asyncio.run(health.modules_health())

    serialized = str(payload)
    assert payload["modules"]["degraded"]["error"] == (
        "Module health check returned HTTP 503."
    )
    assert payload["modules"]["offline"]["error"] == (
        "Module health check is unavailable."
    )
    assert "10.0.0" not in serialized
    assert "/private/jobs.db" not in serialized


def test_module_health_probe_attaches_admin_token(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("NMTK_ADMIN_TOKEN", "secret-admin-token")
    monkeypatch.setattr(
        health, "MODULE_URLS", {"neurocnl": "http://127.0.0.1:9000/api/neurocnl/health"}
    )

    seen_headers: dict[str, str] = {}

    class FakeClient:
        def __init__(self, **_kwargs: Any) -> None:
            pass

        async def __aenter__(self) -> "FakeClient":
            return self

        async def __aexit__(self, *_args: Any) -> None:
            return None

        async def get(
            self, url: str, headers: dict[str, str] | None = None
        ) -> httpx.Response:
            seen_headers.update(headers or {})
            return httpx.Response(200)

    monkeypatch.setattr(health.httpx, "AsyncClient", FakeClient)

    payload = asyncio.run(health.modules_health())

    assert seen_headers == {"X-NMTK-Admin-Token": "secret-admin-token"}
    assert payload["modules"]["neurocnl"]["status"] == "online"
