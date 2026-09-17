"""Integration tests for all NeuroHub API endpoints."""

import hashlib

import httpx
import pytest
from fastapi.testclient import TestClient


def _make_asset_payload(
    tmp_path,
    *,
    asset_id: str = "asset_1",
    name: str = "Prosthetic Template",
    description: str = "Standard prosthetic controller template",
    content: bytes = b'{"neuron_count": 128}',
    metadata: dict[str, int] | None = None,
) -> dict[str, object]:
    """Create a valid asset payload backed by a real file."""
    asset_file = tmp_path / f"{asset_id}.json"
    asset_file.write_bytes(content)
    return {
        "id": asset_id,
        "name": name,
        "description": description,
        "type": "neurosim_template",
        "version": 1,
        "author": "testuser",
        "tags": ["prosthetic", "template"],
        "created_at": "2026-03-16T00:00:00Z",
        "file_path": str(asset_file),
        "file_size_bytes": len(content),
        "sha256": hashlib.sha256(content).hexdigest(),
        "metadata": metadata or {"neuron_count": 128},
    }


# --- Config ---


def test_get_config_defaults(client: TestClient) -> None:
    """Test retrieving default configuration."""
    response = client.get("/api/neurohub/config")
    assert response.status_code == 200
    data = response.json()
    assert data["neurosim_url"] == "http://localhost:8000"
    assert data["shared_storage_path"] == "./shared_assets"


def test_update_config(client: TestClient) -> None:
    """Test updating suite configuration."""
    response = client.put(
        "/api/neurohub/config",
        json={
            "neurosim_url": "http://neurosim:9001",
            "neurochip_url": "http://localhost:8002",
            "neurobench_url": "http://localhost:8003",
            "neurosense_url": "http://localhost:8004",
            "neurocnl_url": "http://localhost:8000",
            "shared_storage_path": "/data/shared",
            "default_project_settings": {"auto_milestone": True},
        },
    )
    assert response.status_code == 200
    data = response.json()
    assert data["neurosim_url"] == "http://neurosim:9001"
    assert data["shared_storage_path"] == "/data/shared"

    # Verify persistence
    response2 = client.get("/api/neurohub/config")
    assert response2.json()["neurosim_url"] == "http://neurosim:9001"


# --- Projects (create one for subsequent tests) ---


def test_create_project_for_tests(client: TestClient) -> None:
    """Create a project to be used by subsequent tests."""
    response = client.post(
        "/api/neurohub/projects",
        json={
            "id": "proj_1",
            "name": "Test Project",
            "description": "For testing",
            "created_at": "2026-03-16T00:00:00Z",
            "updated_at": "2026-03-16T00:00:00Z",
            "owner": "testuser",
            "members": [{"user_id": "testuser", "name": "Alice", "role": "admin"}],
            "links": {},
            "tags": ["test"],
        },
    )
    # 201 if created, 400 if already exists. Both are fine for this helper.
    assert response.status_code in (201, 400)


def test_update_project_members(client: TestClient) -> None:
    """Test updating project members via project PUT."""
    test_create_project_for_tests(client)
    members = [
        {"user_id": "alice", "name": "Alice", "role": "admin"},
        {"user_id": "bob", "name": "Bob", "role": "engineer"},
    ]
    response = client.put("/api/neurohub/projects/proj_1", json={"members": members})
    assert response.status_code == 200
    assert len(response.json()["members"]) == 2


# --- Assets ---


def test_create_asset(client: TestClient, tmp_path) -> None:
    """Test creating a shared asset."""
    response = client.post("/api/neurohub/assets", json=_make_asset_payload(tmp_path))
    assert response.status_code == 201
    data = response.json()
    assert data["name"] == "Prosthetic Template"
    assert data["metadata"]["neuron_count"] == 128


def test_list_assets(client: TestClient, tmp_path) -> None:
    """Test listing all shared assets."""
    # Ensure asset exists
    test_create_asset(client, tmp_path)
    response = client.get("/api/neurohub/assets")
    assert response.status_code == 200
    assert len(response.json()) >= 1


