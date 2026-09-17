"""Smoke test for NeuroHub registry.

Runs against a live NeuroHub instance: project creation, member update, asset list.
"""

import os
import uuid

import httpx
import pytest

NEUROHUB_URL = os.environ.get("NEUROHUB_URL", "http://localhost:8000")
API_KEY = os.environ.get("NEUROHUB_API_KEY", "test-api-key")
RUN_SMOKE_TEST = os.environ.get("NEUROHUB_RUN_SMOKE_TEST", "").lower() == "true"


@pytest.fixture
def client():
    """Httpx client for smoke testing."""
    return httpx.Client(base_url=NEUROHUB_URL, headers={"X-API-Key": API_KEY}, timeout=10.0)


@pytest.mark.skipif(
    not RUN_SMOKE_TEST,
    reason="Set NEUROHUB_RUN_SMOKE_TEST=true to run live registry smoke tests.",
)
def test_registry_smoke_path(client):
    """Run the end-to-end smoke path against a real backend instance."""
    print(f"\nStarting smoke test against {NEUROHUB_URL}...")

    project_id = f"smoke-proj-{uuid.uuid4().hex[:8]}"
    now = "2026-03-20T10:00:00Z"

    create_res = client.post(
        "/api/neurohub/projects",
        json={
            "id": project_id,
            "name": "Smoke Test Project",
            "description": "Created by smoke test",
            "created_at": now,
            "updated_at": now,
            "owner": "admin",
            "members": [{"user_id": "admin", "name": "Admin", "role": "admin"}],
            "links": {},
            "tags": ["smoke"],
        },
    )
    assert create_res.status_code == 201, f"Failed to create project: {create_res.text}"

    member_data = [
        {"user_id": "admin", "name": "Admin", "role": "admin"},
        {"user_id": "smoke-user", "name": "Smoke User", "role": "viewer"},
    ]
    member_res = client.put(
        f"/api/neurohub/projects/{project_id}",
        json={"members": member_data},
    )
    assert member_res.status_code == 200, f"Failed to add member: {member_res.text}"

    assets_res = client.get("/api/neurohub/assets")
    assert assets_res.status_code == 200, f"Failed to list assets: {assets_res.text}"

    export_res = client.post(f"/api/neurohub/projects/{project_id}/export")
    assert export_res.status_code == 200, f"Failed to export project: {export_res.text}"
    assert export_res.json()["project"]["id"] == project_id

    print(f"Smoke test passed successfully for project {project_id}!")


if __name__ == "__main__":
    import sys

    pytest.main([__file__] + sys.argv[1:])
