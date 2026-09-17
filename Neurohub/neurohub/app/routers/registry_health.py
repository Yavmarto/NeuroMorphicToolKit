"""Registry health endpoint (``/api/v1/health``)."""

from __future__ import annotations

from fastapi import APIRouter, Depends, Request, Response
from sqlalchemy import text
from sqlalchemy.orm import Session

from neurohub.app.limiter import limiter
from neurohub.app.services.object_storage import get_object_storage
from neurohub.db.database import get_db

router = APIRouter(prefix="/health", tags=["Registry Health"])

_VERSION = "0.6.0"


@router.get("")
@limiter.limit("120/minute")
def registry_health(
    request: Request, response: Response, db: Session = Depends(get_db)
) -> dict[str, str]:
    """Report registry liveness, DB connectivity, and storage connectivity.

    Returns:
        A status object with ``status``, ``db``, ``storage`` and ``version`` keys.
        ``status`` is ``"ok"`` only when both the database and object storage are
        reachable, otherwise ``"degraded"``.
    """
    del response
    try:
        db.execute(text("SELECT 1"))
        db_ok = True
    except Exception:  # noqa: BLE001
        db_ok = False

    storage_ok = get_object_storage().is_available()
    status_value = "ok" if (db_ok and storage_ok) else "degraded"
    return {
        "status": status_value,
        "db": "connected" if db_ok else "disconnected",
        "storage": "connected" if storage_ok else "disconnected",
        "version": _VERSION,
    }
