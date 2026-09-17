"""Tests for the /api/jobs endpoint."""

import pytest
from fastapi.testclient import TestClient

from backend.app.main import app
from backend.app.services.job_store import JobStore, job_store

client = TestClient(app)


@pytest.mark.asyncio(loop_scope="function")
async def test_get_job_not_found():
    """Test polling a non-existent job ID."""
    resp = client.get("/api/jobs/non-existent-id")
    assert resp.status_code == 404
    assert "not found" in resp.json()["detail"]


@pytest.mark.asyncio(loop_scope="function")
async def test_get_job_success():
    """Test polling an existing job."""
    # Manually create a job in the store
    job_id = await job_store.create()
    await job_store.set_running(job_id)
    await job_store.set_complete(job_id, {"result": "ok"})

    resp = client.get(f"/api/jobs/{job_id}")
    assert resp.status_code == 200
    data = resp.json()
    assert data["job_id"] == job_id
    assert data["status"] == "complete"
    assert data["result"] == {"result": "ok"}


@pytest.mark.asyncio(loop_scope="function")
async def test_get_job_failed():
    """Test polling a failed job."""
    job_id = await job_store.create()
    await job_store.set_failed(job_id, "Something went wrong")

    resp = client.get(f"/api/jobs/{job_id}")
    assert resp.status_code == 200
    data = resp.json()
    assert data["job_id"] == job_id
    assert data["status"] == "failed"
    assert data["error"] == "Something went wrong"


@pytest.mark.asyncio(loop_scope="function")
async def test_get_job_failed_with_structured_error():
    """Structured job failures are returned without flattening."""
    job_id = await job_store.create()
    detail = {
        "error": "parse_failed",
        "items": [{"code": "unsupported_sentence_family", "message": "No match"}],
    }
    await job_store.set_failed(job_id, detail)

    resp = client.get(f"/api/jobs/{job_id}")
    assert resp.status_code == 200
    data = resp.json()
    assert data["status"] == "failed"
    assert data["error"] == detail


@pytest.mark.asyncio(loop_scope="function")
async def test_list_jobs_pagination():
    """Test listing jobs with pagination.

    job_store is the real, persistent ~/.neurocnl/jobs.db shared by every
    real run on this machine (see test_persistence, which exercises that
    same persistence directly) — it is never empty on a real dev machine, so
    asserting an exact total/page count here needs a baseline taken before
    creating this test's own 5 jobs, not a hardcoded absolute count.
    """
    baseline = client.get("/api/jobs?page=1&size=1").json()
    total_before = baseline["total"]

    # Create 5 jobs
    job_ids = []
    for _ in range(5):
        job_ids.append(await job_store.create())

    expected_total = total_before + 5
    expected_pages = (expected_total + 1) // 2  # ceil(expected_total / 2)

    # Test page 1, size 2 — our 5 new jobs sort first (created_at DESC).
    resp = client.get("/api/jobs?page=1&size=2")
    assert resp.status_code == 200
    data = resp.json()
    assert len(data["items"]) == 2
    assert data["total"] == expected_total
    assert data["page"] == 1
    assert data["size"] == 2
    assert data["pages"] == expected_pages

    # Test the last page — its item count is whatever remains after filling
    # every prior page with `size` items.
    resp = client.get(f"/api/jobs?page={expected_pages}&size=2")
    assert resp.status_code == 200
    data = resp.json()
    assert len(data["items"]) == expected_total - (expected_pages - 1) * 2
    assert data["total"] == expected_total
    assert data["page"] == expected_pages


@pytest.mark.asyncio(loop_scope="function")
async def test_persistence():
    """Test that jobs survive 'server restart' (re-initialization of store)."""
    job_id = await job_store.create()
    await job_store.set_running(job_id)
    await job_store.set_complete(job_id, {"status": "persisted"})

    # Simulate restart by creating a new JobStore pointing to the same DB
    new_store = JobStore(db_path=job_store.db_path)
    job = await new_store.get(job_id)

    assert job is not None
    assert job["job_id"] == job_id
    assert job["status"] == "complete"
    assert job["result"] == {"status": "persisted"}


@pytest.mark.asyncio(loop_scope="function")
async def test_request_id_in_job_response():
    """Job response includes request_id field."""
    job_id = await job_store.create(request_id="req-router-test")
    await job_store.set_running(job_id)
    await job_store.set_complete(job_id, {"ok": True})

    resp = client.get(f"/api/jobs/{job_id}")
    assert resp.status_code == 200
    data = resp.json()
    assert data["request_id"] == "req-router-test"
