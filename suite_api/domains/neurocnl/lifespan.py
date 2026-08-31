"""neurocnl lifespan management for suite_api.

Initialises the job and workspace stores, wires the slowapi rate limiter onto
the app, starts the periodic job-cleanup task, and configures structlog — all
the startup work that the standalone
``neurocnl/backend/app/main.py`` does but that suite_api must do itself.

Called from ``suite_api/main.py``'s asynccontextmanager lifespan.
"""

from __future__ import annotations

import asyncio
import logging

# Ensure neurocnl/backend is importable (mirrors the __init__.py preamble)
import suite_api.domains.neurocnl  # noqa: F401 (side-effect import)

logger = logging.getLogger("suite_api.neurocnl.lifespan")

_cleanup_task: asyncio.Task | None = None


async def neurocnl_startup(app) -> None:  # type: ignore[type-arg]
    """Run neurocnl startup tasks inside suite_api's lifespan.

    * Configures structlog so request-level logs appear in the terminal.
    * Initialises the SQLite job store schema.
    * Initialises the SQLite workspace store schema.
    * Recovers any orphaned 'running' jobs from a previous crash.
    * Starts the hourly job-cleanup background task.
    * Wires the slowapi rate limiter onto ``app.state`` so the
      ``@limiter.limit`` decorator on ``/simulate`` can resolve it.
    """
    global _cleanup_task

    # ── Logging ──────────────────────────────────────────────────────────────
    # The standalone backend calls setup_logging() at module level; suite_api
    # must do it here so neurocnl's structlog processors are active.
    try:
        from neurocnl.logging_config import setup_logging

        setup_logging()
    except Exception as exc:
        logger.warning("neurocnl setup_logging failed (non-fatal): %s", exc)

    # ── Rate limiter ─────────────────────────────────────────────────────────
    # slowapi resolves the limiter via request.app.state.limiter.  Without this
    # the @limiter.limit("10/minute") on /simulate raises AttributeError → 500.
    try:
        from backend.app.middleware.rate_limit import limiter
        from slowapi import _rate_limit_exceeded_handler
        from slowapi.errors import RateLimitExceeded

        app.state.limiter = limiter
        app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)
        logger.info("neurocnl rate limiter wired onto suite_api")
    except Exception as exc:
        logger.warning("neurocnl rate limiter setup failed (non-fatal): %s", exc)

    # ── Job store ────────────────────────────────────────────────────────────
    # Creates the SQLite schema (jobs table + indexes).  Without this every
    # call to /simulate fails with "no such table: jobs".
    try:
        from backend.app.services.job_store import job_store

        await job_store.initialize()
        recovered = await job_store.recover_stale_running_jobs()
        if recovered:
            logger.info("neurocnl: recovered %d orphaned jobs", recovered)
    except Exception as exc:
        logger.error("neurocnl job_store initialisation failed: %s", exc)

    # Suite API mounts the workspace router in-process, so it must initialize
    # the same SQLite schema as the standalone NeuroCNL application.
    try:
        from backend.app.services.workspace_store import workspace_store

        await workspace_store.initialize()
    except Exception as exc:
        logger.error("neurocnl workspace_store initialisation failed: %s", exc)

    # Same rule as above, and it was missed: dataset_cache.initialize() is the
    # only place the `source` column migration runs. Under Docker it never ran,
    # so GET /api/neurocnl/datasets died with "no such column: source" and
    # Setup could not list a single dataset — which left every Studio step
    # after Setup locked, because unlocking them requires a chosen dataset.
    try:
        from backend.app.services.dataset_cache import dataset_cache

        await dataset_cache.initialize()
    except Exception as exc:
        logger.error("neurocnl dataset_cache initialisation failed: %s", exc)

    # ── Cleanup task ─────────────────────────────────────────────────────────
    async def _cleanup_loop() -> None:
        from backend.app.services.job_store import job_store as _js

        while True:
            try:
                await _js.cleanup_expired_jobs(86400)
            except Exception as e:
                logger.error("neurocnl job cleanup error: %s", e)
            await asyncio.sleep(3600)

    _cleanup_task = asyncio.create_task(_cleanup_loop())
    logger.info("neurocnl lifespan startup complete")


async def neurocnl_shutdown() -> None:
    """Drain active jobs and cancel the cleanup task on shutdown."""
    global _cleanup_task

    try:
        from backend.app.services.job_store import job_store

        cancelled = await job_store.drain(timeout=10.0)
        if cancelled:
            logger.warning("neurocnl: shutdown cancelled %d active jobs", cancelled)
    except Exception as exc:
        logger.warning("neurocnl job_store drain failed: %s", exc)

    if _cleanup_task is not None and not _cleanup_task.done():
        _cleanup_task.cancel()
        _cleanup_task = None
