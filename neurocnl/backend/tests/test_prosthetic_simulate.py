"""Tests for POST /api/prosthetic/simulate."""

import asyncio
from unittest.mock import MagicMock, patch

import httpx
import pytest
from fastapi.testclient import TestClient

from backend.app.main import app

client = TestClient(app)


@pytest.fixture
def anyio_backend() -> str:
    # job_store is backed by aiosqlite, which is asyncio-only by its own
    # design (it schedules work via a background thread + asyncio.Future).
    # Without this override, anyio's pytest plugin also parametrizes over
    # trio, which fails with `trio.run received unrecognized yield message`.
    return "asyncio"


VALID_SPEC = "The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0"

VALID_REQUEST = {
    "spec": VALID_SPEC,
    "gripper_type": "pinch",
    "drop_height": 0.15,
    "duration": 2.0,
    "n_neurons": 50,
    "seed": 0,
}


@pytest.mark.anyio
@patch("backend.app.routers.prosthetic.simulate.run_drop_test")
async def test_simulate_valid_request(mock_run):
    """Happy path: valid request returns 202 and then completion."""
    mock_run.return_value = {
        "success": True,
        "grip_history": [0.1, 0.2],
        "slip_vz_history": [0.0, 0.01],
        "object_z_history": [0.15, 0.14],
        "stopping_distance_m": 0.01,
        "frames": None,
        "wall_time_seconds": 0.5,
    }
    async with httpx.AsyncClient(
        transport=httpx.ASGITransport(app=app), base_url="http://test"
    ) as ac:
        with patch.dict("sys.modules", {"mujoco": MagicMock()}):
            resp = await ac.post("/api/prosthetic/simulate", json=VALID_REQUEST)
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
                assert result["success"] is True
                assert "grip_history" in result
                return
            elif data["status"] == "failed":
                pytest.fail(f"Job failed: {data['error']}")
            await asyncio.sleep(0.5)

    pytest.fail("Job timed out")


def test_simulate_duration_exceeds_max():
    """Duration > 10 should be rejected with 422."""
    payload = {**VALID_REQUEST, "duration": 11.0}
    with patch.dict("sys.modules", {"mujoco": MagicMock()}):
        resp = client.post("/api/prosthetic/simulate", json=payload)
    assert resp.status_code == 422
    assert "Duration" in resp.json()["detail"]


def test_simulate_mujoco_unavailable():
    """MuJoCo not installed should return 503."""
    with patch(
        "backend.app.routers.prosthetic.simulate.ensure_runtime_dependency",
        return_value=False,
    ):
        resp = client.post("/api/prosthetic/simulate", json=VALID_REQUEST)
    assert resp.status_code == 503
    assert resp.json()["detail"] == (
        "MuJoCo is not installed and automatic installation failed. "
        "Install with: pip install mujoco"
    )


def test_simulate_attempts_mujoco_auto_install():
    with patch(
        "backend.app.routers.prosthetic.simulate.ensure_runtime_dependency",
        return_value=True,
    ) as ensure_dependency:
        resp = client.post("/api/prosthetic/simulate", json=VALID_REQUEST)

    assert resp.status_code == 202
    ensure_dependency.assert_called_once_with("mujoco")
