"""GET/POST /api/datasets — catalog and server-side Firebase downloads."""

from __future__ import annotations

import uuid
from pathlib import Path
from typing import Annotated

from fastapi import APIRouter, File, Form, HTTPException, Request, Response, UploadFile
from fastapi.responses import JSONResponse

from backend.app.middleware.rate_limit import limiter
from backend.app.schemas.datasets import (
    DatasetDownloadResponse,
    DatasetEntryResponse,
    DatasetFolderResponse,
    DatasetImportLocalResponse,
    DatasetListResponse,
    DatasetPathExistsResponse,
    DatasetRawUploadResponse,
)
from backend.app.services.dataset_cache import (
    DATA_DIR,
    DatasetDownloadError,
    DatasetIntegrityError,
    DatasetNotFoundError,
    FirebaseNotConfiguredError,
    LocalDatasetImportError,
    dataset_cache,
    firebase_bucket_configured,
)
from backend.app.services.dataset_catalog import (
    LOCAL_DATASET_FOLDER_PATH,
    FirebaseCatalogError,
    load_dataset_catalog,
)

router = APIRouter()


def _map_dataset_exception(
    exc: Exception,
    *,
    fallback: str = "Dataset download failed unexpectedly.",
) -> HTTPException:
    """Map a dataset failure onto an HTTP error.

    `fallback` exists because every caller shares this function but they are
    not all downloading. A listing failure reported as "Dataset download
    failed" sends the reader looking for a download that never started — which
    is exactly what happened when a schema error in the registry surfaced under
    the download wording.
    """
    if isinstance(exc, DatasetNotFoundError):
        return HTTPException(status_code=404, detail=str(exc))
    if isinstance(exc, FirebaseNotConfiguredError):
        return HTTPException(status_code=503, detail=str(exc))
    if isinstance(exc, FirebaseCatalogError):
        return HTTPException(status_code=503, detail=str(exc))
    if isinstance(exc, DatasetIntegrityError):
        return HTTPException(status_code=409, detail=str(exc))
    if isinstance(exc, DatasetDownloadError):
        return HTTPException(status_code=503, detail=str(exc))
    if isinstance(exc, OSError) and exc.errno == 28:  # ENOSPC
        return HTTPException(
            status_code=507,
            detail=(
                "Server disk is full. Free space under NEUROCNL_DATA_DIR or choose a smaller dataset."
            ),
        )
    return HTTPException(status_code=500, detail=fallback)


@router.get("/datasets", response_model=DatasetListResponse)
async def list_datasets() -> DatasetListResponse:
    try:
        from pathlib import Path

        items, firebase_ok = await dataset_cache.list_entries_with_availability()
        dataset_entries = [DatasetEntryResponse(**item) for item in items]

        folders_map: dict[str, dict] = {}
        for entry in dataset_entries:
            fp = (entry.folder_path or "").rstrip("/")
            fp_key = fp or "/"
            if fp_key not in folders_map:
                if fp == LOCAL_DATASET_FOLDER_PATH.rstrip("/"):
                    folder_name = "Local imports"
                else:
                    folder_name = Path(fp).name if fp else "Root"
                folders_map[fp_key] = {
                    "folder_name": folder_name,
                    "folder_path": entry.folder_path or "",
                    "description": entry.description,
                    "files": [],
                }
            folders_map[fp_key]["files"].append(entry)

        folders = sorted(
            (DatasetFolderResponse(**data) for data in folders_map.values()),
            key=lambda f: f.folder_name.lower(),
        )

        return DatasetListResponse(
            firebase_available=firebase_ok and firebase_bucket_configured(),
            datasets=dataset_entries,
            folders=folders,
        )
    except Exception as exc:
        raise _map_dataset_exception(
            exc,
            fallback=(
                "The dataset catalog could not be read. Check the backend logs; "
                "no dataset can be selected until this is resolved."
            ),
        ) from exc


@router.post(
    "/datasets/import-local",
    response_model=DatasetImportLocalResponse,
)
@limiter.limit("30/minute")
async def import_local_dataset(
    request: Request,
    response: Response,
    file: Annotated[UploadFile | None, File()] = None,
    server_path: Annotated[str | None, Form()] = None,
) -> DatasetImportLocalResponse:
    """Import a neuromorphic dataset from the user's device into the server cache."""
    resolved_server_path = server_path.strip() if server_path else None
    if file is None and not resolved_server_path:
        content_type = request.headers.get("content-type", "")
        if "application/json" in content_type:
            payload = await request.json()
            if isinstance(payload, dict) and payload.get("server_path"):
                raw_path = payload["server_path"]
                resolved_server_path = str(raw_path).strip()

    try:
        if file is not None:
            filename = Path(file.filename or "dataset.bin").name
            file_bytes = await file.read()
            if not file_bytes:
                raise HTTPException(
                    status_code=422,
                    detail="Uploaded dataset file is empty.",
                )
            item = await dataset_cache.register_local_dataset(
                filename=filename,
                file_bytes=file_bytes,
            )
        elif resolved_server_path:
            item = await dataset_cache.register_local_dataset(
                filename=Path(resolved_server_path).name,
                server_path=resolved_server_path,
            )
        else:
            raise HTTPException(
                status_code=422,
                detail=("Provide a dataset file upload or a server_path JSON/form field."),
            )
    except LocalDatasetImportError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    except OSError as exc:
        if exc.errno == 28:
            raise HTTPException(
                status_code=507,
                detail=(
                    "Server disk is full. Free space under NEUROCNL_DATA_DIR "
                    "or choose a smaller dataset."
                ),
            ) from exc
        raise HTTPException(
            status_code=503,
            detail=f"Could not import dataset on the server: {exc}",
        ) from exc

    return DatasetImportLocalResponse(**item)


