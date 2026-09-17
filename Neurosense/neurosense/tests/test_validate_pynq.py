from __future__ import annotations

from pathlib import Path
from unittest.mock import patch

import httpx
import pytest
from fastapi import FastAPI
from fastapi.responses import StreamingResponse

from neurosense.app.main import app
from neurosense.tests.validate_pynq import run_validation


@pytest.mark.anyio
async def test_simulated_validation_passes_against_app() -> None:
    transport = httpx.ASGITransport(app=app)
    frames = [{"spikes": [0, 1, 0, 1], "simulated": True}]
    with patch(
        "neurosense.tests.validate_pynq._read_stream_frames",
        return_value=(frames, None),
    ):
        async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
            report = await run_validation(
                base_url="http://test/api/neurosense",
                simulated=True,
                client=client,
            )

    assert report.passed is True
    assert report.device_id == "pynq_sim_01"
    assert report.frames_received == 1
    assert [check.name for check in report.checks] == [
        "discover devices",
        "resolve device",
        "start stream",
        "spike payload",
        "simulated markers",
        "stop stream",
    ]


@pytest.mark.anyio
async def test_real_validation_fails_without_real_device(tmp_path: Path) -> None:
    transport = httpx.ASGITransport(app=app)
    evidence_path = tmp_path / "pynq_acceptance_real.json"
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
        report = await run_validation(
            base_url="http://test/api/neurosense",
            simulated=False,
            evidence_path=evidence_path,
            client=client,
        )

    assert report.passed is False
    assert evidence_path.exists()
    assert any(check.name == "resolve real device" and not check.passed for check in report.checks)


@pytest.mark.anyio
async def test_real_validation_uses_http_frame_reader() -> None:
    """The non-simulated path must dial the real NDJSON frame reader.

    Regression: ``_read_stream_frames`` is keyword-only, so the positional call
    in ``run_validation`` raised TypeError and the real path never ran.
    """
    fake = FastAPI()

    @fake.get("/api/neurosense/sense/pynq/devices")
    async def _devices() -> dict[str, list[dict[str, object]]]:
        return {
            "devices": [
                {
                    "device_id": "pynq",
                    "ip_address": "192.168.2.103",
                    "status": "online",
                    "sensors": [],
                }
            ]
        }

    @fake.post("/api/neurosense/sense/pynq/stream/start")
    async def _start() -> StreamingResponse:
        async def _lines():
            for _ in range(2):
                yield '{"spikes": [0, 1, 0, 1]}\n'

        return StreamingResponse(_lines(), media_type="application/x-ndjson")

    @fake.post("/api/neurosense/sense/pynq/stream/stop")
    async def _stop() -> dict[str, str]:
        return {"status": "stopped", "device_id": "pynq"}

    transport = httpx.ASGITransport(app=fake)
    with patch("neurosense.tests.validate_pynq._probe_websocket", return_value=(True, "ok")):
        async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
            report = await run_validation(
                base_url="http://test/api/neurosense",
                simulated=False,
                frame_count=2,
                client=client,
            )

    assert report.passed is True
    assert report.device_id == "pynq"
    assert report.frames_received == 2
