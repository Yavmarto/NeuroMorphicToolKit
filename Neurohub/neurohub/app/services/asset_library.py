"""Service for managing shared assets in the NeuroHub asset library."""

import hashlib
import logging
import os
import uuid
from datetime import datetime, UTC
from pathlib import Path

from sqlalchemy.orm import Session

from neurohub.app.schemas.assets import SharedAsset
from neurohub.db.models import SharedAssetDB

logger = logging.getLogger(__name__)

# Mapping: asset_type -> (allowed MIME types, allowed file extensions).
# Extension check is the primary gate; MIME is a secondary check.
# Both must fail for a rejection (avoids false rejects when browsers send application/octet-stream).
_ASSET_TYPE_MIME: dict[str, tuple[set[str], set[str]]] = {
    "nir": (
        {"application/x-hdf", "application/x-hdf5", "application/octet-stream"},
        {".h5", ".hdf5", ".nir"},
    ),
    "cnl_spec": (
        {"application/json", "text/plain", "application/octet-stream"},
        {".json", ".cnl", ".txt"},
    ),
    "neurosim_template": (
        {"application/json", "text/plain", "application/octet-stream"},
        {".json", ".txt", ".bin"},
    ),
    "hardware_profile": (
        {"application/json", "text/plain", "application/octet-stream"},
        {".json", ".txt"},
    ),
    "benchmark_definition": (
        {"application/json", "text/plain", "application/octet-stream"},
        {".json", ".txt"},
    ),
    "studio_workspace": (
        {"application/json", "text/plain", "application/octet-stream"},
        {".nmtk", ".txt"},
    ),
    "neurosense_recording": (
        {"application/octet-stream", "application/x-hdf", "application/x-hdf5"},
        {".bin", ".h5", ".hdf5", ".edf"},
    ),
    "encoding_preset": (
        {"application/json", "text/plain", "application/octet-stream"},
        {".json", ".txt"},
    ),
}


def validate_upload(
    asset_type: str,
    filename: str,
    content_type: str | None,
    content_length: int,
) -> None:
    """Validate MIME type and file size for an uploaded asset.

    Rejects only when BOTH the file extension AND the MIME type fail the
    allowlist — this avoids false rejects when browsers send
    ``application/octet-stream`` for everything.

    Args:
        asset_type: The declared asset type (e.g. ``'nir'``, ``'cnl_spec'``).
        filename: The original filename from the upload (used for extension check).
        content_type: The Content-Type header from the upload (may be None).
        content_length: The size in bytes of the uploaded content.

    Raises:
        ValueError: If the file exceeds the configured size limit, or if both
            extension and MIME type fail the allowlist for the given asset type.
    """
    max_bytes = int(os.environ.get("NEUROHUB_MAX_UPLOAD_BYTES", str(500 * 1024 * 1024)))
    if content_length > max_bytes:
        raise ValueError(f"File size {content_length} bytes exceeds limit of {max_bytes} bytes")

    if os.environ.get("NEUROHUB_SKIP_ASSET_VALIDATION") == "true":
        return

    allowed_mimes, allowed_exts = _ASSET_TYPE_MIME.get(asset_type, (set(), set()))
    suffix = Path(filename).suffix.lower() if filename else ""

    # Reject only when extension fails AND MIME type also fails.
    if allowed_exts and suffix not in allowed_exts:
        ct = (content_type or "").split(";")[0].strip()
        if allowed_mimes and ct and ct not in allowed_mimes:
            raise ValueError(
                f"File type not allowed for asset type '{asset_type}'. "
                f"Expected extensions {allowed_exts}, got '{suffix}'"
            )


