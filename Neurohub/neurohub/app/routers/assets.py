"""Router for asset-related endpoints."""

import mimetypes
import os
from pathlib import Path
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Query, Request, Response, status
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session

from neurohub.app.auth import get_current_user, require_admin
from neurohub.app.limiter import limiter
from neurohub.app.schemas.assets import SharedAsset
from neurohub.app.services.asset_library import (
    create_asset,
    delete_asset,
    get_asset,
    get_asset_file_path,
    get_assets,
    update_asset,
)
from neurohub.db.database import get_db
from neurohub.db.models import SharedAssetDB

router = APIRouter(tags=["Assets"])


def _to_schema(db_asset: SharedAssetDB) -> SharedAsset:
    """Convert DB model to a typed SharedAsset response schema.

    Args:
        db_asset (SharedAssetDB): The database model instance.

    Returns:
        SharedAsset: A validated Pydantic schema instance.
    """
    # SharedAsset.type is a Literal, but the DB column is a plain str — go through
    # model_validate (from_attributes=True, with the metadata/metadata_ alias
    # already declared on the contract) so Pydantic does the runtime narrowing
    # instead of a field-by-field constructor call that mypy can't type-check.
    return SharedAsset.model_validate(db_asset)


@router.get(
    "/assets",
    response_model=list[SharedAsset],
    dependencies=[Depends(get_current_user)],
)
@limiter.limit("120/minute")
def list_assets(
    request: Request,
    response: Response,
    type: str | None = None,
    tags: str | None = Query(None, description="Comma-separated tags"),
    q: str | None = Query(None, description="Substring search on name and description"),
    db: Session = Depends(get_db),
) -> list[SharedAsset]:
    """List shared assets, optionally filtering by type, tags, or a search term.

    Args:
        request: The incoming HTTP request.
        response: The outgoing HTTP response.
        type: The type of asset to filter by.
        tags: Comma-separated tags to filter by.
        q: Substring to search within asset names and descriptions.
        db: SQLAlchemy database session.

    Returns:
        A list of assets matching the query.
    """
    tag_list = [t.strip() for t in tags.split(",")] if tags else None
    return [_to_schema(a) for a in get_assets(db, asset_type=type, tags=tag_list, q=q)]


@router.post(
    "/assets",
    response_model=SharedAsset,
    status_code=status.HTTP_201_CREATED,
    dependencies=[Depends(require_admin)],
)
@limiter.limit("30/minute")
async def add_asset(
    request: Request, response: Response, asset: SharedAsset, db: Session = Depends(get_db)
) -> SharedAsset:
    """Add a new shared asset to the library.

    Args:
        request: The incoming HTTP request.
        response: The outgoing HTTP response.
        asset: The asset data to create.
        db: SQLAlchemy database session.

    Returns:
        The created asset.

    Raises:
        HTTPException: If validation fails (400).
    """
    try:
        return _to_schema(create_asset(db, asset))
    except (ValueError, FileNotFoundError) as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e)) from e


@router.get(
    "/assets/{id}",
    response_model=SharedAsset,
    dependencies=[Depends(get_current_user)],
)
@limiter.limit("120/minute")
async def get_asset_detail(
    request: Request, response: Response, id: str, db: Session = Depends(get_db)
) -> SharedAsset:
    """Get metadata and details for a specific asset.

    Args:
        request: The incoming HTTP request.
        response: The outgoing HTTP response.
        id: The unique identifier of the asset.
        db: SQLAlchemy database session.

    Returns:
        The asset details.

    Raises:
        HTTPException: If the asset is not found (404).
    """
    db_asset = get_asset(db, id)
    if not db_asset:
        raise HTTPException(status_code=404, detail="Asset not found")
    return _to_schema(db_asset)


@router.get(
    "/assets/{id}/download",
    dependencies=[Depends(get_current_user)],
    response_class=FileResponse,
    summary="Download the raw file for an asset",
)
@limiter.limit("120/minute")
async def download_asset(
    request: Request,
    response: Response,
    id: str,
    db: Session = Depends(get_db),
) -> FileResponse:
    """Stream the raw file bytes for a stored asset.

    Args:
        request: The incoming HTTP request.
        response: The outgoing HTTP response.
        id: The unique identifier of the asset.
        db: SQLAlchemy database session.

    Returns:
        A FileResponse streaming the asset file as an attachment.

    Raises:
        HTTPException: 404 if the asset record is not found; 410 Gone if the
            DB record exists but the physical file is missing on disk; 403 if
            the resolved path escapes the configured storage directory.
    """
    del response
    try:
        path = get_asset_file_path(db, id)
    except FileNotFoundError as exc:
        raise HTTPException(status_code=status.HTTP_410_GONE, detail=str(exc)) from exc
    if path is None:
        raise HTTPException(status_code=404, detail="Asset not found")

    # Path-traversal guard: resolved path must stay under the storage directory.
    storage_base = Path(os.environ.get("NEUROHUB_ASSET_STORAGE_PATH", "./shared_assets")).resolve()
    if not str(path).startswith(str(storage_base)):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied")

    media_type, _ = mimetypes.guess_type(str(path))
    return FileResponse(
        path=str(path),
        media_type=media_type or "application/octet-stream",
        headers={"Content-Disposition": f'attachment; filename="{path.name}"'},
    )


@router.put(
    "/assets/{id}",
    response_model=SharedAsset,
    dependencies=[Depends(require_admin)],
)
@limiter.limit("30/minute")
async def update_asset_detail(
    request: Request,
    response: Response,
    id: str,
    asset: SharedAsset,
    db: Session = Depends(get_db),
) -> SharedAsset:
    """Update an existing asset, creating a new version.

    Args:
        request: The incoming HTTP request.
        response: The outgoing HTTP response.
        id: The unique identifier of the asset to update.
        asset: The updated asset data.
        db: SQLAlchemy database session.

    Returns:
        The updated asset.

    Raises:
        HTTPException: If the asset is not found (404) or validation fails (400).
    """
    try:
        db_asset = update_asset(db, id, asset)
        if not db_asset:
            raise HTTPException(status_code=404, detail="Asset not found")
        return _to_schema(db_asset)
    except (ValueError, FileNotFoundError) as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e)) from e


@router.delete(
    "/assets/{id}",
    status_code=status.HTTP_204_NO_CONTENT,
)
@limiter.limit("30/minute")
async def remove_asset(
    request: Request,
    response: Response,
    id: str,
    current_user: Any = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> None:
    """Remove an asset from the library.

    Allowed for the asset's original author or an admin user.

    Args:
        request: The incoming HTTP request.
        response: The outgoing HTTP response.
        id: The unique identifier of the asset to remove.
        current_user: The currently authenticated user.
        db: SQLAlchemy database session.

    Raises:
        HTTPException: 404 if the asset is not found; 403 if the caller is
            neither an admin nor the asset's author.
    """
    del response
    db_asset = get_asset(db, id)
    if not db_asset:
        raise HTTPException(status_code=404, detail="Asset not found")

    username: str = (
        current_user.get("sub", "")
        if isinstance(current_user, dict)
        else getattr(current_user, "username", "")
    )
    is_admin: bool = (
        current_user.get("role") == "admin"
        if isinstance(current_user, dict)
        else getattr(current_user, "is_admin", False)
    )
    if not is_admin and db_asset.author != username:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Forbidden")

    delete_asset(db, id)