def test_get_asset(client: TestClient, tmp_path) -> None:
    """Test retrieving a single asset."""
    # Ensure asset exists
    test_create_asset(client, tmp_path)
    response = client.get("/api/neurohub/assets/asset_1")
    assert response.status_code == 200
    assert response.json()["name"] == "Prosthetic Template"


def test_update_asset_increments_version(client: TestClient, tmp_path) -> None:
    """Test that updating an asset increments its version."""
    # Ensure asset exists
    test_create_asset(client, tmp_path)
    updated_payload = _make_asset_payload(
        tmp_path,
        asset_id="asset_1",
        name="Prosthetic Template v2",
        description="Updated",
        content=b'{"neuron_count": 256}',
        metadata={"neuron_count": 256},
    )
    updated_payload["author"] = "alice"
    updated_payload["tags"] = ["prosthetic", "template", "v2"]
    response = client.put(
        "/api/neurohub/assets/asset_1",
        json=updated_payload,
    )
    assert response.status_code == 200
    data = response.json()
    assert data["version"] == 2  # auto-incremented
    assert data["name"] == "Prosthetic Template v2"


def test_filter_assets_by_type(client: TestClient, tmp_path) -> None:
    """Test filtering assets by type."""
    # Ensure asset exists
    test_create_asset(client, tmp_path)
    response = client.get("/api/neurohub/assets?type=neurosim_template")
    assert response.status_code == 200
    assert len(response.json()) >= 1


def test_delete_asset(client: TestClient, tmp_path) -> None:
    """Test deleting an asset."""
    # Ensure asset exists
    test_create_asset(client, tmp_path)
    response = client.delete("/api/neurohub/assets/asset_1")
    assert response.status_code == 204

    response2 = client.get("/api/neurohub/assets/asset_1")
    assert response2.status_code == 404


# --- Health ---


def test_health_check(client: TestClient) -> None:
    """Test the NeuroHub self-only health check endpoint."""
    response = client.get("/api/neurohub/health")
    assert response.status_code == 200
    data = response.json()
    assert "status" in data
    assert "database" in data
    assert data["status"] in ("ok", "degraded", "offline")


# --- Sharing ---


def test_create_share_via_multipart_upload(client: TestClient, tmp_path) -> None:
    """Test that a multipart file upload creates a shared asset."""
    content = b'{"neuron_count": 64, "topology": "snn"}'
    asset_file = tmp_path / "prototype.json"
    asset_file.write_bytes(content)

    with open(asset_file, "rb") as fh:
        response = client.post(
            "/api/neurohub/shares",
            data={
                "name": "Prototype SNN",
                "description": "A small spiking neural network template.",
                "type": "neurosim_template",
                "tags": '["prototype", "snn"]',
                "metadata": '{"downloads": 0}',
            },
            files={"file": ("prototype.json", fh, "application/json")},
        )

    assert response.status_code == 201, response.text
    data = response.json()
    assert data["name"] == "Prototype SNN"
    assert len(data["id"]) == 36  # UUID
    assert len(data["sha256"]) == 64
    assert data["file_size_bytes"] == len(content)
    assert data["version"] == 1


def test_created_share_appears_in_feed(client: TestClient, tmp_path) -> None:
    """Test that a newly created share appears in the public feed."""
    content = b'{"layers": [128, 64], "type": "encoder"}'
    asset_file = tmp_path / "encoder.json"
    asset_file.write_bytes(content)

    with open(asset_file, "rb") as fh:
        create_resp = client.post(
            "/api/neurohub/shares",
            data={
                "name": "Encoder Template",
                "description": "Encoder model template.",
                "type": "neurosim_template",
                "tags": "[]",
                "metadata": "{}",
            },
            files={"file": ("encoder.json", fh, "application/json")},
        )
    assert create_resp.status_code == 201, create_resp.text
    created_id = create_resp.json()["id"]

    feed_resp = client.get("/api/neurohub/feed")
    assert feed_resp.status_code == 200
    feed_ids = [a["id"] for a in feed_resp.json()]
    assert created_id in feed_ids


# --- 404 cases ---


def test_get_nonexistent_project(client: TestClient) -> None:
    """Test 404 response for nonexistent project."""
    response = client.get("/api/neurohub/projects/nonexistent")
    assert response.status_code == 404


