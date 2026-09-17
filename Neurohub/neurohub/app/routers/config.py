"""Router for suite configuration endpoints."""

from fastapi import APIRouter, Depends, Request, Response
from sqlalchemy.orm import Session

from neurohub.app.auth import require_admin
from neurohub.app.limiter import limiter
from neurohub.app.schemas.config import SuiteConfig
from neurohub.app.services.config_service import get_config, update_config
from neurohub.db.database import get_db

router = APIRouter(tags=["Config"])


@router.get("/config", response_model=SuiteConfig)
@limiter.limit("120/minute")
async def get_suite_config(
    request: Request, response: Response, db: Session = Depends(get_db)
) -> SuiteConfig:
    """Retrieve the current suite configuration.

    Args:
        request: The incoming HTTP request.
        response: The outgoing HTTP response.
        db: SQLAlchemy database session.

    Returns:
        The current suite configuration.
    """
    return get_config(db)


@router.put(
    "/config",
    response_model=SuiteConfig,
    dependencies=[Depends(require_admin)],
)
@limiter.limit("30/minute")
async def update_suite_config(
    request: Request, response: Response, config: SuiteConfig, db: Session = Depends(get_db)
) -> SuiteConfig:
    """Update the suite configuration.

    Args:
        request: The incoming HTTP request.
        response: The outgoing HTTP response.
        config: The new suite configuration data.
        db: SQLAlchemy database session.

    Returns:
        The updated suite configuration.
    """
    return update_config(db, config)
