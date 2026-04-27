"""Neurohub lifespan management for suite_api.

Runs Alembic migrations and starts the workflow worker loop on startup.
Called from suite_api/main.py's asynccontextmanager lifespan.
"""
import asyncio
import logging
import os
from pathlib import Path
from typing import Any

logger = logging.getLogger("suite_api.neurohub.lifespan")

_worker_task: asyncio.Task[Any] | None = None


async def neurohub_startup() -> None:
    """Run Neurohub startup tasks inside suite_api's lifespan."""
    global _worker_task

    # Point Neurohub's DB to the submodule's SQLite file (relative to repo root)
    # This can be overridden with NEUROHUB_DB_URL environment variable.
    from suite_api.config import settings
    _db_url = os.environ.get("NEUROHUB_DB_URL", settings.neurohub_db_url)
    os.environ.setdefault("NEUROHUB_DB_URL", _db_url)

    # Apply Alembic migrations (skippable in test environments)
    if os.environ.get("NEUROHUB_SKIP_MIGRATIONS") != "true":
        try:
            from alembic import command as alembic_command
            from alembic.config import Config as AlembicConfig
            _alembic_ini = Path(__file__).parents[3] / "Neurohub" / "alembic.ini"
            if _alembic_ini.exists():
                _alembic_cfg = AlembicConfig(str(_alembic_ini))
                alembic_command.upgrade(_alembic_cfg, "head")
                logger.info("Neurohub: Alembic migrations applied")
            else:
                logger.warning("Neurohub: alembic.ini not found at %s", _alembic_ini)
        except Exception as exc:
            logger.error("Neurohub: Alembic migration failed: %s", exc)

    # Start the workflow worker loop
    try:
        from neurohub.app.services.workflow_engine import workflow_worker_loop
        from neurohub.db.database import SessionLocal
        _worker_task = asyncio.create_task(workflow_worker_loop(SessionLocal))
        logger.info("Neurohub: workflow worker loop started")
    except Exception as exc:
        logger.error("Neurohub: workflow worker loop failed to start: %s", exc)


async def neurohub_shutdown() -> None:
    """Run Neurohub shutdown tasks inside suite_api's lifespan."""
    global _worker_task
    if _worker_task is not None:
        _worker_task.cancel()
        try:
            await _worker_task
        except asyncio.CancelledError:
            pass
        _worker_task = None
        logger.info("Neurohub: workflow worker loop stopped")
