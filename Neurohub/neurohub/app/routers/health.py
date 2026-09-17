"""Router for health-related endpoints."""

from fastapi import APIRouter, Depends
from sqlalchemy import text
from sqlalchemy.orm import Session

from neurohub.app.schemas.health import SelfHealthResponse
from neurohub.db.database import get_db

router = APIRouter(tags=["Health"])

# Version read at import time
try:
    from importlib.metadata import version as _pkg_version

    _NEUROHUB_VERSION = _pkg_version("neurohub")
except Exception:
    _NEUROHUB_VERSION = "0.1.0"


@router.get("/health", response_model=SelfHealthResponse)
async def check_health(db: Session = Depends(get_db)) -> SelfHealthResponse:
    """Check NeuroHub's own health (database connectivity + version).

    This endpoint checks only NeuroHub's local status, not the health
    of other suite services. Suite-wide health monitoring belongs to nmtk.
    """
    db_status = "connected"
    try:
        db.execute(text("SELECT 1"))
    except Exception:
        db_status = "unreachable"

    return SelfHealthResponse(
        status="ok" if db_status == "connected" else "degraded",
        database=db_status,
        version=_NEUROHUB_VERSION,
    )
