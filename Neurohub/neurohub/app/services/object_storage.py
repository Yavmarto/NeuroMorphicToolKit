"""Object storage service for registry artefact blobs.

Wraps an S3-compatible backend (MinIO in dev, AWS S3 in cloud) when
``OBJECT_STORAGE_URL`` is configured, and falls back to a local filesystem
backend otherwise so the registry is runnable without external infrastructure.

Responsibilities: deterministic key construction with a path-traversal guard
(Property 24), SHA-256 computation at upload, a 5 GB size guard, presigned-URL
generation (S3 mode), and blob retrieval/deletion. Multipart upload for large
blobs is handled transparently by ``boto3``'s ``TransferConfig`` in S3 mode.
"""

from __future__ import annotations

import hashlib
import logging
import os
import shutil
from pathlib import Path
from typing import Any

logger = logging.getLogger(__name__)

MAX_BLOB_SIZE = 5 * 1024 * 1024 * 1024  # 5 GB (Requirement 9.6)
MULTIPART_THRESHOLD = 100 * 1024 * 1024  # 100 MB (Requirement 9.5)
PRESIGNED_URL_TTL_SECONDS = 3600  # 1 hour (Requirement 9.7)


class StorageUnavailableError(Exception):
    """Raised when the storage backend is unreachable (→ HTTP 503)."""


class BlobTooLargeError(Exception):
    """Raised when a blob exceeds :data:`MAX_BLOB_SIZE` (→ HTTP 413)."""


def build_storage_key(
    artefact_type: str, owner: str, slug: str, version: str, filename: str
) -> str:
    """Construct the canonical object-storage key for an artefact blob.

    Pattern: ``{type}/{owner}/{slug}/{version}/{filename}``. The filename is
    reduced to its basename and any path-traversal sequence is rejected
    (Property 24).

    Args:
        artefact_type: The artefact type key.
        owner: The artefact owner (``user`` or ``org/user``).
        slug: The artefact slug.
        version: The semantic version.
        filename: The original upload filename.

    Returns:
        The storage key.

    Raises:
        ValueError: If the resulting filename is empty or contains traversal.
    """
    safe_name = Path(filename).name
    if not safe_name or safe_name in {".", ".."}:
        raise ValueError("invalid artefact filename")
    key = f"{artefact_type}/{owner}/{slug}/{version}/{safe_name}"
    if ".." in key.split("/"):
        raise ValueError("storage key cannot contain traversal sequences")
    return key


def compute_sha256(data: bytes) -> str:
    """Return the hex SHA-256 digest of ``data``."""
    return hashlib.sha256(data).hexdigest()


