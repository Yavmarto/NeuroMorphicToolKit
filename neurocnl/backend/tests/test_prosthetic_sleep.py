"""Tests for POST /api/prosthetic/sleep."""

import asyncio
from unittest.mock import patch

import httpx
import pytest
from fastapi.testclient import TestClient

from backend.app.main import app
from neurocnl.training_registry import TrainingResult

client = TestClient(app)


@pytest.fixture
def anyio_backend() -> str:
    # job_store is backed by aiosqlite, which is asyncio-only by its own
    # design (it schedules work via a background thread + asyncio.Future).
    # Without this override, anyio's pytest plugin also parametrizes over
    # trio, which fails with `trio.run received unrecognized yield message`.
    return "asyncio"


VALID_REQUEST = {
    "spec": "The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0",
    "memory_buffer": [
        {"slip_vz": 0.01, "grip": 0.5, "error": 0.1},
        {"slip_vz": 0.02, "grip": 0.6, "error": 0.05},
    ],
    "n_epochs": 5,
    "homeostasis_factor": 0.01,
}


@pytest.mark.anyio
@patch("neurocnl.training.sleep_pes_adapter.SleepPesAdapter.run")
async def test_sleep_valid_request(mock_run):
    """Happy path: valid request returns 202 and then completion."""
    mock_run.return_value = TrainingResult(
        adapter_name="sleep_pes",
        training_mode="offline_sleep",
        status="completed",
        n_epochs=5,
        final_loss=0.05,
        loss_curve=(1.0, 0.5, 0.2, 0.1, 0.05),
        learned_weights=[[0.1, 0.2], [0.3, 0.4]],
        duration_seconds=0.01,
    )
    async with httpx.AsyncClient(
        transport=httpx.ASGITransport(app=app), base_url="http://test"
    ) as ac:
        resp = await ac.post("/api/prosthetic/sleep", json=VALID_REQUEST)
        assert resp.status_code == 202
        job_data = resp.json()
        job_id = job_data["job_id"]
        assert job_id

        # Poll for completion
        for _ in range(20):
            resp = await ac.get(f"/api/jobs/{job_id}")
            assert resp.status_code == 200
            data = resp.json()
            if data["status"] == "complete":
                result = data["result"]
                assert result["n_epochs"] == 5
                assert result["final_loss"] == 0.05
                assert len(result["loss_curve"]) == 5
                return
            elif data["status"] == "failed":
                pytest.fail(f"Job failed: {data['error']}")
            await asyncio.sleep(0.5)

    pytest.fail("Job timed out")


def test_sleep_missing_memory_buffer():
    """Missing required field should return 422."""
    payload = {"spec": "test", "n_epochs": 3}
    resp = client.post("/api/prosthetic/sleep", json=payload)
    assert resp.status_code == 422


@pytest.mark.anyio
@patch("neurocnl.training.sleep_pes_adapter.SleepPesAdapter.run")
async def test_sleep_failed_training_marks_job_failed(mock_run):
    """Legacy sleep jobs should still fail at the job layer for adapter failures."""
    mock_run.return_value = TrainingResult(
        adapter_name="sleep_pes",
        training_mode="offline_sleep",
        status="failed",
        error="optimizer exploded",
        duration_seconds=0.01,
    )
    async with httpx.AsyncClient(
        transport=httpx.ASGITransport(app=app), base_url="http://test"
    ) as ac:
        resp = await ac.post("/api/prosthetic/sleep", json=VALID_REQUEST)
        assert resp.status_code == 202
        job_id = resp.json()["job_id"]

        for _ in range(20):
            resp = await ac.get(f"/api/jobs/{job_id}")
            assert resp.status_code == 200
            data = resp.json()
            if data["status"] == "failed":
                detail = data["error"]
                assert detail["error"] == "training_failed"
                assert detail["messages"] == ["optimizer exploded"]
                return
            elif data["status"] == "complete":
                pytest.fail(f"Job completed unexpectedly: {data['result']}")
            await asyncio.sleep(0.5)

    pytest.fail("Job did not fail in time")
