"""Tests for JobStore service."""

import asyncio
import time

import aiosqlite
import pytest
import pytest_asyncio

from backend.app.schemas.jobs import JobStatus
from backend.app.services.job_store import JobStore


@pytest_asyncio.fixture
async def store(tmp_path):
    """Fixture to provide a JobStore with an isolated database."""
    db_path = tmp_path / "test_jobs.db"
    store = JobStore(db_path=db_path)
    await store.initialize()
    return store


@pytest.mark.asyncio
async def test_create_job(store):
    """Test job creation."""
    job_id = await store.create()
    assert job_id is not None

    job = await store.get(job_id)
    assert job["job_id"] == job_id
    assert job["status"] == JobStatus.queued
    assert job["result"] is None
    assert job["error"] is None


@pytest.mark.asyncio
async def test_set_running(store):
    """Test updating job to running."""
    job_id = await store.create()
    await store.set_running(job_id)

    job = await store.get(job_id)
    assert job["status"] == JobStatus.running


@pytest.mark.asyncio
async def test_set_complete(store):
    """Test updating job to complete with result."""
    job_id = await store.create()
    await store.set_running(job_id)
    result = {"foo": "bar"}
    await store.set_complete(job_id, result)

    job = await store.get(job_id)
    assert job["status"] == JobStatus.complete
    assert job["result"] == result


@pytest.mark.asyncio
async def test_set_failed(store):
    """Test updating job to failed with error message."""
    job_id = await store.create()
    error = "Something went wrong"
    await store.set_failed(job_id, error)

    job = await store.get(job_id)
    assert job["status"] == JobStatus.failed
    assert job["error"] == error


@pytest.mark.asyncio
async def test_set_failed_with_structured_error(store):
    """Structured failure payloads survive round-trip storage."""
    job_id = await store.create()
    error = {
        "error": "parse_failed",
        "items": [{"code": "unsupported_sentence_family", "message": "No match"}],
    }
    await store.set_failed(job_id, error)

    job = await store.get(job_id)
    assert job["status"] == JobStatus.failed
    assert job["error"] == error


@pytest.mark.asyncio
async def test_get_nonexistent_job(store):
    """Test retrieving a job that doesn't exist."""
    job = await store.get("invalid-id")
    assert job is None


@pytest.mark.asyncio
async def test_get_job_malformed_json(store):
    """Test retrieval when result contains malformed JSON."""
    job_id = await store.create()

    # Manually insert malformed JSON
    async with aiosqlite.connect(store.db_path) as db:
        await db.execute(
            "UPDATE jobs SET result = ? WHERE job_id = ?",
            ("{not valid json", job_id),
        )
        await db.commit()

    job = await store.get(job_id)
    assert job["result"] == "{not valid json"


@pytest.mark.asyncio
async def test_list_jobs_pagination(store):
    """Test paginated job listing."""
    # Create 25 jobs
    for i in range(25):
        await store.create()

    # Check first page
    page1 = await store.list_jobs(page=1, size=10)
    assert len(page1["items"]) == 10
    assert page1["total"] == 25
    assert page1["pages"] == 3

    # Check last page
    page3 = await store.list_jobs(page=3, size=10)
    assert len(page3["items"]) == 5


@pytest.mark.asyncio
async def test_cleanup_expired_jobs(store):
    """Test cleaning up old jobs."""
    await store.create()

    # Manually set updated_at to the past
    async with aiosqlite.connect(store.db_path) as db:
        await db.execute("UPDATE jobs SET updated_at = datetime('now', '-2 days')")
        await db.commit()

    # Create a fresh job
    await store.create()

    deleted_count = await store.cleanup_expired_jobs(ttl_seconds=86400)
    assert deleted_count == 1

    res = await store.list_jobs()
    assert res["total"] == 1


@pytest.mark.asyncio
async def test_list_jobs_malformed_json(store):
    """Test paginated job listing with malformed JSON result."""
    job_id = await store.create()

    # Manually insert malformed JSON
    async with aiosqlite.connect(store.db_path) as db:
        await db.execute(
            "UPDATE jobs SET result = ? WHERE job_id = ?",
            ("{not valid json", job_id),
        )
        await db.commit()

    res = await store.list_jobs()
    assert res["items"][0]["result"] == "{not valid json"


