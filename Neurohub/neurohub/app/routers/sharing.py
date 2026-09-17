"""Sharing-space router — public feed and personal shares."""

import hashlib
import json
import logging
import mimetypes
import os
import uuid
from datetime import datetime, UTC
from pathlib import Path
from typing import Any

from fastapi import (
    APIRouter,
    Depends,
    File,
    Form,
    HTTPException,
    Request,
    Response,
    UploadFile,
    status,
)
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session

from neurohub.app.auth import get_current_user
from neurohub.app.limiter import limiter
from neurohub.app.schemas.assets import SharedAsset
from neurohub.app.services.asset_library import (
    create_asset,
    delete_asset,
    get_asset,
    get_asset_file_path,
    get_assets,
    validate_upload,
)
from neurohub.db.database import get_db
from neurohub.db.models import SharedAssetDB

logger = logging.getLogger(__name__)

router = APIRouter(tags=["Sharing"])


def _to_schema(db_asset: SharedAssetDB) -> SharedAsset:
    # SharedAsset.type is a Literal, but the DB column is a plain str — go through
    # model_validate (from_attributes=True, with the metadata/metadata_ alias
    # already declared on the contract) so Pydantic does the runtime narrowing
    # instead of a field-by-field constructor call that mypy can't type-check.
    return SharedAsset.model_validate(db_asset)


@router.get(
    "/feed",
    response_model=list[SharedAsset],
    dependencies=[Depends(get_current_user)],
    summary="Public feed of recently shared assets",
)
@limiter.limit("120/minute")
def get_feed(
    request: Request,
    response: Response,
    limit: int = 50,
    db: Session = Depends(get_db),
) -> list[SharedAsset]:
    """Return the most recently shared assets across all users, newest first."""
    assets = get_assets(db)
    # Sort by created_at descending and cap at limit.
    sorted_assets = sorted(
        assets,
        key=lambda a: a.created_at or "",
        reverse=True,
    )
    return [_to_schema(a) for a in sorted_assets[:limit]]


@router.get(
    "/feed/unread-count",
    summary="Count of new feed items since last check",
)
@limiter.limit("120/minute")
def get_feed_unread_count(
    request: Request,
    response: Response,
    db: Session = Depends(get_db),
) -> dict[str, int]:
    """Return the total count of assets in the feed (proxy for unread count)."""
    assets = get_assets(db)
    return {"count": len(assets)}


