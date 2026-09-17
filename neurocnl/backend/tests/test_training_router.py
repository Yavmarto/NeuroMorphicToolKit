"""Tests for the generic training API routes.

``POST /training/run`` and ``GET /training/capabilities`` were removed along
with the adapter-registry live-training engine (see
``neurocnl/neurocnl/training/factory.py`` — the registry now only carries
``SleepPesAdapter``). The remaining routes (job status, SSE events, activity
download) are shared infrastructure also used by the notebook-run flow
(``kernel_runner.py`` writes into the same ``job_store``/``progress_bus``),
so they still need coverage here. The terminal-replay test below creates its
job via ``POST /api/prosthetic/sleep`` (still backed by the same job_store)
rather than the now-removed ``/training/run``.
"""

import asyncio
from unittest.mock import AsyncMock, patch

import httpx
import pytest
from fastapi.testclient import TestClient

from backend.app.main import app
from backend.app.routers.training import _resolve_activity_b64
from neurocnl.training_registry import TrainingAvailability, TrainingResult

client = TestClient(app)


@pytest.fixture
def anyio_backend() -> str:
    # job_store is backed by aiosqlite, which is asyncio-only by its own
    # design (it schedules work via a background thread + asyncio.Future).
    # Without this override, anyio's pytest plugin also parametrizes over
    # trio, which fails with `trio.run received unrecognized yield message`.
    return "asyncio"


def test_get_training_job_not_found():
    """GET /api/training/jobs/{nonexistent} returns 404."""
    resp = client.get("/api/training/jobs/nonexistent-job-id")
    assert resp.status_code == 404


def test_training_events_unknown_job_404():
    """SSE endpoint returns 404 for unknown job_id (no hung stream)."""
    resp = client.get("/api/training/jobs/does-not-exist/events")
    assert resp.status_code == 404


@pytest.mark.anyio
async def test_training_events_replays_terminal_for_already_complete_job():
    """If the job already finished before SSE attaches, replay terminal once and close.

    This guards against the "subscribe too late" hang where the bus has already
    been closed and the queue would otherwise never receive an event. The job
    is created via the sleep-PES prosthetic route (which shares the same
    job_store/progress_bus as the removed generic ``/training/run`` route).
    """
    with (
        patch(
            "neurocnl.training.sleep_pes_adapter.SleepPesAdapter.is_available",
            return_value=TrainingAvailability(available=True),
        ),
        patch(
            "neurocnl.training.sleep_pes_adapter.SleepPesAdapter.run",
            return_value=TrainingResult(
                adapter_name="sleep_pes",
                training_mode="offline_sleep",
                status="completed",
                n_epochs=1,
                final_loss=0.01,
                loss_curve=(0.01,),
                duration_seconds=0.0,
            ),
        ),
    ):
        async with httpx.AsyncClient(
            transport=httpx.ASGITransport(app=app), base_url="http://test"
        ) as ac:
            resp = await ac.post(
                "/api/prosthetic/sleep",
                json={
                    "spec": "The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0",
                    "memory_buffer": [{"slip_vz": 0.01, "grip": 0.5, "error": 0.1}],
                    "n_epochs": 1,
                    "homeostasis_factor": 0.01,
                },
            )
            job_id = resp.json()["job_id"]
            # Let the worker finish.
            for _ in range(20):
                poll = await ac.get(f"/api/training/jobs/{job_id}")
                if poll.json()["status"] == "complete":
                    break
                await asyncio.sleep(0.1)

            events_resp = await ac.get(f"/api/training/jobs/{job_id}/events")
            assert events_resp.status_code == 200
            assert "text/event-stream" in events_resp.headers["content-type"]
            body = events_resp.text
            # Single terminal "done" payload, then stream closes naturally.
            assert '"type": "done"' in body
            assert body.count("data:") == 1


# ── _resolve_activity_b64 (per-epoch activity lookup) ───────────────────────


