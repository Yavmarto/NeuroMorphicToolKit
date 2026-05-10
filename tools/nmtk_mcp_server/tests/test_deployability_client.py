from __future__ import annotations

from typing import Any

import pytest
import requests

from tools.nmtk_mcp_server.deployability_client import (
    DeployabilityClient,
    DeployabilityClientError,
    DeployabilityRequest,
)


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


def test_teensy_success_preserves_verdict(monkeypatch: pytest.MonkeyPatch) -> None:
    def fake_post(*args: Any, **kwargs: Any) -> _FakeResponse:
        return _FakeResponse(
            json_data={
                "verdict": "faithful",
                "warnings": ["low headroom"],
                "rejection_reasons": [],
                "payload": {"num_neurons": 4},
            }
        )

    monkeypatch.setattr(requests, "post", fake_post)

    result = DeployabilityClient().check_deployability(
        DeployabilityRequest(spec="ok", target="teensy")
    )

    assert result.target == "teensy"
    assert result.outcome == "faithful"
    assert result.payload == {"num_neurons": 4}


def test_teensy_not_deployable_is_returned_not_raised(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    def fake_post(*args: Any, **kwargs: Any) -> _FakeResponse:
        return _FakeResponse(
            status_code=422,
            json_data={
                "detail": {
                    "error": "not_deployable",
                    "warnings": ["timing risk"],
                    "rejection_reasons": ["too many neurons"],
                }
            },
        )

    monkeypatch.setattr(requests, "post", fake_post)

    result = DeployabilityClient().check_deployability(
        DeployabilityRequest(spec="bad", target="teensy")
    )

    assert result.outcome == "not_deployable"
    assert result.rejections == ["too many neurons"]


def test_pynq_success_uses_support_state(monkeypatch: pytest.MonkeyPatch) -> None:
    def fake_post(*args: Any, **kwargs: Any) -> _FakeResponse:
        return _FakeResponse(
            json_data={
                "support_state": "exportable_with_warnings",
                "warnings": ["near capacity"],
                "rejections": [],
                "network_summary": {"n_neurons": 128},
                "deploy_payload": {"overlay_id": "snn_overlay_v1"},
            }
        )

    monkeypatch.setattr(requests, "post", fake_post)

    result = DeployabilityClient().check_deployability(
        DeployabilityRequest(spec="ok", target="pynq")
    )

    assert result.outcome == "exportable_with_warnings"
    assert result.network_summary == {"n_neurons": 128}
    assert result.payload == {"overlay_id": "snn_overlay_v1"}


def test_akida_success_preserves_topology_and_version(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    def fake_post(*args: Any, **kwargs: Any) -> _FakeResponse:
        return _FakeResponse(
            json_data={
                "support_state": "exportable_scaffold",
                "akida_version": "akida2",
                "topology_verdict": "approximate",
                "warnings": [],
                "rejections": [],
                "network_summary": {"n_neurons": 32},
                "mapped_network": {"layers": []},
            }
        )

    monkeypatch.setattr(requests, "post", fake_post)

    result = DeployabilityClient().check_deployability(
        DeployabilityRequest(spec="ok", target="akida")
    )

    assert result.outcome == "exportable_scaffold"
    assert result.akida_version == "akida2"
    assert result.topology_verdict == "approximate"
    assert result.payload == {"layers": []}


def test_unknown_target_raises() -> None:
    with pytest.raises(DeployabilityClientError, match="Unknown target"):
        DeployabilityClient().check_deployability(
            DeployabilityRequest(spec="ok", target="unknown")
        )


def test_parse_failure_raises(monkeypatch: pytest.MonkeyPatch) -> None:
    def fake_post(*args: Any, **kwargs: Any) -> _FakeResponse:
        return _FakeResponse(
            status_code=422,
            json_data={"detail": {"error": "parse_failed", "messages": ["bad cnl"]}},
        )

    monkeypatch.setattr(requests, "post", fake_post)

    with pytest.raises(DeployabilityClientError, match="rejected"):
        DeployabilityClient().check_deployability(
            DeployabilityRequest(spec="bad", target="teensy")
        )


def test_network_failure_raises(monkeypatch: pytest.MonkeyPatch) -> None:
    def fake_post(*args: Any, **kwargs: Any) -> _FakeResponse:
        raise requests.ConnectionError("boom")

    monkeypatch.setattr(requests, "post", fake_post)

    with pytest.raises(DeployabilityClientError, match="request failed"):
        DeployabilityClient().check_deployability(
            DeployabilityRequest(spec="ok", target="teensy")
        )
