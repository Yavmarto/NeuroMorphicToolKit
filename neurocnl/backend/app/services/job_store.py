"""Persistent job registry, backed by a typed SQLAlchemy repository, for async background tasks."""

from __future__ import annotations

import asyncio
import json
import os
import time
import uuid
from collections.abc import Callable
from pathlib import Path
from typing import Any

import structlog
from prometheus_client import Counter, Gauge, Histogram
from sqlalchemy import delete, func, select, text, update

from backend.app.schemas.jobs import JobStatus

from .job_db import JobDB, JobEventDB, initialize_schema, session_scope

logger = structlog.get_logger(__name__)

DEFAULT_TIMEOUT = 60.0
DB_PATH = (
    Path(os.environ.get("NEUROCNL_DATA_DIR", Path.home() / ".neurocnl")) / "jobs.db"
)

# ---------------------------------------------------------------------------
# Prometheus metrics
# ---------------------------------------------------------------------------
JOB_QUEUE_DEPTH = Gauge(
    "neurocnl_job_queue_depth",
    "Number of jobs currently in queued or running state",
)
JOB_ACTIVE_TASKS = Gauge(
    "neurocnl_job_active_tasks",
    "Number of asyncio tasks currently executing jobs",
)
JOB_COMPLETIONS = Counter(
    "neurocnl_job_completions_total",
    "Total number of completed jobs",
    ["status"],
)
JOB_DURATION = Histogram(
    "neurocnl_job_duration_seconds",
    "Time from job start to terminal state",
    buckets=[0.1, 0.5, 1, 2, 5, 10, 30, 60, 120],
)


def _parse_json_field(raw: str | None) -> Any:
    if not raw:
        return None
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return raw


def _job_to_dict(row: JobDB) -> dict[str, Any]:
    return {
        "job_id": row.job_id,
        "status": row.status,
        "result": _parse_json_field(row.result),
        "error": _parse_json_field(row.error),
        "request_id": row.request_id,
    }


