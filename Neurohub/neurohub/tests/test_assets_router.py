"""Tests for the asset library router."""

import hashlib
import pytest
from fastapi.testclient import TestClient

import os


@pytest.fixture(autouse=True)
def enable_asset_validation():
    """Ensure asset validation is NOT skipped for router tests."""
    if "NEUROHUB_SKIP_ASSET_VALIDATION" in os.environ:
        old_val = os.environ["NEUROHUB_SKIP_ASSET_VALIDATION"]
        del os.environ["NEUROHUB_SKIP_ASSET_VALIDATION"]
        yield
        os.environ["NEUROHUB_SKIP_ASSET_VALIDATION"] = old_val
    else:
        yield


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


def test_add_asset_success(client: TestClient, test_file: str, test_file_hash: str) -> None:
    """Test successful asset creation via router."""
    asset_data = {
        "id": "asset_router_test",
        "name": "Router Test Asset",
        "description": "Tested via router",
        "type": "neurosim_template",
        "version": 1,
        "author": "bob",
        "tags": ["router"],
        "created_at": "2026-03-20T10:00:00Z",
        "file_path": test_file,
        "file_size_bytes": 100,
        "sha256": test_file_hash,
        "metadata": {"router": "test"},
    }
    response = client.post("/api/neurohub/assets", json=asset_data)
    assert response.status_code == 201
    data = response.json()
    assert data["name"] == "Router Test Asset"
    assert data["sha256"] == test_file_hash


def test_add_asset_integrity_fail(client: TestClient, test_file: str) -> None:
    """Test asset creation failure due to hash mismatch."""
    asset_data = {
        "id": "asset_router_fail",
        "name": "Failing Asset",
        "description": "Should fail",
        "type": "neurosim_template",
        "version": 1,
        "author": "bob",
        "tags": ["fail"],
        "created_at": "2026-03-20T10:00:00Z",
        "file_path": test_file,
        "file_size_bytes": 100,
        "sha256": "0" * 64,
        "metadata": {},
    }
    response = client.post("/api/neurohub/assets", json=asset_data)
    assert response.status_code == 400
    assert "Integrity check failed" in response.json()["detail"]


def test_add_asset_nir_fail(client: TestClient, tmp_path) -> None:
    """Test NIR asset creation failure due to invalid structure."""
    invalid_nir = tmp_path / "bad.nir"
    invalid_nir.write_bytes(b"not a nir file")
    sha256 = hashlib.sha256(b"not a nir file").hexdigest()

    asset_data = {
        "id": "asset_nir_fail",
        "name": "Bad NIR",
        "description": "Invalid NIR",
        "type": "nir",
        "version": 1,
        "author": "bob",
        "tags": ["nir"],
        "created_at": "2026-03-20T10:00:00Z",
        "file_path": str(invalid_nir),
        "file_size_bytes": 100,
        "sha256": sha256,
        "metadata": {},
    }
    response = client.post("/api/neurohub/assets", json=asset_data)
    assert response.status_code == 400
    assert "not a valid NIR model" in response.json()["detail"]


def test_get_asset_not_found(client: TestClient) -> None:
    """Test 404 for non-existent asset."""
    response = client.get("/api/neurohub/assets/nonexistent")
    assert response.status_code == 404
    assert response.json()["detail"] == "Asset not found"


def test_update_asset_not_found(client: TestClient, test_file: str, test_file_hash: str) -> None:
    """Test 404 for updating non-existent asset."""
    asset_data = {
        "id": "nonexistent",
        "name": "Updated Name",
        "description": "Tested via router",
        "type": "neurosim_template",
        "version": 1,
        "author": "bob",
        "tags": ["router"],
        "created_at": "2026-03-20T10:00:00Z",
        "file_path": test_file,
        "file_size_bytes": 100,
        "sha256": test_file_hash,
        "metadata": {},
    }
    response = client.put("/api/neurohub/assets/nonexistent", json=asset_data)
    assert response.status_code == 404


def test_delete_asset_not_found(client: TestClient) -> None:
    """Test 404 for deleting non-existent asset."""
    response = client.delete("/api/neurohub/assets/nonexistent")
    assert response.status_code == 404


