"""Tests for the asset library service."""

import hashlib

import pytest
from sqlalchemy.orm import Session

from neurohub.app.schemas.assets import SharedAsset
from neurohub.app.services import asset_library


@pytest.fixture
def test_file(tmp_path) -> str:
    """Fixture to create a temporary file for asset testing."""
    file_path = tmp_path / "test_asset.bin"
    content = b"test content for asset integrity"
    file_path.write_bytes(content)
    return str(file_path)


@pytest.fixture
def test_file_hash(test_file) -> str:
    """Fixture to get the hash of the test file."""
    sha256_hash = hashlib.sha256()
    with open(test_file, "rb") as f:
        for byte_block in iter(lambda: f.read(4096), b""):
            sha256_hash.update(byte_block)
    return sha256_hash.hexdigest()


@pytest.fixture
def sample_asset(test_file, test_file_hash) -> SharedAsset:
    """Fixture to provide a sample asset for testing."""
    return SharedAsset(
        id="asset_test",
        name="Test Asset",
        description="A test asset",
        type="neurosim_template",
        version=1,
        author="alice",
        tags=["test"],
        created_at="2026-03-19T10:00:00Z",
        file_path=test_file,
        file_size_bytes=100,
        sha256=test_file_hash,
        metadata={"key": "value"},
    )


def test_create_get_asset(db_session: Session, sample_asset: SharedAsset) -> None:
    """Test creating and retrieving an asset."""
    created = asset_library.create_asset(db_session, sample_asset)
    assert created.id == "asset_test"
    assert created.sha256 == sample_asset.sha256

    retrieved = asset_library.get_asset(db_session, "asset_test")
    assert retrieved is not None
    assert retrieved.name == "Test Asset"

    all_assets = asset_library.get_assets(db_session, asset_type="neurosim_template")
    assert len(all_assets) >= 1

    filtered = asset_library.get_assets(db_session, tags=["test"])
    assert len(filtered) >= 1


def test_update_asset(db_session: Session, sample_asset: SharedAsset) -> None:
    """Test updating an existing asset."""
    asset_library.create_asset(db_session, sample_asset)

    sample_asset.name = "Updated Name"
    updated = asset_library.update_asset(db_session, "asset_test", sample_asset)
    assert updated is not None
    assert updated.name == "Updated Name"
    assert updated.version == 2


def test_delete_asset(db_session: Session, sample_asset: SharedAsset, test_file: str) -> None:
    """Test deleting an asset removes the DB record and the physical file."""
    from pathlib import Path

    asset_library.create_asset(db_session, sample_asset)
    assert Path(test_file).exists(), "file should exist before deletion"
    assert asset_library.delete_asset(db_session, "asset_test") is True
    assert asset_library.get_asset(db_session, "asset_test") is None
    assert not Path(test_file).exists(), "physical file should be removed after deletion"
    assert asset_library.delete_asset(db_session, "nonexistent") is False


def test_delete_asset_missing_file_is_graceful(
    db_session: Session, sample_asset: SharedAsset, test_file: str
) -> None:
    """Deleting an asset whose file is already gone should still return True."""
    from pathlib import Path

    asset_library.create_asset(db_session, sample_asset)
    Path(test_file).unlink()  # Remove the file manually before calling delete
    assert asset_library.delete_asset(db_session, "asset_test") is True
    assert asset_library.get_asset(db_session, "asset_test") is None


def test_create_asset_integrity_fail(db_session: Session, sample_asset: SharedAsset) -> None:
    """Test that creating an asset with a mismatched hash fails."""
    sample_asset.sha256 = "a" * 64
    with pytest.raises(ValueError, match="Integrity check failed"):
        asset_library.create_asset(db_session, sample_asset)


def test_create_asset_file_not_found(db_session: Session, sample_asset: SharedAsset) -> None:
    """Test that creating an asset with a non-existent file fails."""
    sample_asset.file_path = "/nonexistent/file"
    with pytest.raises(FileNotFoundError):
        asset_library.create_asset(db_session, sample_asset)


def test_create_nir_validation_fail(
    db_session: Session, sample_asset: SharedAsset, tmp_path
) -> None:
    """Test that labeling an invalid file as 'nir' fails."""
    invalid_nir = tmp_path / "invalid.nir"
    invalid_nir.write_bytes(b"not an hdf5 file")

    sha256_hash = hashlib.sha256(b"not an hdf5 file").hexdigest()

    sample_asset.type = "nir"
    sample_asset.file_path = str(invalid_nir)
    sample_asset.sha256 = sha256_hash

    with pytest.raises(ValueError, match="not a valid NIR model"):
        asset_library.create_asset(db_session, sample_asset)