@router.get(
    "/shares",
    response_model=list[SharedAsset],
    dependencies=[Depends(get_current_user)],
    summary="Assets shared by the current user",
)
@limiter.limit("120/minute")
def get_my_shares(
    request: Request,
    response: Response,
    current_user: Any = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> list[SharedAsset]:
    """Return assets shared by the currently authenticated user."""
    all_assets = get_assets(db)
    # Filter by author matching the current user's identity.
    # current_user may be a dict or object depending on auth impl.
    username: str = (
        current_user.get("sub", "")
        if isinstance(current_user, dict)
        else getattr(current_user, "username", "")
    )
    user_assets = [a for a in all_assets if a.author == username]
    return [_to_schema(a) for a in user_assets]


@router.post(
    "/shares",
    response_model=SharedAsset,
    status_code=status.HTTP_201_CREATED,
)
@limiter.limit("30/minute")
async def create_share(
    request: Request,
    response: Response,
    name: str = Form(...),
    description: str = Form(...),
    asset_type: str = Form(..., alias="type"),
    tags: str = Form("[]"),
    metadata: str = Form("{}"),
    file: UploadFile = File(...),
    current_user: Any = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> SharedAsset:
    """Accept a multipart file upload and register it as a shared asset.

    Args:
        request: The incoming HTTP request.
        response: The outgoing HTTP response.
        name: Human-readable name for the asset.
        description: Short description of the asset.
        asset_type: One of the valid asset type literals.
        tags: JSON-encoded list of tag strings.
        metadata: JSON-encoded metadata dict.
        file: The uploaded asset file.
        current_user: The currently authenticated user.
        db: SQLAlchemy database session.

    Returns:
        The newly created shared asset.

    Raises:
        HTTPException: 400 if the payload is malformed; 500 on storage failure.
    """
    del response

    try:
        parsed_tags: list[str] = json.loads(tags)
        parsed_metadata: dict[str, Any] = json.loads(metadata)
    except json.JSONDecodeError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invalid JSON in tags or metadata: {exc}",
        ) from exc

    storage_dir = os.environ.get("NEUROHUB_ASSET_STORAGE_PATH", "./shared_assets")
    os.makedirs(storage_dir, exist_ok=True)

    suffix = Path(file.filename or "asset").suffix or ".bin"
    asset_id = str(uuid.uuid4())
    save_path = os.path.join(storage_dir, f"{asset_id}{suffix}")

    content = await file.read()

    # Validate size and MIME type before writing to disk.
    try:
        validate_upload(
            asset_type=asset_type,
            filename=file.filename or "",
            content_type=file.content_type,
            content_length=len(content),
        )
    except ValueError as exc:
        msg = str(exc)
        if "exceeds limit" in msg:
            raise HTTPException(
                status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                detail=msg,
            ) from exc
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail=msg,
        ) from exc

    try:
        with open(save_path, "wb") as fh:
            fh.write(content)
    except OSError as exc:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to save asset file: {exc}",
        ) from exc

    sha256 = hashlib.sha256(content).hexdigest()
    file_size = len(content)

    username: str = (
        current_user.get("sub", "unknown")
        if isinstance(current_user, dict)
        else getattr(current_user, "username", "unknown")
    )

    now = datetime.now(UTC).isoformat()

    asset_contract = SharedAsset(
        id=asset_id,
        name=name,
        description=description,
        type=asset_type,  # type: ignore[arg-type]
        version=1,
        author=username,
        tags=parsed_tags,
        created_at=now,
        file_path=save_path,
        file_size_bytes=file_size,
        sha256=sha256,
        metadata=parsed_metadata,
    )

    db_asset = create_asset(db, asset_contract)
    return _to_schema(db_asset)


@router.get(
    "/shares/{id}",
    response_model=SharedAsset,
    dependencies=[Depends(get_current_user)],
)
@limiter.limit("120/minute")
async def get_share_detail(
    request: Request,
    response: Response,
    id: str,
    db: Session = Depends(get_db),
) -> SharedAsset:
    """Get metadata and details for a specific shared asset.

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
    "/shares/{id}/download",
    dependencies=[Depends(get_current_user)],
    response_class=FileResponse,
    summary="Download the raw file for a shared asset",
)
@limiter.limit("120/minute")
async def download_share(
    request: Request,
    response: Response,
    id: str,
    db: Session = Depends(get_db),
) -> FileResponse:
    """Stream the raw file bytes for a shared asset.

    Args:
        request: The incoming HTTP request.
        response: The outgoing HTTP response.
        id: The unique identifier of the shared asset.
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

    # Path-traversal guard.
    storage_base = Path(os.environ.get("NEUROHUB_ASSET_STORAGE_PATH", "./shared_assets")).resolve()
    if not str(path).startswith(str(storage_base)):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied")

    media_type, _ = mimetypes.guess_type(str(path))
    return FileResponse(
        path=str(path),
        media_type=media_type or "application/octet-stream",
        headers={"Content-Disposition": f'attachment; filename="{path.name}"'},
    )


@router.delete(
    "/shares/{id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Delete a shared asset (author or admin only)",
)
@limiter.limit("30/minute")
async def delete_share(
    request: Request,
    response: Response,
    id: str,
    current_user: Any = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> None:
    """Delete a shared asset. Only the asset's author or an admin may do this.

    Args:
        request: The incoming HTTP request.
        response: The outgoing HTTP response.
        id: The unique identifier of the shared asset.
        current_user: The currently authenticated user.
        db: SQLAlchemy database session.

    Raises:
        HTTPException: 404 if the asset is not found; 403 if the caller is
            neither the asset's author nor an admin.
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