def test_get_nonexistent_asset(client: TestClient) -> None:
    """Test 404 response for nonexistent asset."""
    response = client.get("/api/neurohub/assets/nonexistent")
    assert response.status_code == 404


def test_members_nonexistent_project(client: TestClient) -> None:
    """Test 404 response for members of nonexistent project."""
    response = client.get("/api/neurohub/projects/nonexistent/members")
    assert response.status_code == 404


# ---------------------------------------------------------------------------
# Sharing — download, delete, validation
# ---------------------------------------------------------------------------


def _upload_share(
    client: TestClient,
    tmp_path,
    *,
    name: str = "Test Share",
    content: bytes = b'{"layers": [64]}',
    filename: str = "model.json",
    content_type: str = "application/json",
    asset_type: str = "neurosim_template",
) -> httpx.Response:
    """Helper that uploads a share and returns the raw HTTP response."""
    asset_file = tmp_path / filename
    asset_file.write_bytes(content)
    with open(asset_file, "rb") as fh:
        resp: httpx.Response = client.post(
            "/api/neurohub/shares",
            data={
                "name": name,
                "description": "Integration test share",
                "type": asset_type,
                "tags": "[]",
                "metadata": "{}",
            },
            files={"file": (filename, fh, content_type)},
        )
    return resp


def test_download_share(client: TestClient, tmp_path, monkeypatch: pytest.MonkeyPatch) -> None:
    """GET /shares/{id}/download streams the correct file bytes."""
    storage_dir = tmp_path / "shared_assets"
    storage_dir.mkdir()
    monkeypatch.setenv("NEUROHUB_ASSET_STORAGE_PATH", str(storage_dir))

    content = b'{"layers": [64]}'
    resp = _upload_share(client, tmp_path, content=content)
    assert resp.status_code == 201, resp.text
    asset_id = resp.json()["id"]

    dl_resp = client.get(f"/api/neurohub/shares/{asset_id}/download")
    assert dl_resp.status_code == 200
    assert dl_resp.content == content
    assert "attachment" in dl_resp.headers.get("content-disposition", "")


def test_delete_share_by_author(
    client: TestClient, tmp_path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """DELETE /shares/{id} returns 204 for an admin (who acts as author or admin)."""
    storage_dir = tmp_path / "shared_assets"
    storage_dir.mkdir()
    monkeypatch.setenv("NEUROHUB_ASSET_STORAGE_PATH", str(storage_dir))

    resp = _upload_share(client, tmp_path, name="Share To Delete")
    assert resp.status_code == 201, resp.text
    asset_id = resp.json()["id"]

    del_resp = client.delete(f"/api/neurohub/shares/{asset_id}")
    assert del_resp.status_code == 204

    # Confirm it is gone from the feed
    feed_resp = client.get("/api/neurohub/feed")
    assert all(a["id"] != asset_id for a in feed_resp.json())


def test_delete_share_not_found(client: TestClient) -> None:
    """DELETE /shares/{nonexistent} returns 404."""
    resp = client.delete("/api/neurohub/shares/does_not_exist")
    assert resp.status_code == 404


def test_create_share_size_limit(
    client: TestClient, tmp_path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Uploading a file exceeding NEUROHUB_MAX_UPLOAD_BYTES returns 413."""
    monkeypatch.setenv("NEUROHUB_MAX_UPLOAD_BYTES", "10")
    content = b"x" * 100  # 100 bytes > 10 byte limit
    resp = _upload_share(client, tmp_path, content=content, filename="big.json")
    assert resp.status_code == 413, resp.text


def test_create_share_invalid_mime(
    client: TestClient, tmp_path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Uploading a .mp4 file as cnl_spec returns 415."""
    # Ensure validation is not skipped
    monkeypatch.delenv("NEUROHUB_SKIP_ASSET_VALIDATION", raising=False)
    content = b"fake video data"
    resp = _upload_share(
        client,
        tmp_path,
        content=content,
        filename="video.mp4",
        content_type="video/mp4",
        asset_type="cnl_spec",
    )
    assert resp.status_code == 415, resp.text