def get_assets(
    db: Session,
    asset_type: str | None = None,
    tags: list[str] | None = None,
    q: str | None = None,
    skip: int = 0,
    limit: int = 100,
) -> list[SharedAssetDB]:
    """Retrieve a list of shared assets, with optional filtering.

    Args:
        db (Session): SQLAlchemy database session.
        asset_type (str, optional): The type of asset to filter by. Defaults to None.
        tags (list[str], optional): A list of tags to filter by. Only returns assets
            matching at least one tag. Defaults to None.
        q (str, optional): Substring search applied to name and description
            (case-insensitive). Defaults to None.
        skip (int, optional): Number of records to skip for pagination. Defaults to 0.
        limit (int, optional): Maximum number of records to return. Defaults to 100.

    Returns:
        list[SharedAssetDB]: A list of asset records from the database.
    """
    query = db.query(SharedAssetDB)
    if asset_type:
        query = query.filter(SharedAssetDB.type == asset_type)
    # Tag and text filtering done in-memory since tags are JSON
    assets = query.offset(skip).limit(limit).all()
    if tags:
        assets = [a for a in assets if a.tags and any(t in a.tags for t in tags)]
    if q:
        q_lower = q.lower()
        assets = [
            a
            for a in assets
            if q_lower in (a.name or "").lower() or q_lower in (a.description or "").lower()
        ]
    return assets


def get_asset(db: Session, asset_id: str) -> SharedAssetDB | None:
    """Retrieve a single asset by its ID.

    Args:
        db (Session): SQLAlchemy database session.
        asset_id (str): The unique identifier of the asset.

    Returns:
        Optional[SharedAssetDB]: The asset record if found, else None.
    """
    return db.query(SharedAssetDB).filter(SharedAssetDB.id == asset_id).first()


def get_asset_file_path(db: Session, asset_id: str) -> Path | None:
    """Return the resolved absolute Path of an asset's file.

    Args:
        db (Session): SQLAlchemy database session.
        asset_id (str): The unique identifier of the asset.

    Returns:
        Path | None: The resolved absolute path if the asset exists, else None.

    Raises:
        FileNotFoundError: If the DB record exists but the file is missing on disk.
    """
    db_asset = get_asset(db, asset_id)
    if not db_asset:
        return None
    path = Path(db_asset.file_path).resolve()
    if not path.exists():
        raise FileNotFoundError(f"Asset file missing on disk: {db_asset.file_path}")
    return path


def _calculate_sha256(file_path: str) -> str:
    """Calculate the SHA-256 hash of a file.

    Args:
        file_path (str): Path to the file.

    Returns:
        str: The hex-encoded SHA-256 hash.

    Raises:
        FileNotFoundError: If the file does not exist.
    """
    if not Path(file_path).exists():
        raise FileNotFoundError(f"Asset file not found at {file_path}")

    sha256_hash = hashlib.sha256()
    with open(file_path, "rb") as f:
        # Read in 64kb chunks
        for byte_block in iter(lambda: f.read(65536), b""):
            sha256_hash.update(byte_block)
    return sha256_hash.hexdigest()


def _is_valid_nir(file_path: str) -> bool:
    """Validate that a file is a valid NIR model.

    NIR models are typically stored in HDF5 containers.
    This check verifies the HDF5 magic bytes.

    Args:
        file_path (str): Path to the file to validate.

    Returns:
        bool: True if it appears to be a valid NIR file, False otherwise.
    """
    if not Path(file_path).exists():
        return False

    # HDF5 magic bytes: \x89HDF\r\n\x1a\n
    hdf5_magic = b"\x89HDF\r\n\x1a\n"
    try:
        with open(file_path, "rb") as f:
            header = f.read(len(hdf5_magic))
            return header == hdf5_magic
    except Exception:
        return False


