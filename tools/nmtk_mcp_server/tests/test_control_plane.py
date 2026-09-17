from __future__ import annotations

from typing import Any

import pytest
import requests

from tools.nmtk_mcp_server.control_plane import (
    ControlPlaneClient,
    ControlPlaneClientError,
    classify_doctor_report,
)
from tools.nmtk_mcp_server.control_plane_models import LauncherDoctorResponse


class _FakeResponse:
    def __init__(
        self,
        *,
        status_code: int = 200,
        json_data: dict[str, Any] | None = None,
        text: str = "",
        json_error: Exception | None = None,
    ) -> None:
        self.status_code = status_code
        self._json_data = json_data
        self.text = text
        self._json_error = json_error

    def raise_for_status(self) -> None:
        if self.status_code >= 400:
            raise requests.HTTPError(f"{self.status_code} error", response=self)

    def json(self) -> dict[str, Any]:
        if self._json_error is not None:
            raise self._json_error
        assert self._json_data is not None
        return self._json_data


def _doctor_payload(*, fatal: int = 0, degraded: int = 0, ok: int = 1) -> dict[str, Any]:
    return {
        "status": "ok" if fatal == 0 else "error",
        "fatalCount": fatal,
        "degradedCount": degraded,
        "okCount": ok,
        "globalChecks": [
            {
                "id": "suite_api",
                "preflightStatus": "ok",
                "capabilityWarnings": [],
            }
        ],
        "modules": [
            {
                "id": "neurocnl",
                "name": "NeuroCNL",
                "status": "running",
                "effectivePort": 9000,
            }
        ],
        "backendDeployment": {"ready": True, "selectedTarget": None, "targetCount": 0},
        "akidaHosts": [],
        "pynqBoards": [],
    }


def test_suite_health_success(monkeypatch: pytest.MonkeyPatch) -> None:
    def fake_get(*args: Any, **kwargs: Any) -> _FakeResponse:
        return _FakeResponse(json_data={"status": "ok", "service": "suite_api"})

    monkeypatch.setattr(requests, "get", fake_get)

    result = ControlPlaneClient().suite_health()
    assert result.status == "ok"
    assert result.service == "suite_api"


def test_suite_health_http_failure(monkeypatch: pytest.MonkeyPatch) -> None:
    def fake_get(*args: Any, **kwargs: Any) -> _FakeResponse:
        return _FakeResponse(status_code=500, text="nope")

    monkeypatch.setattr(requests, "get", fake_get)

    with pytest.raises(ControlPlaneClientError, match="Suite health request failed"):
        ControlPlaneClient().suite_health()


def test_doctor_success_ok(monkeypatch: pytest.MonkeyPatch) -> None:
    def fake_get(*args: Any, **kwargs: Any) -> _FakeResponse:
        return _FakeResponse(json_data=_doctor_payload())

    monkeypatch.setattr(requests, "get", fake_get)

    result = ControlPlaneClient().doctor()
    assert result.status == "ok"
    assert result.blocking is False


def test_doctor_degraded_only(monkeypatch: pytest.MonkeyPatch) -> None:
    def fake_get(*args: Any, **kwargs: Any) -> _FakeResponse:
        return _FakeResponse(json_data=_doctor_payload(degraded=2, ok=3))

    monkeypatch.setattr(requests, "get", fake_get)

    result = ControlPlaneClient().doctor()
    assert result.status == "degraded_optional_capability"
    assert result.blocking is False
    assert result.degraded_count == 2


def test_doctor_fatal_present(monkeypatch: pytest.MonkeyPatch) -> None:
    def fake_get(*args: Any, **kwargs: Any) -> _FakeResponse:
        return _FakeResponse(json_data=_doctor_payload(fatal=1, degraded=2, ok=3))

    monkeypatch.setattr(requests, "get", fake_get)

    result = ControlPlaneClient().doctor()
    assert result.status == "preflight_failed"
    assert result.blocking is True
    assert result.fatal_count == 1


def test_invalid_json_or_network_failure_raises(monkeypatch: pytest.MonkeyPatch) -> None:
    def fake_get_json(*args: Any, **kwargs: Any) -> _FakeResponse:
        return _FakeResponse(json_error=ValueError("bad json"))

    monkeypatch.setattr(requests, "get", fake_get_json)

    with pytest.raises(ControlPlaneClientError, match="not valid JSON"):
        ControlPlaneClient().doctor()

    def fake_get_network(*args: Any, **kwargs: Any) -> _FakeResponse:
        raise requests.ConnectionError("boom")

    monkeypatch.setattr(requests, "get", fake_get_network)

    with pytest.raises(ControlPlaneClientError, match="request failed"):
        ControlPlaneClient().doctor()


def test_doctor_summary_preserves_underlying_report_details() -> None:
    report = LauncherDoctorResponse.model_validate(_doctor_payload(degraded=1))
    summary = classify_doctor_report(report)

    assert summary.report.modules[0].id == "neurocnl"
    assert summary.report.backendDeployment == {
        "ready": True,
        "selectedTarget": None,
        "targetCount": 0,
    }
