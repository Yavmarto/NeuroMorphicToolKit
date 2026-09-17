from __future__ import annotations

import json
from pathlib import Path
from unittest.mock import patch

import pytest

from neurosense.tests.validate_prophesee import run_api_validation, run_local_validation


@pytest.mark.anyio
async def test_mock_local_validation_passes(tmp_path: Path) -> None:
    evidence_path = tmp_path / "prophesee_acceptance_mock.json"

    report = await run_local_validation(mock=True, evidence_path=evidence_path)

    assert report.passed is True
    assert report.mock is True
    assert report.event_count == 12
    assert report.resolution == [640, 480]
    assert [check.name for check in report.checks] == [
        "metavision sdk",
        "open live stream",
        "capture event batch",
        "close stream",
    ]

    payload = json.loads(evidence_path.read_text(encoding="utf-8"))
    assert payload["passed"] is True
    assert payload["mock"] is True


@pytest.mark.anyio
async def test_api_validation_fails_when_sdk_missing(tmp_path: Path) -> None:
    class FakeResponse:
        status_code = 200

        def json(self) -> dict[str, object]:
            return {"devices": [], "error": "metavision-sdk not installed"}

    class FakeClient:
        async def __aenter__(self) -> FakeClient:
            return self

        async def __aexit__(self, *_args: object) -> None:
            return None

        async def get(self, _url: str) -> FakeResponse:
            return FakeResponse()

    evidence_path = tmp_path / "prophesee_acceptance_api.json"
    with patch(
        "neurosense.tests.validate_prophesee.httpx.AsyncClient",
        return_value=FakeClient(),
    ):
        report = await run_api_validation(
            api_base="http://example:8004",
            evidence_path=evidence_path,
        )

    assert report.passed is False
    assert any(check.name == "metavision sdk" and not check.passed for check in report.checks)
