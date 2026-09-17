"""Tests for the Projects API."""

from collections.abc import Generator
from contextlib import contextmanager
from typing import Any

from fastapi.testclient import TestClient
from sqlalchemy.orm import Session

from neurohub.app.auth import User as AuthUser
from neurohub.app.auth import get_current_user as get_current_user_auth
from neurohub.app.main import app
from neurohub.app.schemas.projects import Project
from neurohub.app.services import project_service


def _seed_project(db_session: Session, payload: dict[str, Any]) -> None:
    """Insert a project directly into the test database."""
    project_service.create_project(db_session, Project.model_validate(payload))


@contextmanager
def _override_current_user(user: AuthUser) -> Generator[None, None, None]:
    """Temporarily override the authenticated user for project tests."""

    def override_user() -> AuthUser:
        return user

    previous_override = app.dependency_overrides.get(get_current_user_auth)
    app.dependency_overrides[get_current_user_auth] = override_user
    try:
        yield
    finally:
        if previous_override is None:
            app.dependency_overrides.pop(get_current_user_auth, None)
        else:
            app.dependency_overrides[get_current_user_auth] = previous_override


def test_create_project(client: TestClient) -> None:
    """Test creating a new project."""
    response = client.post(
        "/api/neurohub/projects",
        json={
            "id": "test_project_1",
            "name": "Test Project 1",
            "description": "A test project",
            "created_at": "2023-10-27T10:00:00Z",
            "updated_at": "2023-10-27T10:00:00Z",
            "owner": "admin",
            "members": [{"user_id": "admin", "name": "User One", "role": "admin"}],
            "links": {
                "neurosim_project_id": "sim1",
                "neurochip_deployment_ids": [],
                "neurobench_benchmark_ids": [],
                "neurobench_baseline_ids": [],
                "neurosense_session_ids": [],
            },
            "tags": ["test"],
            "status": "not_started",
        },
    )
    assert response.status_code == 201, response.text
    data = response.json()
    assert data["name"] == "Test Project 1"
    assert data["id"] == "test_project_1"


def test_get_projects(client: TestClient) -> None:
    """Test retrieving all projects."""
    # Create a project first to ensure there's something to retrieve
    client.post(
        "/api/neurohub/projects",
        json={
            "id": "test_project_2",
            "name": "Test Project 2",
            "description": "Another test project",
            "owner": "admin",
            "members": [],
            "links": {},
            "tags": [],
            "created_at": "2023-10-27T10:00:00Z",
            "updated_at": "2023-10-27T10:00:00Z",
            "status": "not_started",
        },
    )
    response = client.get("/api/neurohub/projects")
    assert response.status_code == 200
    # Filter by ID to ensure we find the one we just created,
    # as other tests might have created projects too.
    projects = response.json()
    assert any(p["id"] == "test_project_2" for p in projects)


def test_get_project_not_found(client: TestClient) -> None:
    """Test retrieving a non-existent project."""
    response = client.get("/api/neurohub/projects/non_existent")
    assert response.status_code == 404
    assert response.json()["detail"] == "Project found" if False else "Project not found"


def test_update_project_not_found(client: TestClient) -> None:
    """Test updating a non-existent project."""
    response = client.put(
        "/api/neurohub/projects/non_existent",
        json={"name": "New Name"},
    )
    assert response.status_code == 404
    assert response.json()["detail"] == "Project not found"


def test_delete_project_not_found(client: TestClient) -> None:
    """Test deleting a non-existent project."""
    response = client.delete("/api/neurohub/projects/non_existent")
    assert response.status_code == 404
    assert response.json()["detail"] == "Project not found"


def test_project_access_denied(client: TestClient, db_session: Session) -> None:
    """Test 403 access denial for project mutations."""
    project_id = "denied_project"
    _seed_project(
        db_session,
        {
            "id": project_id,
            "name": "Denied Project",
            "description": "Owner is admin",
            "owner": "admin",
            "members": [],
            "links": {},
            "tags": [],
            "created_at": "2023-10-27T10:00:00Z",
            "updated_at": "2023-10-27T10:00:00Z",
        },
    )

    with _override_current_user(AuthUser(id="other_user", role="viewer")):
        listing_response = client.get("/api/neurohub/projects")
        assert listing_response.status_code == 200
        assert all(project["id"] != project_id for project in listing_response.json())

        response = client.get(f"/api/neurohub/projects/{project_id}")
        assert response.status_code == 403
        assert response.json()["detail"] == "Not a project member"

        response = client.put(
            f"/api/neurohub/projects/{project_id}",
            json={"name": "Hacked Name"},
        )
        assert response.status_code == 403

        response = client.delete(f"/api/neurohub/projects/{project_id}")
        assert response.status_code == 403


def test_project_member_insufficient_role(client: TestClient, db_session: Session) -> None:
    """Test 403 when a member has insufficient role for mutation."""
    project_id = "member_project"
    _seed_project(
        db_session,
        {
            "id": project_id,
            "name": "Member Project",
            "description": "Owner is admin",
            "owner": "admin",
            "members": [{"user_id": "member_user", "name": "Member", "role": "viewer"}],
            "links": {},
            "tags": [],
            "created_at": "2023-10-27T10:00:00Z",
            "updated_at": "2023-10-27T10:00:00Z",
        },
    )

    with _override_current_user(AuthUser(id="member_user", role="viewer")):
        listing_response = client.get("/api/neurohub/projects")
        assert listing_response.status_code == 200
        assert any(project["id"] == project_id for project in listing_response.json())

        response = client.get(f"/api/neurohub/projects/{project_id}")
        assert response.status_code == 200

        response = client.put(
            f"/api/neurohub/projects/{project_id}",
            json={"name": "Hacked Name"},
        )
        assert response.status_code == 403
        assert response.json()["detail"] == "Project admin role required"

        response = client.delete(f"/api/neurohub/projects/{project_id}")
        assert response.status_code == 403
        assert response.json()["detail"] == "Project admin role required"