def test_create_nir_validation_success(
    db_session: Session, sample_asset: SharedAsset, tmp_path
) -> None:
    """Test that a valid NIR file (HDF5 magic bytes) passes validation."""
    valid_nir = tmp_path / "valid.nir"
    hdf5_magic = b"\x89HDF\r\n\x1a\n"
    valid_nir.write_bytes(hdf5_magic + b"payload")

    sha256_hash = hashlib.sha256(hdf5_magic + b"payload").hexdigest()

    sample_asset.type = "nir"
    sample_asset.file_path = str(valid_nir)
    sample_asset.sha256 = sha256_hash

    created = asset_library.create_asset(db_session, sample_asset)
    assert created.type == "nir"


# ---------------------------------------------------------------------------
# validate_upload tests
# ---------------------------------------------------------------------------


def test_validate_upload_size_limit(monkeypatch: pytest.MonkeyPatch) -> None:
    """Uploading a file larger than the configured limit raises ValueError."""
    monkeypatch.setenv("NEUROHUB_MAX_UPLOAD_BYTES", "100")
    with pytest.raises(ValueError, match="exceeds limit"):
        asset_library.validate_upload("cnl_spec", "spec.json", "application/json", 200)


def test_validate_upload_mime_rejection() -> None:
    """A video extension + MIME type for cnl_spec raises ValueError."""
    with pytest.raises(ValueError, match="File type not allowed"):
        asset_library.validate_upload("cnl_spec", "video.mp4", "video/mp4", 50)


def test_validate_upload_extension_ok_mime_generic() -> None:
    """Correct extension with generic MIME (octet-stream) should NOT raise."""
    # Many browsers send application/octet-stream regardless of file type.
    asset_library.validate_upload("cnl_spec", "spec.json", "application/octet-stream", 100)


def test_validate_upload_mime_ok() -> None:
    """Correct extension and MIME type should not raise."""
    asset_library.validate_upload("cnl_spec", "spec.json", "application/json", 100)


def test_validate_upload_workspace_type_ok() -> None:
    """Workspace uploads should accept JSON workspace files."""
    asset_library.validate_upload(
        "studio_workspace",
        "session.nmtk",
        "application/json",
        100,
    )


def test_validate_upload_skipped_in_test_env(monkeypatch: pytest.MonkeyPatch) -> None:
    """When NEUROHUB_SKIP_ASSET_VALIDATION=true, MIME check is bypassed."""
    monkeypatch.setenv("NEUROHUB_SKIP_ASSET_VALIDATION", "true")
    # Would normally fail (wrong extension + MIME), but is bypassed.
    asset_library.validate_upload("nir", "video.mp4", "video/mp4", 50)


# ---------------------------------------------------------------------------
# get_asset_file_path tests
# ---------------------------------------------------------------------------


def test_get_asset_file_path_not_found(db_session: Session) -> None:
    """Returns None when no asset with the given ID exists."""
    result = asset_library.get_asset_file_path(db_session, "does_not_exist")
    assert result is None


def test_get_asset_file_path_missing_file(
    db_session: Session, sample_asset: SharedAsset, test_file: str
) -> None:
    """Raises FileNotFoundError when the DB record exists but the file is gone."""
    from pathlib import Path

    asset_library.create_asset(db_session, sample_asset)
    Path(test_file).unlink()
    with pytest.raises(FileNotFoundError):
        asset_library.get_asset_file_path(db_session, "asset_test")


def test_get_asset_file_path_success(
    db_session: Session, sample_asset: SharedAsset, test_file: str
) -> None:
    """Returns the resolved path when the file exists."""
    from pathlib import Path

    asset_library.create_asset(db_session, sample_asset)
    path = asset_library.get_asset_file_path(db_session, "asset_test")
    assert path is not None
    assert path == Path(test_file).resolve()


# ---------------------------------------------------------------------------
# get_assets with ?q= search
# ---------------------------------------------------------------------------


def test_get_assets_search_q(db_session: Session, sample_asset: SharedAsset) -> None:
    """The q parameter filters assets by name/description substring."""
    asset_library.create_asset(db_session, sample_asset)

    # Match on name
    results = asset_library.get_assets(db_session, q="Test Asset")
    assert any(a.id == "asset_test" for a in results)

    # Match on description
    results = asset_library.get_assets(db_session, q="a test asset")
    assert any(a.id == "asset_test" for a in results)

    # Case-insensitive
    results = asset_library.get_assets(db_session, q="TEST")
    assert any(a.id == "asset_test" for a in results)

    # Non-matching query returns nothing for this asset
    results = asset_library.get_assets(db_session, q="XYZNOSUCHNAME99999")
    assert not any(a.id == "asset_test" for a in results)
