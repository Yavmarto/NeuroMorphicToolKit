"""Pydantic models for dataset catalog and download API."""

from pydantic import BaseModel


class DatasetEntryResponse(BaseModel):
    id: str
    label: str
    description: str
    storage_path: str
    folder_path: str | None = None
    source_filename: str | None = None
    size_bytes: int | None = None
    content_sha256: str | None = None
    status: str
    local_path: str | None = None
    downloaded_at: str | None = None
    error_message: str | None = None
    download_progress: float | None = None
    source: str | None = None
    format: str | None = None


class DatasetImportLocalRequest(BaseModel):
    server_path: str | None = None


class DatasetImportLocalResponse(DatasetEntryResponse):
    """Response for POST /api/datasets/import-local."""


class DatasetRawUploadResponse(BaseModel):
    """Response for POST /api/datasets/upload-raw."""

    path: str


class DatasetPathExistsResponse(BaseModel):
    """Response for GET /api/datasets/exists."""

    exists: bool


class DatasetFolderResponse(BaseModel):
    folder_name: str
    folder_path: str
    description: str
    files: list[DatasetEntryResponse]


class DatasetListResponse(BaseModel):
    firebase_available: bool
    datasets: list[DatasetEntryResponse]
    folders: list[DatasetFolderResponse] = []


class DatasetDownloadResponse(BaseModel):
    dataset_id: str
    local_path: str
    downloaded_at: str
    sha256_verified: bool
    size_bytes: int | None = None