def _validate_asset_integrity(asset_type: str, file_path: str, expected_sha256: str) -> None:
    """Perform integrity and type-specific validation for an asset.

    Args:
        asset_type (str): The type of asset (e.g., 'nir').
        file_path (str): Path to the asset file.
        expected_sha256 (str): The expected SHA-256 hash.

    Raises:
        ValueError: If integrity or type validation fails.
        FileNotFoundError: If the file does not exist.
    """
    # For testing and dev bypass if file_path is dummy
    if os.environ.get("NEUROHUB_SKIP_ASSET_VALIDATION") == "true":
        # Ensure we still validate the hash format at least
        if expected_sha256 and not hashlib.sha256().hexdigest() == expected_sha256:
            # Basic check to see if it's 64 chars hex
            if not (
                len(expected_sha256) == 64
                and all(c in "0123456789abcdef" for c in expected_sha256.lower())
            ):
                raise ValueError("Invalid SHA-256 format")
        return

    # 1. Integrity Check (SHA-256)
    actual_sha256 = _calculate_sha256(file_path)
    if actual_sha256.lower() != expected_sha256.lower():
        raise ValueError(
            f"Integrity check failed: expected hash {expected_sha256}, got {actual_sha256}"
        )

    # 2. Type Validation (e.g., NIR)
    if asset_type == "nir":
        if not _is_valid_nir(file_path):
            raise ValueError(f"File at {file_path} is not a valid NIR model (invalid structure)")


def create_asset(db: Session, asset: SharedAsset) -> SharedAssetDB:
    """Create a new shared asset in the database.

    Args:
        db (Session): SQLAlchemy database session.
        asset (SharedAsset): The asset data to be created.

    Returns:
        SharedAssetDB: The newly created asset record.

    Raises:
        ValueError: If integrity or type validation fails.
        FileNotFoundError: If the file does not exist.
    """
    _validate_asset_integrity(asset.type, asset.file_path, asset.sha256)

    now = datetime.now(UTC).isoformat()
    db_asset = SharedAssetDB(
        id=asset.id or str(uuid.uuid4()),
        name=asset.name,
        description=asset.description,
        type=asset.type,
        version=asset.version,
        author=asset.author,
        tags=asset.tags,
        created_at=asset.created_at or now,
        file_path=asset.file_path,
        file_size_bytes=asset.file_size_bytes,
        sha256=asset.sha256,
        metadata_=asset.metadata,
    )
    db.add(db_asset)
    db.commit()
    db.refresh(db_asset)
    return db_asset


def update_asset(db: Session, asset_id: str, asset_update: SharedAsset) -> SharedAssetDB | None:
    """Update an asset, incrementing version (creates new version semantics).

    Args:
        db (Session): SQLAlchemy database session.
        asset_id (str): The unique identifier of the asset to update.
        asset_update (SharedAsset): The new asset data to apply.

    Returns:
        Optional[SharedAssetDB]: The updated asset record, or None if the asset was not found.

    Raises:
        ValueError: If integrity or type validation fails.
        FileNotFoundError: If the file does not exist.
    """
    db_asset = get_asset(db, asset_id)
    if not db_asset:
        return None

    _validate_asset_integrity(asset_update.type, asset_update.file_path, asset_update.sha256)

    db_asset.name = asset_update.name
    db_asset.description = asset_update.description
    db_asset.version = db_asset.version + 1
    db_asset.tags = asset_update.tags
    db_asset.file_path = asset_update.file_path
    db_asset.file_size_bytes = asset_update.file_size_bytes
    db_asset.sha256 = asset_update.sha256
    db_asset.metadata_ = asset_update.metadata
    db.commit()
    db.refresh(db_asset)
    return db_asset


def delete_asset(db: Session, asset_id: str) -> bool:
    """Delete an asset from the database and remove its physical file from disk.

    The physical file is deleted before the DB record is committed. If the file
    cannot be removed (permissions error, NFS issue, etc.), a warning is logged
    but the DB record is still cleaned up — orphaned file references are worse
    than orphaned files on disk.

    Args:
        db (Session): SQLAlchemy database session.
        asset_id (str): The unique identifier of the asset to delete.

    Returns:
        bool: True if the asset was deleted successfully, False if it was not found.
    """
    db_asset = get_asset(db, asset_id)
    if not db_asset:
        return False

    # Attempt physical deletion before committing the DB record removal.
    if db_asset.file_path:
        file_path = Path(db_asset.file_path)
        if file_path.exists():
            try:
                file_path.unlink()
            except OSError as exc:
                logger.warning("Could not delete asset file %s: %s", file_path, exc)
        else:
            logger.warning("Asset file already missing at deletion time: %s", file_path)

    db.delete(db_asset)
    db.commit()
    return True
