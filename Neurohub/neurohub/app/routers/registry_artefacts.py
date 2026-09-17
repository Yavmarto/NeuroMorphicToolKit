"""Registry artefact endpoints (``/api/v1/artefacts``)."""

from __future__ import annotations

import json
from typing import Annotated

from fastapi import (
    APIRouter,
    BackgroundTasks,
    Depends,
    File,
    Form,
    HTTPException,
    Request,
    Response,
    UploadFile,
    status,
)
from fastapi.responses import RedirectResponse
from pydantic import ValidationError
from sqlalchemy.orm import Session

from neurohub.app.limiter import limiter
from neurohub.app.registry_security import (
    RegistryUser,
    ensure_owner_or_admin,
    get_registry_user,
    user_or_ip_key,
)
from neurohub.app.services import registry_service
from neurohub.app.services.object_storage import (
    BlobTooLargeError,
    StorageUnavailableError,
    compute_sha256,
    get_object_storage,
)
from neurohub.contracts.registry_contracts import (
    ArtefactCreate,
    ArtefactResponse,
    ArtefactUpdate,
    ModelCard,
)
from neurohub.db.database import get_db

router = APIRouter(prefix="/artefacts", tags=["Registry Artefacts"])


def _download_path(owner: str, slug: str, version: str) -> str:
    """Build the registry-relative download URL for an artefact version."""
    return f"/api/v1/artefacts/{owner}/{slug}/{version}/download"


def _parse_tags(raw: str | None) -> list[str]:
    """Parse the ``tags`` form field from JSON array or comma-separated text."""
    if not raw:
        return []
    raw = raw.strip()
    if raw.startswith("["):
        try:
            parsed = json.loads(raw)
            return [str(t) for t in parsed]
        except json.JSONDecodeError:
            pass
    return [t.strip() for t in raw.split(",") if t.strip()]


def _parse_model_card(raw: str | None) -> tuple[ModelCard | None, list[str]]:
    """Parse a model-card JSON string, returning the card and stripped-field warnings.

    Unrecognised fields are stripped and named in the warnings list (Property 25).
    """
    if not raw:
        return None, []
    try:
        data = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"model_card is not valid JSON: {exc}",
        ) from exc
    if not isinstance(data, dict):
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="model_card must be a JSON object",
        )
    known = set(ModelCard.model_fields.keys())
    warnings = sorted(k for k in data if k not in known)
    return ModelCard(**{k: v for k, v in data.items() if k in known}), warnings


@router.post("", response_model=ArtefactResponse, status_code=status.HTTP_201_CREATED)
@limiter.limit("300/minute", key_func=user_or_ip_key)
async def create_artefact(
    request: Request,
    response: Response,
    background_tasks: BackgroundTasks,
    file: Annotated[UploadFile, File(description="The artefact blob")],
    type: Annotated[str, Form()],
    slug: Annotated[str, Form()],
    version: Annotated[str, Form()],
    description: Annotated[str | None, Form()] = None,
    tags: Annotated[str | None, Form()] = None,
    readme: Annotated[str | None, Form()] = None,
    model_card: Annotated[str | None, Form()] = None,
    user: RegistryUser = Depends(get_registry_user),
    db: Session = Depends(get_db),
) -> ArtefactResponse:
    """Publish a new artefact version (multipart blob + metadata).

    Returns:
        The created artefact, including its canonical ``neurohub://`` URI.

    Raises:
        HTTPException: ``422`` invalid metadata; ``409`` duplicate identifier;
            ``413`` blob too large; ``503`` storage unavailable.
    """
    del response
    card, warnings = _parse_model_card(model_card)
    try:
        meta = ArtefactCreate(
            type=type,  # type: ignore[arg-type]
            slug=slug,
            version=version,
            description=description,
            tags=_parse_tags(tags),
            readme=readme,
            model_card=card,
        )
    except ValidationError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail=exc.errors()
        ) from exc

    data = await file.read()
    storage = get_object_storage()
    try:
        artefact = registry_service.create_artefact(
            db,
            storage,
            owner=user.username,
            meta=meta,
            data=data,
            filename=file.filename or f"{slug}-{version}",
            warnings=warnings,
        )
    except registry_service.DuplicateArtefactError as exc:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(exc)) from exc
    except BlobTooLargeError as exc:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE, detail=str(exc)
        ) from exc
    except StorageUnavailableError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail="storage unavailable"
        ) from exc

    return registry_service.to_response(
        artefact,
        download_url=_download_path(artefact.owner, artefact.slug, artefact.version),
        warnings=warnings,
    )