def test_delete_asset_removes_physical_file(
    client: TestClient, tmp_path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """DELETE /assets/{id} should remove the physical file from disk."""
    from pathlib import Path

    # Place asset in a tmp directory and set it as the storage root.
    storage_dir = tmp_path / "assets"
    storage_dir.mkdir()
    monkeypatch.setenv("NEUROHUB_ASSET_STORAGE_PATH", str(storage_dir))

    content = b"delete me"
    asset_file = storage_dir / "todel.bin"
    asset_file.write_bytes(content)
    sha256 = hashlib.sha256(content).hexdigest()

    asset_data = {
        "id": "asset_delete_test",
        "name": "To Delete",
        "description": "Will be deleted",
        "type": "neurosim_template",
        "version": 1,
        "author": "unknown",  # matches the admin user's username default
        "tags": [],
        "created_at": "2026-05-18T00:00:00Z",
        "file_path": str(asset_file),
        "file_size_bytes": len(content),
        "sha256": sha256,
        "metadata": {},
    }
    create_resp = client.post("/api/neurohub/assets", json=asset_data)
    assert create_resp.status_code == 201

    del_resp = client.delete("/api/neurohub/assets/asset_delete_test")
    assert del_resp.status_code == 204
    assert not Path(asset_file).exists(), "physical file should be removed by DELETE"


def test_download_asset_not_found(client: TestClient) -> None:
    """GET /assets/{id}/download returns 404 for an unknown asset."""
    response = client.get("/api/neurohub/assets/nonexistent/download")
    assert response.status_code == 404


def test_download_asset_file_missing(
    client: TestClient, tmp_path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """GET /assets/{id}/download returns 410 when the file has been removed from disk."""
    from pathlib import Path

    storage_dir = tmp_path / "assets"
    storage_dir.mkdir()
    monkeypatch.setenv("NEUROHUB_ASSET_STORAGE_PATH", str(storage_dir))

    content = b"temporary content"
    asset_file = storage_dir / "gone.bin"
    asset_file.write_bytes(content)
    sha256 = hashlib.sha256(content).hexdigest()

    asset_data = {
        "id": "asset_gone",
        "name": "Gone Asset",
        "description": "File will be manually removed",
        "type": "neurosim_template",
        "version": 1,
        "author": "unknown",
        "tags": [],
        "created_at": "2026-05-18T00:00:00Z",
        "file_path": str(asset_file),
        "file_size_bytes": len(content),
        "sha256": sha256,
        "metadata": {},
    }
    create_resp = client.post("/api/neurohub/assets", json=asset_data)
    assert create_resp.status_code == 201

    # Simulate out-of-band deletion of the physical file.
    Path(asset_file).unlink()

    dl_resp = client.get("/api/neurohub/assets/asset_gone/download")
    assert dl_resp.status_code == 410


def test_download_asset_success(
    client: TestClient, tmp_path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """GET /assets/{id}/download streams the correct file bytes."""
    storage_dir = tmp_path / "assets"
    storage_dir.mkdir()
    monkeypatch.setenv("NEUROHUB_ASSET_STORAGE_PATH", str(storage_dir))

    content = b'{"neuron_count": 32}'
    asset_file = storage_dir / "model.json"
    asset_file.write_bytes(content)
    sha256 = hashlib.sha256(content).hexdigest()

    asset_data = {
        "id": "asset_dl_success",
        "name": "Download Me",
        "description": "For download testing",
        "type": "neurosim_template",
        "version": 1,
        "author": "unknown",
        "tags": [],
        "created_at": "2026-05-18T00:00:00Z",
        "file_path": str(asset_file),
        "file_size_bytes": len(content),
        "sha256": sha256,
        "metadata": {},
    }
    create_resp = client.post("/api/neurohub/assets", json=asset_data)
    assert create_resp.status_code == 201

    dl_resp = client.get("/api/neurohub/assets/asset_dl_success/download")
    assert dl_resp.status_code == 200
    assert dl_resp.content == content
    assert "attachment" in dl_resp.headers.get("content-disposition", "")


def test_list_assets_search_q(
    client: TestClient, tmp_path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """GET /assets?q= filters by name/description substring."""
    storage_dir = tmp_path / "assets"
    storage_dir.mkdir()
    monkeypatch.setenv("NEUROHUB_ASSET_STORAGE_PATH", str(storage_dir))

    content = b"data"
    asset_file = storage_dir / "unique.bin"
    asset_file.write_bytes(content)
    sha256 = hashlib.sha256(content).hexdigest()

    unique_name = "ZZZ_RouterSearchTest_Unique"
    asset_data = {
        "id": "asset_search_q",
        "name": unique_name,
        "description": "Unique search description",
        "type": "neurosim_template",
        "version": 1,
        "author": "unknown",
        "tags": [],
        "created_at": "2026-05-18T00:00:00Z",
        "file_path": str(asset_file),
        "file_size_bytes": len(content),
        "sha256": sha256,
        "metadata": {},
    }
    client.post("/api/neurohub/assets", json=asset_data)

    # Match returns the asset
    resp = client.get("/api/neurohub/assets?q=ZZZ_RouterSearchTest")
    assert resp.status_code == 200
    assert any(a["name"] == unique_name for a in resp.json())

    # Non-match returns empty
    resp2 = client.get("/api/neurohub/assets?q=XYZNOSUCHTERM99999")
    assert resp2.status_code == 200
    assert not any(a["name"] == unique_name for a in resp2.json())
