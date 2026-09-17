"""Registry search endpoint (``/api/v1/search``)."""

from __future__ import annotations

from fastapi import APIRouter, HTTPException, Query, Request, Response, status
from sqlalchemy.orm import Session
from fastapi import Depends

from neurohub.app.limiter import limiter
from neurohub.app.services.search_index import get_search_index
from neurohub.contracts.registry_contracts import SearchResponse
from neurohub.db.database import get_db

router = APIRouter(prefix="/search", tags=["Registry Search"])


@router.get("", response_model=SearchResponse)
@limiter.limit("60/minute")
def search_artefacts(
    request: Request,
    response: Response,
    q: str | None = None,
    type: str | None = None,
    owner: str | None = None,
    hardware_target: str | None = None,
    neuron_model: str | None = None,
    tags: str | None = Query(None, description="Comma-separated tags (match any)"),
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    db: Session = Depends(get_db),
) -> SearchResponse:
    """Search active artefacts with optional filters and pagination.

    Args:
        request: The incoming request (required by the rate limiter).
        response: The outgoing response (required by the rate limiter).
        q: Free-text query over slug and description.
        type: Exact artefact type filter.
        owner: Exact owner filter.
        hardware_target: Model-card hardware-target filter.
        neuron_model: Model-card neuron-model filter.
        tags: Comma-separated tags (OR semantics).
        page: 1-based page number.
        page_size: Page size (1-100).
        db: The database session.

    Returns:
        The paginated search results.

    Raises:
        HTTPException: ``422`` if pagination parameters are out of range.
    """
    del response
    if page < 1 or not 1 <= page_size <= 100:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="invalid pagination parameters",
        )
    tag_list = [t.strip() for t in tags.split(",") if t.strip()] if tags else None
    return get_search_index().search(
        db,
        q=q,
        type_=type,
        owner=owner,
        tags=tag_list,
        hardware_target=hardware_target,
        neuron_model=neuron_model,
        page=page,
        page_size=page_size,
    )
