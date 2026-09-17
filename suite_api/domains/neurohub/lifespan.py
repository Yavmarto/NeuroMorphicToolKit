"""Neurohub lifespan management for suite_api.

Runs Alembic migrations on startup. Called from suite_api/main.py's
asynccontextmanager lifespan.
"""

import logging
import os
from pathlib import Path

logger = logging.getLogger("suite_api.neurohub.lifespan")


async def neurohub_startup() -> None:
    """Run Neurohub startup tasks inside suite_api's lifespan."""
    from suite_api.config import settings

    _db_url = os.environ.get("NEUROHUB_DB_URL", settings.neurohub_db_url)
    os.environ.setdefault("NEUROHUB_DB_URL", _db_url)

    if os.environ.get("NEUROHUB_SKIP_MIGRATIONS") != "true":
        try:
            from alembic import command as alembic_command
            from alembic.config import Config as AlembicConfig

            _repo_root = Path(os.environ.get("NMTK_REPO_ROOT", "/repo"))
            _dev_root = Path(__file__).resolve().parents[3]
            _alembic_ini = _repo_root / "Neurohub" / "alembic.ini"
            if not _alembic_ini.exists():
                _alembic_ini = _dev_root / "Neurohub" / "alembic.ini"
            if _alembic_ini.exists():
                _alembic_cfg = AlembicConfig(str(_alembic_ini))
                alembic_command.upgrade(_alembic_cfg, "head")
                logger.info("Neurohub: Alembic migrations applied")
            else:
                logger.warning("Neurohub: alembic.ini not found at %s", _alembic_ini)
        except Exception as exc:
            logger.error("Neurohub: Alembic migration failed: %s", exc)


async def neurohub_shutdown() -> None:
    """Run Neurohub shutdown tasks inside suite_api's lifespan."""
    logger.info("Neurohub: shutdown complete")