@pytest.mark.asyncio
async def test_submit_success(store):
    """Test successful job submission."""

    def sample_task(x: int) -> int:
        return x * 2

    job_id = await store.submit(sample_task, 21)

    # Wait for completion (since it runs in executor)
    for _ in range(50):
        job = await store.get(job_id)
        if job["status"] == JobStatus.complete:
            break
        await asyncio.sleep(0.1)

    assert job["status"] == JobStatus.complete
    assert job["result"] == 42


@pytest.mark.asyncio
async def test_submit_timeout(store):
    """Test job submission with timeout."""

    def long_task():
        time.sleep(1)
        return "done"

    # Set a very short timeout
    job_id = await store.submit(long_task, timeout=0.1)

    # Wait for failure
    for _ in range(50):
        job = await store.get(job_id)
        if job["status"] == JobStatus.failed:
            break
        await asyncio.sleep(0.1)

    assert job["status"] == JobStatus.failed
    assert "timeout" in job["error"].lower()


@pytest.mark.asyncio
async def test_submit_exception(store):
    """Test job submission that raises an exception."""

    def failing_task():
        raise ValueError("Boom!")

    job_id = await store.submit(failing_task)

    # Wait for failure
    for _ in range(50):
        job = await store.get(job_id)
        if job["status"] == JobStatus.failed:
            break
        await asyncio.sleep(0.1)

    assert job["status"] == JobStatus.failed
    assert "Boom!" in job["error"]


# ---------------------------------------------------------------------------
# Operational hardening tests (issue #28)
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_recover_stale_running_jobs(store):
    """Running jobs are marked failed on recovery."""
    job_id = await store.create()
    await store.set_running(job_id)

    recovered = await store.recover_stale_running_jobs()
    assert recovered == 1

    job = await store.get(job_id)
    assert job["status"] == JobStatus.failed
    assert "server_restart" in job["error"]


@pytest.mark.asyncio
async def test_recover_idempotent(store):
    """Second recovery pass finds nothing to recover."""
    job_id = await store.create()
    await store.set_running(job_id)

    assert await store.recover_stale_running_jobs() == 1
    assert await store.recover_stale_running_jobs() == 0


@pytest.mark.asyncio
async def test_drain_completes_active_tasks(store):
    """Drain waits for active tasks to finish."""

    def slow_task():
        time.sleep(0.3)
        return "done"

    job_id = await store.submit(slow_task)
    cancelled = await store.drain(timeout=5.0)
    assert cancelled == 0

    job = await store.get(job_id)
    assert job["status"] == JobStatus.complete


@pytest.mark.asyncio
async def test_create_with_request_id(store):
    """request_id is stored and retrievable."""
    job_id = await store.create(request_id="test-req-123")
    job = await store.get(job_id)
    assert job["request_id"] == "test-req-123"


@pytest.mark.asyncio
async def test_create_without_request_id(store):
    """request_id defaults to None when not provided."""
    job_id = await store.create()
    job = await store.get(job_id)
    assert job["request_id"] is None


@pytest.mark.asyncio
async def test_submit_with_request_id(store):
    """submit() forwards request_id to create()."""

    def noop():
        return "ok"

    job_id = await store.submit(noop, request_id="req-abc")

    # Wait for completion
    for _ in range(50):
        job = await store.get(job_id)
        if job["status"] == JobStatus.complete:
            break
        await asyncio.sleep(0.1)

    assert job["request_id"] == "req-abc"


@pytest.mark.asyncio
async def test_list_jobs_includes_request_id(store):
    """Paginated listing includes request_id."""
    await store.create(request_id="req-list-test")

    res = await store.list_jobs()
    assert res["items"][0]["request_id"] == "req-list-test"


@pytest.mark.asyncio
async def test_invalid_state_transitions(store):
    """Test that invalid state transitions raise ValueError."""
    job_id = await store.create()

    # queued -> complete is invalid
    with pytest.raises(ValueError, match="cannot transition to complete"):
        await store.set_complete(job_id, {"result": "test"})

    # Transition to running is valid
    await store.set_running(job_id)

    # running -> running is invalid
    with pytest.raises(ValueError, match="cannot transition to running"):
        await store.set_running(job_id)

    # running -> complete is valid
    await store.set_complete(job_id, {"result": "test"})

    # complete -> failed is invalid
    with pytest.raises(ValueError, match="cannot transition to failed"):
        await store.set_failed(job_id, "error")

    # complete -> running is invalid
    with pytest.raises(ValueError, match="cannot transition to running"):
        await store.set_running(job_id)

    # complete -> complete is invalid
    with pytest.raises(ValueError, match="cannot transition to complete"):
        await store.set_complete(job_id, {"result": "test"})
