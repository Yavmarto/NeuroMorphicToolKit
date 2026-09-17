from __future__ import annotations

from typing import Any

import pytest
import requests

from tools.nmtk_mcp_server.models import ValidateCnlRequest
from tools.nmtk_mcp_server.neurocnl_client import NeuroCnlClient, NeuroCnlClientError


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


def _valid_response_payload() -> dict[str, Any]:
    return {
        "layer1": {
            "overall": True,
            "passed": [{"name": "tau_positive", "description": "ok"}],
            "failed": [],
            "warnings": [{"name": "planner_hint", "severity": "warning"}],
        },
        "layer2": {
            "overall": True,
            "checks_passed": ["all_neurons_resolved"],
            "checks_failed": [],
            "neurons_found": ["A", "B"],
        },
        "overall": True,
        "backend_support": {
            "backend": "nengo",
            "verdict": "faithful",
            "supported_concepts": ["lif"],
            "approximated_concepts": [],
            "unsupported_concepts": [],
            "warnings": [],
        },
    }


def test_validate_response_success(monkeypatch: pytest.MonkeyPatch) -> None:
    def fake_post(*args: Any, **kwargs: Any) -> _FakeResponse:
        return _FakeResponse(json_data=_valid_response_payload())

    monkeypatch.setattr(requests, "post", fake_post)

    client = NeuroCnlClient()
    result = client.validate_cnl(ValidateCnlRequest(spec="neuron A spikes."))

    assert result.overall is True
    assert result.layer1.passed[0].name == "tau_positive"
    assert result.layer2.neurons_found == ["A", "B"]


def test_backend_support_is_preserved(monkeypatch: pytest.MonkeyPatch) -> None:
    def fake_post(*args: Any, **kwargs: Any) -> _FakeResponse:
        return _FakeResponse(json_data=_valid_response_payload())

    monkeypatch.setattr(requests, "post", fake_post)

    result = NeuroCnlClient().validate_cnl(
        ValidateCnlRequest(spec="neuron A spikes.", backend="nengo")
    )

    assert result.backend_support is not None
    assert result.backend_support.backend == "nengo"
    assert result.backend_support.verdict == "faithful"


def test_non_200_status_raises(monkeypatch: pytest.MonkeyPatch) -> None:
    def fake_post(*args: Any, **kwargs: Any) -> _FakeResponse:
        return _FakeResponse(status_code=503, text="service unavailable")

    monkeypatch.setattr(requests, "post", fake_post)

    with pytest.raises(NeuroCnlClientError, match="validation request failed"):
        NeuroCnlClient().validate_cnl(ValidateCnlRequest(spec="bad"))


def test_invalid_json_raises(monkeypatch: pytest.MonkeyPatch) -> None:
    def fake_post(*args: Any, **kwargs: Any) -> _FakeResponse:
        return _FakeResponse(json_error=ValueError("bad json"))

    monkeypatch.setattr(requests, "post", fake_post)

    with pytest.raises(NeuroCnlClientError, match="not valid JSON"):
        NeuroCnlClient().validate_cnl(ValidateCnlRequest(spec="bad"))


def test_network_failure_raises(monkeypatch: pytest.MonkeyPatch) -> None:
    def fake_post(*args: Any, **kwargs: Any) -> _FakeResponse:
        raise requests.ConnectionError("boom")

    monkeypatch.setattr(requests, "post", fake_post)

    with pytest.raises(NeuroCnlClientError, match="request failed"):
        NeuroCnlClient().validate_cnl(ValidateCnlRequest(spec="bad"))