@router.get("/{owner}/{slug}/versions", response_model=list[str])
@limiter.limit("60/minute")
def list_versions(
    request: Request, response: Response, owner: str, slug: str, db: Session = Depends(get_db)
) -> list[str]:
    """Return all versions for ``{owner}/{slug}`` in descending semver order."""
    del response
    versions = registry_service.list_versions(db, owner, slug)
    if not versions:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="artefact not found")
    return [a.version for a in versions]


@router.get("/{owner}/{slug}/{version}/download")
@limiter.limit("300/minute", key_func=user_or_ip_key)
def download_artefact(
    request: Request,
    response: Response,
    owner: str,
    slug: str,
    version: str,
    db: Session = Depends(get_db),
) -> Response:
    """Serve the artefact blob (presigned redirect in S3 mode, stream in local mode).

    Verifies the stored blob's checksum against the recorded digest before
    serving in local mode (Property 4).

    Raises:
        HTTPException: ``404`` if absent; ``503`` storage unavailable; ``500`` on
            checksum mismatch.
    """
    del response
    artefact = registry_service.get_artefact(db, owner, slug, version)
    if artefact is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="artefact not found")

    storage = get_object_storage()
    try:
        presigned = storage.generate_presigned_url(artefact.storage_key)
    except StorageUnavailableError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail="storage unavailable"
        ) from exc

    artefact.download_count += 1
    db.commit()

    if presigned is not None:
        return RedirectResponse(url=presigned, status_code=status.HTTP_302_FOUND)

    try:
        blob = storage.download_blob(artefact.storage_key)
    except StorageUnavailableError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail="storage unavailable"
        ) from exc
    if compute_sha256(blob) != artefact.sha256:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="checksum mismatch"
        )
    filename = artefact.storage_key.rsplit("/", 1)[-1]
    return Response(
        content=blob,
        media_type="application/octet-stream",
        headers={
            "Content-Disposition": f'attachment; filename="{filename}"',
            "X-Artefact-SHA256": artefact.sha256,
        },
    )


@router.get("/{owner}/{slug}/{version}", response_model=ArtefactResponse)
@limiter.limit("60/minute")
def get_artefact_version(
    request: Request,
    response: Response,
    owner: str,
    slug: str,
    version: str,
    db: Session = Depends(get_db),
) -> ArtefactResponse:
    """Retrieve a specific artefact version with its download URL."""
    del response
    artefact = registry_service.get_artefact(db, owner, slug, version)
    if artefact is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="artefact not found")
    return registry_service.to_response(artefact, download_url=_download_path(owner, slug, version))


@router.get("/{owner}/{slug}", response_model=ArtefactResponse)
@limiter.limit("60/minute")
def get_latest_artefact(
    request: Request, response: Response, owner: str, slug: str, db: Session = Depends(get_db)
) -> ArtefactResponse:
    """Resolve ``{owner}/{slug}`` to its highest-semver active version."""
    del response
    artefact = registry_service.get_latest(db, owner, slug)
    if artefact is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="artefact not found")
    return registry_service.to_response(
        artefact, download_url=_download_path(owner, slug, artefact.version)
    )


@router.put("/{owner}/{slug}/{version}", response_model=ArtefactResponse)
@limiter.limit("300/minute", key_func=user_or_ip_key)
def update_artefact_version(
    request: Request,
    response: Response,
    owner: str,
    slug: str,
    version: str,
    body: ArtefactUpdate,
    user: RegistryUser = Depends(get_registry_user),
    db: Session = Depends(get_db),
) -> ArtefactResponse:
    """Update mutable fields of an artefact version (owner or admin only)."""
    del response
    artefact = registry_service.get_artefact(db, owner, slug, version)
    if artefact is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="artefact not found")
    ensure_owner_or_admin(user, artefact.owner)
    updated = registry_service.update_artefact(db, artefact, body)
    return registry_service.to_response(updated, download_url=_download_path(owner, slug, version))


@router.delete("/{owner}/{slug}/{version}", status_code=status.HTTP_204_NO_CONTENT)
@limiter.limit("300/minute", key_func=user_or_ip_key)
def delete_artefact_version(
    request: Request,
    response: Response,
    owner: str,
    slug: str,
    version: str,
    background_tasks: BackgroundTasks,
    user: RegistryUser = Depends(get_registry_user),
    db: Session = Depends(get_db),
) -> None:
    """Soft-delete an artefact version (owner or admin only)."""
    del response
    artefact = registry_service.get_artefact(db, owner, slug, version)
    if artefact is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="artefact not found")
    ensure_owner_or_admin(user, artefact.owner)
    registry_service.soft_delete(db, artefact)


__all__: list[str] = ["router"]
