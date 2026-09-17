"""Tests for project export/import round-trip."""

from fastapi.testclient import TestClient


def test_export_import_roundtrip(client: TestClient) -> None:
    """Test exporting a project and then importing it."""
    project_id = "rt_project_1"
    project_data = {
        "id": project_id,
        "name": "RT Project",
        "description": "Round-trip test project",
        "created_at": "2023-10-27T10:00:00Z",
        "updated_at": "2023-10-27T10:00:00Z",
        "owner": "user1",
        "members": [{"user_id": "user1", "name": "User One", "role": "admin"}],
        "links": {
            "neurosim_project_id": "sim1",
            "neurochip_deployment_ids": [],
            "neurobench_benchmark_ids": [],
            "neurobench_baseline_ids": [],
            "neurosense_session_ids": [],
        },
        "tags": ["rt-test"],
    }
    client.post("/api/neurohub/projects", json=project_data)

    response = client.post(f"/api/neurohub/projects/{project_id}/export")
    assert response.status_code == 200
    bundle = response.json()
    assert bundle["project"]["id"] == project_id
    assert bundle["version"] == 2

    new_project_id = "rt_project_imported"
    bundle["project"]["id"] = new_project_id

    response = client.post("/api/neurohub/projects/import", json=bundle)
    assert response.status_code == 200
    imported_project = response.json()
    assert imported_project["id"] == new_project_id
    assert imported_project["name"] == project_data["name"]

    get_res = client.get(f"/api/neurohub/projects/{new_project_id}")
    assert get_res.status_code == 200


def test_import_conflict(client: TestClient) -> None:
    """Test importing a project that already exists."""
    project_id = "conflict_project"
    project_data = {
        "id": project_id,
        "name": "Conflict Project",
        "description": "Conflict test project",
        "created_at": "2023-10-27T10:00:00Z",
        "updated_at": "2023-10-27T10:00:00Z",
        "owner": "user1",
        "members": [],
        "links": {},
        "tags": [],
    }
    client.post("/api/neurohub/projects", json=project_data)

    response = client.post(f"/api/neurohub/projects/{project_id}/export")
    bundle = response.json()

    response = client.post("/api/neurohub/projects/import", json=bundle)
    assert response.status_code == 409
    assert "already exists" in response.json()["detail"]


def test_import_unsupported_version(client: TestClient) -> None:
    """Test importing a bundle with an unsupported version."""
    bundle = {
        "version": 999,
        "project": {
            "id": "v999_project",
            "name": "V999 Project",
            "description": "v999 test project",
            "created_at": "2023-10-27T10:00:00Z",
            "updated_at": "2023-10-27T10:00:00Z",
            "owner": "user1",
            "members": [],
            "links": {},
            "tags": [],
        },
    }
    response = client.post("/api/neurohub/projects/import", json=bundle)
    assert response.status_code == 400
    assert "Unsupported bundle version" in response.json()["detail"]
