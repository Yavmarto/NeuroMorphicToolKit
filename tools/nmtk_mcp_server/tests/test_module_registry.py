from __future__ import annotations

from typing import Any

import pytest
import requests

from tools.nmtk_mcp_server.module_registry import (
    ModuleRegistryClient,
    ModuleRegistryClientError,
    ModuleStatusModel,
    shape_module_status,
    shape_module_statuses,
)


class _FakeResponse:
    def __init__(
        self,
        *,
        status_code: int = 200,
        json_data: Any = None,
        json_error: Exception | None = None,
    ) -> None:
        self.status_code = status_code
        self._json_data = json_data
        self._json_error = json_error

    def raise_for_status(self) -> None:
        if self.status_code >= 400:
            raise requests.HTTPError(f"{self.status_code} error", response=self)

    def json(self) -> Any:
        if self._json_error is not None:
            raise self._json_error
        return self._json_data


def test_list_modules_success(monkeypatch: pytest.MonkeyPatch) -> None:
    def fake_get(*args: Any, **kwargs: Any) -> _FakeResponse:
        assert kwargs["params"] is None
        return _FakeResponse(
            json_data=[
                {
                    "id": "neurocnl",
                    "name": "NeuroCNL",
                    "status": "running",
                    "effectivePort": 9000,
                    "preflightStatus": "ok",
                }
            ]
        )

    monkeypatch.setattr(requests, "get", fake_get)

    modules = ModuleRegistryClient().list_modules()
    assert len(modules) == 1
    assert modules[0].id == "neurocnl"
    assert modules[0].effectivePort == 9000


def test_list_modules_refresh_updates(monkeypatch: pytest.MonkeyPatch) -> None:
    def fake_get(*args: Any, **kwargs: Any) -> _FakeResponse:
        assert kwargs["params"] == {"refreshUpdates": "true"}
        return _FakeResponse(json_data=[])

    monkeypatch.setattr(requests, "get", fake_get)

    ModuleRegistryClient().list_modules(refresh_updates=True)


def test_get_module_filters_by_id(monkeypatch: pytest.MonkeyPatch) -> None:
    def fake_get(*args: Any, **kwargs: Any) -> _FakeResponse:
        return _FakeResponse(
            json_data=[
                {"id": "neurocnl"},
                {"id": "neurohub"},
            ]
        )

    monkeypatch.setattr(requests, "get", fake_get)

    module = ModuleRegistryClient().get_module("neurohub")
    assert module is not None
    assert module.id == "neurohub"


def test_invalid_json_raises(monkeypatch: pytest.MonkeyPatch) -> None:
    def fake_get(*args: Any, **kwargs: Any) -> _FakeResponse:
        return _FakeResponse(json_error=ValueError("bad json"))

    monkeypatch.setattr(requests, "get", fake_get)

    with pytest.raises(ModuleRegistryClientError, match="not valid JSON"):
        ModuleRegistryClient().list_modules()


def test_non_list_payload_raises(monkeypatch: pytest.MonkeyPatch) -> None:
    def fake_get(*args: Any, **kwargs: Any) -> _FakeResponse:
        return _FakeResponse(json_data={"id": "not-a-list"})

    monkeypatch.setattr(requests, "get", fake_get)

    with pytest.raises(ModuleRegistryClientError, match="did not return a list"):
        ModuleRegistryClient().list_modules()


def test_network_failure_raises(monkeypatch: pytest.MonkeyPatch) -> None:
    def fake_get(*args: Any, **kwargs: Any) -> _FakeResponse:
        raise requests.ConnectionError("boom")

    monkeypatch.setattr(requests, "get", fake_get)

    with pytest.raises(ModuleRegistryClientError, match="request failed"):
        ModuleRegistryClient().list_modules()


def test_shape_module_status_preserves_launcher_fields() -> None:
    shaped = shape_module_status(
        ModuleStatusModel(
            id="neurocnl",
            name="NeuroCNL",
            status="running",
            preflightStatus="ok",
            preflightMessage="ready",
            capabilityWarnings=[],
            route="/neurocnl",
            effectivePort=9000,
            healthUrl="http://127.0.0.1:9000/health",
            metadata={"kind": "studio"},
        )
    )

    assert shaped["id"] == "neurocnl"
    assert shaped["readiness"] == "ok"
    assert shaped["preflightStatus"] == "ok"
    assert shaped["effectivePort"] == 9000
    assert shaped["metadata"] == {"kind": "studio"}


def test_shape_module_status_marks_preflight_failed_as_blocking() -> None:
    shaped = shape_module_status(
        ModuleStatusModel(
            id="neurochip",
            status="error",
            preflightStatus="preflight_failed",
            capabilityWarnings=["missing runtime"],
        )
    )

    assert shaped["readiness"] == "preflight_failed"
    assert shaped["blocking"] is True
    assert shaped["capabilityWarnings"] == ["missing runtime"]


def test_shape_module_status_marks_degraded_warnings() -> None:
    shaped = shape_module_status(
        ModuleStatusModel(
            id="akida",
            status="degraded",
            preflightStatus="degraded_optional_capability",
            capabilityWarnings=["remote host unavailable"],
        )
    )

    assert shaped["readiness"] == "degraded_optional_capability"
    assert shaped["blocking"] is False


def test_shape_module_statuses_handles_missing_optional_fields() -> None:
    shaped = shape_module_statuses([ModuleStatusModel(id="neurohub")])

    assert shaped == [
        {
            "id": "neurohub",
            "name": None,
            "status": None,
            "readiness": "unknown",
            "blocking": False,
            "preflightStatus": None,
            "preflightMessage": None,
            "capabilityWarnings": [],
            "environmentFingerprint": None,
            "route": None,
            "effectivePort": None,
            "healthUrl": None,
            "metadata": {},
        }
    ]
