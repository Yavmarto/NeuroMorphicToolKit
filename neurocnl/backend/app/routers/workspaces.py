"""POST/GET /api/workspaces — server-side workspace persistence.

Lets a workspace's full pipeline/canvas/CNL config be synced to the
backend and later listed/opened from a different device pointed at the
same server.
"""

from __future__ import annotations

from fastapi import APIRouter, HTTPException, Request, Response

from backend.app.middleware.rate_limit import limiter
from backend.app.schemas.workspaces import (
    WorkspaceDetail,
    WorkspaceSummary,
    WorkspaceSummaryList,
    WorkspaceSyncRequest,
)
from backend.app.services.workspace_store import workspace_store

router = APIRouter()


@router.post("/workspaces/{slug}")
@limiter.limit("60/minute")
async def sync_workspace(
    request: Request, response: Response, slug: str, body: WorkspaceSyncRequest
) -> dict[str, str]:
    """Create or update the stored config for *slug*."""
    await workspace_store.upsert(slug, body.name, body.config)
    return {"slug": slug}


@router.get("/workspaces", response_model=WorkspaceSummaryList)
@limiter.limit("60/minute")
async def list_workspaces(request: Request, response: Response) -> WorkspaceSummaryList:
    """List every workspace saved on this server, most recently updated first."""
    items = await workspace_store.list_summaries()
    return WorkspaceSummaryList(items=[WorkspaceSummary(**item) for item in items])


@router.get("/workspaces/{slug}", response_model=WorkspaceDetail)
@limiter.limit("60/minute")
async def get_workspace(request: Request, response: Response, slug: str) -> WorkspaceDetail:
    """Fetch the full config for *slug*."""
    record = await workspace_store.get(slug)
    if record is None:
        raise HTTPException(status_code=404, detail=f"Workspace {slug!r} not found")
    return WorkspaceDetail(**record)