class ObjectStorageService:
    """S3-compatible or local-filesystem store for artefact blobs."""

    def __init__(self) -> None:
        """Initialise the backend from environment configuration."""
        self._endpoint = os.environ.get("OBJECT_STORAGE_URL")
        self._bucket = os.environ.get("OBJECT_STORAGE_BUCKET", "neurohub-registry")
        self._local_root = Path(os.environ.get("OBJECT_STORAGE_LOCAL_PATH", "./registry_storage"))
        self._client: Any | None = None

    @property
    def backend(self) -> str:
        """Return ``"s3"`` when an S3 endpoint is configured, else ``"local"``."""
        return "s3" if self._endpoint else "local"

    def _s3(self) -> Any:
        """Return a cached boto3 S3 client, creating the bucket if needed.

        When ``OBJECT_STORAGE_SKIP_BUCKET_CREATE=true`` the auto-create step is
        skipped. This is required for Google Cloud Storage, whose S3-compatible
        XML API does not implement ``ListBuckets``. The GCS bucket must be
        created in the GCP console before first use.
        """
        if self._client is None:
            try:
                import boto3
                from botocore.client import Config

                self._client = boto3.client(
                    "s3",
                    endpoint_url=self._endpoint,
                    aws_access_key_id=os.environ.get("OBJECT_STORAGE_ACCESS_KEY", "minioadmin"),
                    aws_secret_access_key=os.environ.get("OBJECT_STORAGE_SECRET_KEY", "minioadmin"),
                    config=Config(signature_version="s3v4"),
                )
                skip_create = (
                    os.environ.get("OBJECT_STORAGE_SKIP_BUCKET_CREATE", "false").lower() == "true"
                )
                if not skip_create:
                    existing = {b["Name"] for b in self._client.list_buckets().get("Buckets", [])}
                    if self._bucket not in existing:
                        self._client.create_bucket(Bucket=self._bucket)
            except Exception as exc:  # noqa: BLE001 - any boto/network error is "unavailable"
                raise StorageUnavailableError(str(exc)) from exc
        return self._client

    def upload_blob(self, data: bytes, key: str) -> tuple[str, str, int]:
        """Store a blob and return ``(storage_key, sha256, size_bytes)``.

        Args:
            data: The raw blob bytes.
            key: The storage key (see :func:`build_storage_key`).

        Returns:
            The stored key, its SHA-256 digest, and its size in bytes.

        Raises:
            BlobTooLargeError: If the blob exceeds the 5 GB guard.
            StorageUnavailableError: If the backend write fails.
        """
        size = len(data)
        if size > MAX_BLOB_SIZE:
            raise BlobTooLargeError(f"blob size {size} exceeds {MAX_BLOB_SIZE} bytes")
        digest = compute_sha256(data)

        if self.backend == "s3":
            try:
                self._s3().put_object(Bucket=self._bucket, Key=key, Body=data)
            except StorageUnavailableError:
                raise
            except Exception as exc:  # noqa: BLE001
                raise StorageUnavailableError(str(exc)) from exc
        else:
            dest = self._local_root / key
            try:
                dest.parent.mkdir(parents=True, exist_ok=True)
                dest.write_bytes(data)
            except OSError as exc:
                raise StorageUnavailableError(str(exc)) from exc

        return key, digest, size

    def download_blob(self, key: str) -> bytes:
        """Retrieve the raw bytes for a stored blob.

        Args:
            key: The storage key.

        Returns:
            The blob bytes.

        Raises:
            StorageUnavailableError: If the backend read fails or the key is absent.
        """
        if self.backend == "s3":
            try:
                resp = self._s3().get_object(Bucket=self._bucket, Key=key)
                return bytes(resp["Body"].read())
            except StorageUnavailableError:
                raise
            except Exception as exc:  # noqa: BLE001
                raise StorageUnavailableError(str(exc)) from exc
        src = self._local_root / key
        try:
            return src.read_bytes()
        except OSError as exc:
            raise StorageUnavailableError(str(exc)) from exc

    def generate_presigned_url(self, key: str) -> str | None:
        """Return a presigned download URL (S3 mode) or ``None`` (local mode).

        Args:
            key: The storage key.

        Returns:
            A presigned URL valid for :data:`PRESIGNED_URL_TTL_SECONDS`, or
            ``None`` when the local backend is in use (the registry streams the
            blob itself instead).
        """
        if self.backend != "s3":
            return None
        try:
            url: str = self._s3().generate_presigned_url(
                "get_object",
                Params={"Bucket": self._bucket, "Key": key},
                ExpiresIn=PRESIGNED_URL_TTL_SECONDS,
            )
            return url
        except StorageUnavailableError:
            raise
        except Exception as exc:  # noqa: BLE001
            raise StorageUnavailableError(str(exc)) from exc

    def delete_blob(self, key: str) -> None:
        """Best-effort deletion of a stored blob; logs but does not raise on failure."""
        try:
            if self.backend == "s3":
                self._s3().delete_object(Bucket=self._bucket, Key=key)
            else:
                (self._local_root / key).unlink(missing_ok=True)
        except Exception as exc:  # noqa: BLE001 - cleanup is best-effort
            logger.warning("Failed to delete blob '%s': %s", key, exc)

    def is_available(self) -> bool:
        """Return whether the storage backend is currently reachable."""
        try:
            if self.backend == "s3":
                self._s3().list_buckets()
            else:
                self._local_root.mkdir(parents=True, exist_ok=True)
            return True
        except Exception:  # noqa: BLE001
            return False

    def reset_local(self) -> None:
        """Remove the local storage root (test helper; no-op in S3 mode)."""
        if self.backend == "local" and self._local_root.exists():
            shutil.rmtree(self._local_root)


_storage: ObjectStorageService | None = None


def get_object_storage() -> ObjectStorageService:
    """Return the process-wide :class:`ObjectStorageService` singleton."""
    global _storage
    if _storage is None:
        _storage = ObjectStorageService()
    return _storage