class JobStore:
    """Persistent job store using SQLite via a typed SQLAlchemy repository."""

    def __init__(self, db_path: Path = DB_PATH) -> None:
        self.db_path = db_path
        self._active_tasks: set[asyncio.Task[None]] = set()

    async def initialize(self) -> None:
        """Initialize the database schema."""
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        await initialize_schema(self.db_path)

    async def create(
        self,
        *,
        request_id: str | None = None,
        platform: str | None = None,
        notebook_path: str | None = None,
    ) -> str:
        """Create a new job and return its ID."""
        job_id = str(uuid.uuid4())
        async with session_scope(self.db_path) as session:
            session.add(
                JobDB(
                    job_id=job_id,
                    status=JobStatus.queued,
                    request_id=request_id,
                    platform=platform,
                    notebook_path=notebook_path,
                )
            )
            await session.commit()
        JOB_QUEUE_DEPTH.inc()
        return job_id

    async def set_running(self, job_id: str) -> None:
        """Mark a job as currently running."""
        async with session_scope(self.db_path) as session:
            result = await session.execute(
                update(JobDB)
                .where(JobDB.job_id == job_id, JobDB.status == JobStatus.queued)
                .values(status=JobStatus.running, updated_at=func.current_timestamp())
            )
            await session.commit()
            if result.rowcount == 0:  # type: ignore[attr-defined]
                raise ValueError(f"Job {job_id} cannot transition to running")

    async def set_complete(self, job_id: str, result: Any) -> None:
        """Mark a job as complete and store its result."""
        async with session_scope(self.db_path) as session:
            outcome = await session.execute(
                update(JobDB)
                .where(JobDB.job_id == job_id, JobDB.status == JobStatus.running)
                .values(
                    status=JobStatus.complete,
                    result=json.dumps(result),
                    updated_at=func.current_timestamp(),
                )
            )
            await session.commit()
            if outcome.rowcount == 0:  # type: ignore[attr-defined]
                raise ValueError(f"Job {job_id} cannot transition to complete")

    async def set_failed(self, job_id: str, error: Any) -> None:
        """Mark a job as failed and store the error."""
        async with session_scope(self.db_path) as session:
            outcome = await session.execute(
                update(JobDB)
                .where(
                    JobDB.job_id == job_id,
                    JobDB.status.in_([JobStatus.queued, JobStatus.running]),
                )
                .values(
                    status=JobStatus.failed,
                    error=json.dumps(error),
                    updated_at=func.current_timestamp(),
                )
            )
            await session.commit()
            if outcome.rowcount == 0:  # type: ignore[attr-defined]
                raise ValueError(f"Job {job_id} cannot transition to failed")

    async def get(self, job_id: str) -> dict[str, Any] | None:
        async with session_scope(self.db_path) as session:
            row = await session.get(JobDB, job_id)
            if row is None:
                return None
            return _job_to_dict(row)

    async def list_jobs(self, page: int = 1, size: int = 20) -> dict[str, Any]:
        """Retrieve a paginated list of jobs."""
        offset = (page - 1) * size
        async with session_scope(self.db_path) as session:
            total = (
                await session.execute(select(func.count()).select_from(JobDB))
            ).scalar_one()
            rows = (
                (
                    await session.execute(
                        select(JobDB)
                        .order_by(JobDB.created_at.desc())
                        .limit(size)
                        .offset(offset)
                    )
                )
                .scalars()
                .all()
            )
            items = [_job_to_dict(row) for row in rows]
            pages = (total + size - 1) // size
            return {
                "items": items,
                "total": total,
                "page": page,
                "size": size,
                "pages": pages,
            }

    async def list_active_notebook_jobs(self) -> list[dict[str, Any]]:
        """List queued/running notebook jobs — the "what's active right now" view."""
        async with session_scope(self.db_path) as session:
            rows = (
                (
                    await session.execute(
                        select(JobDB)
                        .where(JobDB.status.in_([JobStatus.queued, JobStatus.running]))
                        .order_by(JobDB.created_at.desc())
                    )
                )
                .scalars()
                .all()
            )
            return [
                {
                    "job_id": row.job_id,
                    "status": row.status,
                    "platform": row.platform,
                    "notebook_path": row.notebook_path,
                    "created_at": row.created_at,
                }
                for row in rows
            ]

    async def append_job_event(self, job_id: str, event: dict[str, Any]) -> None:
        """Append one progress event to the durable log for job_id."""
        async with session_scope(self.db_path) as session:
            session.add(
                JobEventDB(
                    job_id=job_id,
                    event_type=str(event.get("type", "")),
                    payload=json.dumps(event),
                )
            )
            await session.commit()

    async def list_job_events(self, job_id: str) -> list[dict[str, Any]]:
        """Return every persisted event for job_id, oldest first."""
        async with session_scope(self.db_path) as session:
            rows = (
                (
                    await session.execute(
                        select(JobEventDB.payload)
                        .where(JobEventDB.job_id == job_id)
                        .order_by(JobEventDB.id.asc())
                    )
                )
                .scalars()
                .all()
            )
        events: list[dict[str, Any]] = []
        for payload in rows:
            try:
                events.append(json.loads(payload))
            except json.JSONDecodeError:
                continue
        return events

    async def cleanup_expired_jobs(self, ttl_seconds: int = 86400) -> int:
        """Delete jobs older than the specified TTL (default 24h)."""
        async with session_scope(self.db_path) as session:
            outcome = await session.execute(
                text("DELETE FROM jobs WHERE updated_at < datetime('now', :offset)"),
                {"offset": f"-{ttl_seconds} seconds"},
            )
            deleted_count = int(outcome.rowcount)  # type: ignore[attr-defined]
            await session.execute(
                delete(JobEventDB).where(JobEventDB.job_id.not_in(select(JobDB.job_id)))
            )
            await session.commit()
            if deleted_count > 0:
                logger.info("cleaned_up_expired_jobs", deleted_count=deleted_count)
            return deleted_count

    async def submit(
        self,
        fn: Callable[..., Any],
        *args: Any,
        timeout: float = DEFAULT_TIMEOUT,
        request_id: str | None = None,
        bind_job_id: Callable[[str], None] | None = None,
        on_terminal: Callable[[str], None] | None = None,
    ) -> str:
        """Create a job and run *fn* in a background executor.

        Returns the job_id immediately. The caller should poll GET /api/jobs/{job_id}.

        ``bind_job_id`` (optional) is called synchronously with the freshly
        created job_id before the worker starts. The caller can use it to wire
        a streaming publisher (e.g. ProgressBus) into *fn* via closure.

        ``on_terminal`` (optional) is called after the job reaches a terminal
        state (complete / failed / timeout). Used to close associated
        streaming resources such as a progress-bus subscription.
        """
        job_id = await self.create(request_id=request_id)
        if bind_job_id is not None:
            bind_job_id(job_id)
        loop = asyncio.get_running_loop()

        async def _run() -> None:
            structlog.contextvars.bind_contextvars(job_id=job_id)
            JOB_ACTIVE_TASKS.inc()
            start = time.monotonic()
            await self.set_running(job_id)
            try:
                result = await asyncio.wait_for(
                    loop.run_in_executor(None, fn, *args),
                    timeout=timeout,
                )
                await self.set_complete(job_id, result)
                JOB_COMPLETIONS.labels(status="complete").inc()
            except TimeoutError:
                await self.set_failed(job_id, "simulation timeout")
                JOB_COMPLETIONS.labels(status="timeout").inc()
                logger.warning("job_timed_out", job_id=job_id, timeout=timeout)
            except Exception as exc:
                await self.set_failed(job_id, getattr(exc, "payload", str(exc)))
                JOB_COMPLETIONS.labels(status="failed").inc()
                logger.exception("job_failed", job_id=job_id)
            finally:
                elapsed = time.monotonic() - start
                JOB_DURATION.observe(elapsed)
                JOB_QUEUE_DEPTH.dec()
                JOB_ACTIVE_TASKS.dec()
                if on_terminal is not None:
                    try:
                        on_terminal(job_id)
                    except Exception:
                        logger.exception("on_terminal_callback_failed", job_id=job_id)

        # Ensure task is actually scheduled and not garbage collected
        task = asyncio.create_task(_run())
        self._active_tasks.add(task)
        task.add_done_callback(self._active_tasks.discard)
        return job_id

    async def recover_stale_running_jobs(self) -> int:
        """Mark any orphaned 'running' or 'queued' jobs as failed.

        Called at startup to handle jobs that were in-flight or waiting when the server
        previously shut down or crashed.
        """
        async with session_scope(self.db_path) as session:
            outcome = await session.execute(
                update(JobDB)
                .where(JobDB.status.in_([JobStatus.running, JobStatus.queued]))
                .values(
                    status=JobStatus.failed,
                    error="server_restart: job was lost when server shut down",
                    updated_at=func.current_timestamp(),
                )
            )
            recovered = int(outcome.rowcount)  # type: ignore[attr-defined]
            await session.commit()
        if recovered > 0:
            logger.info("recovered_stale_running_jobs", count=recovered)
        return recovered

    async def drain(self, timeout: float = 10.0) -> int:
        """Wait for active tasks to finish; cancel stragglers after *timeout*.

        Returns the number of tasks that had to be cancelled.
        """
        if not self._active_tasks:
            return 0
        tasks = list(self._active_tasks)
        _done, pending = await asyncio.wait(tasks, timeout=timeout)
        for t in pending:
            t.cancel()
        if pending:
            logger.warning("drain_cancelled_tasks", count=len(pending))
        return len(pending)


# Singleton shared across routers
job_store = JobStore()