def test_resolve_activity_b64_defaults_to_latest_epoch():
    metadata = {"activity_npy_b64_by_epoch": {"1": "aaaa", "5": "bbbb", "3": "cccc"}}
    b64, available = _resolve_activity_b64(metadata, None)
    assert b64 == "bbbb"
    assert available == [1, 3, 5]


def test_resolve_activity_b64_returns_requested_epoch():
    metadata = {"activity_npy_b64_by_epoch": {"1": "aaaa", "5": "bbbb"}}
    b64, available = _resolve_activity_b64(metadata, 1)
    assert b64 == "aaaa"
    assert available == [1, 5]


def test_resolve_activity_b64_missing_epoch_reports_available():
    metadata = {"activity_npy_b64_by_epoch": {"1": "aaaa", "5": "bbbb"}}
    b64, available = _resolve_activity_b64(metadata, 3)
    assert b64 is None
    assert available == [1, 5]


def test_resolve_activity_b64_falls_back_to_legacy_single_blob():
    """Jobs completed before per-epoch capture existed only ever wrote the
    single ``activity_npy_b64`` field — this must keep working."""
    metadata = {"activity_npy_b64": "legacy-blob"}
    b64, available = _resolve_activity_b64(metadata, None)
    assert b64 == "legacy-blob"
    assert available == []


def test_resolve_activity_b64_empty_metadata_returns_none():
    b64, available = _resolve_activity_b64({}, None)
    assert b64 is None
    assert available == []


# ── GET /training/jobs/{job_id}/activity.npy (epoch-aware) ──────────────────


def _complete_job_row(job_id: str, metadata: dict) -> dict:
    return {
        "job_id": job_id,
        "status": "complete",
        "result": {"notebook_path": "nb.ipynb", "metadata": metadata},
        "error": None,
        "request_id": None,
    }


def test_get_activity_npy_defaults_to_latest_epoch():
    job_id = "job-activity-latest"
    metadata = {"activity_npy_b64_by_epoch": {"1": "YQ==", "5": "Yg=="}}
    with patch(
        "backend.app.services.job_store.job_store.get",
        new=AsyncMock(return_value=_complete_job_row(job_id, metadata)),
    ):
        resp = client.get(f"/api/training/jobs/{job_id}/activity.npy")
    assert resp.status_code == 200
    assert resp.content == b"b"


def test_get_activity_npy_returns_requested_epoch():
    job_id = "job-activity-epoch"
    metadata = {"activity_npy_b64_by_epoch": {"1": "YQ==", "5": "Yg=="}}
    with patch(
        "backend.app.services.job_store.job_store.get",
        new=AsyncMock(return_value=_complete_job_row(job_id, metadata)),
    ):
        resp = client.get(f"/api/training/jobs/{job_id}/activity.npy?epoch=1")
    assert resp.status_code == 200
    assert resp.content == b"a"


def test_get_activity_npy_unknown_epoch_reports_available_epochs():
    job_id = "job-activity-missing-epoch"
    metadata = {"activity_npy_b64_by_epoch": {"1": "YQ==", "5": "Yg=="}}
    with patch(
        "backend.app.services.job_store.job_store.get",
        new=AsyncMock(return_value=_complete_job_row(job_id, metadata)),
    ):
        resp = client.get(f"/api/training/jobs/{job_id}/activity.npy?epoch=3")
    assert resp.status_code == 404
    detail = resp.json()["detail"]
    assert "epoch 3" in detail
    assert "[1, 5]" in detail


def test_get_activity_npy_legacy_job_without_epoch_param_still_works():
    job_id = "job-activity-legacy"
    metadata = {"activity_npy_b64": "bGVnYWN5"}
    with patch(
        "backend.app.services.job_store.job_store.get",
        new=AsyncMock(return_value=_complete_job_row(job_id, metadata)),
    ):
        resp = client.get(f"/api/training/jobs/{job_id}/activity.npy")
    assert resp.status_code == 200
    assert resp.content == b"legacy"
