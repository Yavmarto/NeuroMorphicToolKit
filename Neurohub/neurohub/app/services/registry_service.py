"""Persistence and versioning logic for registry artefacts.

Keeps the artefact router thin: blob upload + DB insert with storage atomicity,
semantic-version resolution, soft delete, and response projection.
"""

from __future__ import annotations

import logging
import uuid
from datetime import datetime, UTC

from sqlalchemy.orm import Session

from neurohub.app.services.object_storage import (
    ObjectStorageService,
    build_storage_key,
)
from neurohub.app.services.search_index import artefact_uri
from neurohub.contracts.registry_contracts import (
    ArtefactCreate,
    ArtefactResponse,
    ArtefactUpdate,
    ModelCard,
)
from neurohub.db.models import ArtefactDB

logger = logging.getLogger(__name__)


class DuplicateArtefactError(Exception):
    """Raised when ``(owner, slug, version)`` already exists (→ HTTP 409)."""


def _now_iso() -> str:
    """Return the current UTC time as an ISO 8601 string."""
    return datetime.now(UTC).isoformat()


def parse_semver(version: str) -> tuple[int, int, int]:
    """Parse a ``MAJOR.MINOR.PATCH`` string into a comparable integer tuple."""
    major, minor, patch = version.split(".")
    return int(major), int(minor), int(patch)


def get_artefact(db: Session, owner: str, slug: str, version: str) -> ArtefactDB | None:
    """Return the active artefact for an exact identifier, or ``None``."""
    return (
        db.query(ArtefactDB)
        .filter(
            ArtefactDB.owner == owner,
            ArtefactDB.slug == slug,
            ArtefactDB.version == version,
            ArtefactDB.deleted_at.is_(None),
        )
        .first()
    )


def get_latest(db: Session, owner: str, slug: str) -> ArtefactDB | None:
    """Return the highest-semver active artefact for ``{owner}/{slug}``."""
    rows = (
        db.query(ArtefactDB)
        .filter(
            ArtefactDB.owner == owner,
            ArtefactDB.slug == slug,
            ArtefactDB.deleted_at.is_(None),
        )
        .all()
    )
    if not rows:
        return None
    return max(rows, key=lambda a: parse_semver(a.version))


def list_versions(db: Session, owner: str, slug: str) -> list[ArtefactDB]:
    """Return all active versions for ``{owner}/{slug}`` in descending semver order."""
    rows = (
        db.query(ArtefactDB)
        .filter(
            ArtefactDB.owner == owner,
            ArtefactDB.slug == slug,
            ArtefactDB.deleted_at.is_(None),
        )
        .all()
    )
    return sorted(rows, key=lambda a: parse_semver(a.version), reverse=True)


def create_artefact(
    db: Session,
    storage: ObjectStorageService,
    *,
    owner: str,
    meta: ArtefactCreate,
    data: bytes,
    filename: str,
    warnings: list[str] | None = None,
) -> ArtefactDB:
    """Upload the blob and persist a new artefact record.

    Storage atomicity (Requirement 9.4 / design "Object Storage Atomicity"): the
    blob is uploaded first; if the DB insert then fails the blob is deleted on a
    best-effort basis.

    Args:
        db: The database session.
        storage: The object storage service.
        owner: The publisher (assigned from the authenticated user).
        meta: The validated metadata payload.
        data: The raw blob bytes.
        filename: The original upload filename.
        warnings: Optional stripped-field warnings to echo on the response.

    Returns:
        The persisted :class:`ArtefactDB`.

    Raises:
        DuplicateArtefactError: If ``(owner, slug, version)`` already exists.
        BlobTooLargeError / StorageUnavailableError: From the storage layer.
    """
    existing = (
        db.query(ArtefactDB)
        .filter(
            ArtefactDB.owner == owner,
            ArtefactDB.slug == meta.slug,
            ArtefactDB.version == meta.version,
        )
        .first()
    )
    if existing is not None:
        raise DuplicateArtefactError(f"{owner}/{meta.slug}@{meta.version} already exists")

    key = build_storage_key(meta.type.value, owner, meta.slug, meta.version, filename)
    storage_key, sha256, size = storage.upload_blob(data, key)

    now = _now_iso()
    artefact = ArtefactDB(
        id=str(uuid.uuid4()),
        type=meta.type.value,
        owner=owner,
        slug=meta.slug,
        version=meta.version,
        description=meta.description,
        tags=list(meta.tags),
        readme=meta.readme,
        sha256=sha256,
        storage_key=storage_key,
        file_size_bytes=size,
        download_count=0,
        average_rating=0.0,
        rating_count=0,
        model_card=meta.model_card.model_dump() if meta.model_card else None,
        created_at=now,
        updated_at=now,
        deleted_at=None,
    )
    db.add(artefact)
    try:
        db.commit()
    except Exception:
        db.rollback()
        storage.delete_blob(storage_key)
        raise
    db.refresh(artefact)
    if warnings:
        logger.info(
            "Artefact %s created with stripped model-card fields: %s", artefact.id, warnings
        )
    return artefact


def update_artefact(db: Session, artefact: ArtefactDB, update: ArtefactUpdate) -> ArtefactDB:
    """Apply a mutable-field update, leaving immutable fields untouched (Property 2)."""
    if update.description is not None:
        artefact.description = update.description
    if update.tags is not None:
        artefact.tags = list(update.tags)
    if update.readme is not None:
        artefact.readme = update.readme
    if update.model_card is not None:
        artefact.model_card = update.model_card.model_dump()
    artefact.updated_at = _now_iso()
    db.commit()
    db.refresh(artefact)
    return artefact


def soft_delete(db: Session, artefact: ArtefactDB) -> None:
    """Mark an artefact deleted (Property 3) without removing the row."""
    artefact.deleted_at = _now_iso()
    db.commit()


def to_response(
    artefact: ArtefactDB,
    *,
    download_url: str | None = None,
    warnings: list[str] | None = None,
) -> ArtefactResponse:
    """Project an artefact row into its full API response.

    Args:
        artefact: The artefact row.
        download_url: The resolved download URL (presigned or registry endpoint).
        warnings: Optional stripped-field warnings.

    Returns:
        The :class:`ArtefactResponse`.
    """
    card = ModelCard(**artefact.model_card) if artefact.model_card else None
    return ArtefactResponse(
        id=artefact.id,
        type=artefact.type,  # type: ignore[arg-type]
        owner=artefact.owner,
        slug=artefact.slug,
        version=artefact.version,
        description=artefact.description,
        tags=list(artefact.tags or []),
        readme=artefact.readme,
        sha256=artefact.sha256,
        file_size_bytes=artefact.file_size_bytes,
        download_count=artefact.download_count,
        average_rating=artefact.average_rating,
        rating_count=artefact.rating_count,
        model_card=card,
        created_at=artefact.created_at,
        updated_at=artefact.updated_at,
        neurohub_uri=artefact_uri(artefact),
        download_url=download_url,
        warnings=list(warnings or []),
    )