@router.post(
    "/datasets/upload-raw",
    response_model=DatasetRawUploadResponse,
)
@limiter.limit("30/minute")
async def upload_raw_dataset_file(
    request: Request,
    response: Response,
    file: Annotated[UploadFile, File()],
) -> DatasetRawUploadResponse:
    """Upload arbitrary bytes to a server path, for pipeline nodes (e.g. the
    Data Loader node's dataset_path) that reference a raw file rather than a
    catalog entry. Unlike /datasets/import-local, this does not register a
    dataset-catalog entry and does not gate on supported dataset formats."""
    safe_name = Path(file.filename or "upload.bin").name
    file_bytes = await file.read()
    if not file_bytes:
        raise HTTPException(status_code=422, detail="Uploaded file is empty.")

    dest_dir = DATA_DIR / "pipeline_uploads" / uuid.uuid4().hex
    try:
        dest_dir.mkdir(parents=True, exist_ok=True)
        dest_path = dest_dir / safe_name
        dest_path.write_bytes(file_bytes)
    except OSError as exc:
        if exc.errno == 28:
            raise HTTPException(
                status_code=507,
                detail=(
                    "Server disk is full. Free space under NEUROCNL_DATA_DIR "
                    "or choose a smaller file."
                ),
            ) from exc
        raise HTTPException(
            status_code=503,
            detail=f"Could not save uploaded file on the server: {exc}",
        ) from exc

    return DatasetRawUploadResponse(path=str(dest_path.resolve()))


@router.get("/datasets/exists", response_model=DatasetPathExistsResponse)
async def check_dataset_path_exists(path: str) -> DatasetPathExistsResponse:
    """Read-only check for whether a `dataset_path` (as stored on a Data
    Loader pipeline node) still exists on this backend instance — no copy,
    no cache registration, unlike /datasets/import-local. Lets the frontend
    show a "file missing" indicator on a restored workspace before the user
    hits the errors _collect_uploaded_dataset_artifacts/training_service
    raise at generate/train time.

    Scoped to paths under DATA_DIR (same containment intent as
    _collect_uploaded_dataset_artifacts's `startswith(uploaded_root)` check)
    so this can't be used to probe arbitrary server filesystem paths.
    """
    try:
        resolved = Path(path).resolve()
    except (OSError, ValueError):
        return DatasetPathExistsResponse(exists=False)
    if not resolved.is_relative_to(DATA_DIR.resolve()):
        return DatasetPathExistsResponse(exists=False)
    return DatasetPathExistsResponse(exists=resolved.is_file())


@router.get("/datasets/{dataset_id}", response_model=DatasetEntryResponse)
async def get_dataset(dataset_id: str) -> DatasetEntryResponse:
    try:
        item = await dataset_cache.get_entry_dict(dataset_id)
        if item is None:
            raise HTTPException(
                status_code=404,
                detail=(
                    f"Dataset '{dataset_id}' is not in the catalog. "
                    "Use GET /api/datasets for available ids."
                ),
            )
        return DatasetEntryResponse(**item)
    except HTTPException:
        raise
    except Exception as exc:
        raise _map_dataset_exception(exc) from exc


@router.post(
    "/datasets/{dataset_id}/download",
    response_model=DatasetDownloadResponse,
    responses={202: {"description": "Download started or already in progress"}},
)
@limiter.limit("20/minute")
async def download_dataset(
    request: Request, dataset_id: str
) -> JSONResponse | DatasetDownloadResponse:
    try:
        catalog = load_dataset_catalog(refresh=True)
        entry = catalog.get(dataset_id)
        if entry is None:
            raise HTTPException(
                status_code=404,
                detail=(
                    f"Dataset '{dataset_id}' is not in the catalog. "
                    "Use GET /api/datasets for available ids."
                ),
            )

        if not firebase_bucket_configured():
            raise HTTPException(
                status_code=503,
                detail=(
                    "Firebase Storage is not configured on this server. "
                    "Set NEUROCNL_FIREBASE_BUCKET to your public bucket name and restart the backend."
                ),
            )

        # Already downloaded and file exists on disk → return immediately.
        if await dataset_cache.get_ready_path(dataset_id):
            result = await dataset_cache.ensure_downloaded(dataset_id)
            return DatasetDownloadResponse(
                dataset_id=result["dataset_id"],
                local_path=result["local_path"],
                downloaded_at=result["downloaded_at"],
                sha256_verified=result["sha256_verified"],
                size_bytes=result.get("size_bytes"),
            )

        # Already downloading (in this process or a persisted job that
        # survived a restart) → tell the client to keep polling using the
        # existing job_id instead of spawning a duplicate download.
        active_job_id = await dataset_cache.get_active_job_id(dataset_id)
        if active_job_id or dataset_cache._is_downloading(dataset_id):
            return JSONResponse(
                status_code=202,
                content={
                    "status": "downloading",
                    "dataset_id": dataset_id,
                    "job_id": active_job_id,
                },
            )

        # Start a new background download thread.
        dataset_cache.start_download(dataset_id)
        return JSONResponse(
            status_code=202,
            content={"status": "downloading", "dataset_id": dataset_id},
        )
    except HTTPException:
        raise
    except Exception as exc:
        raise _map_dataset_exception(exc) from exc
