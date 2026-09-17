"""Concurrency tests for NeuroHub dashboard."""

import asyncio

import httpx
import pytest
from fastapi.testclient import TestClient

from neurohub.app.main import app


@pytest.mark.asyncio
async def test_concurrent_dashboard_sessions(client: TestClient) -> None:
    """Test concurrent dashboard sessions (3+ users)."""
    # Use httpx.AsyncClient with the app directly via ASGITransport
    # but ensure it honors the configuration set up by the client fixture.
    async with httpx.AsyncClient(
        transport=httpx.ASGITransport(app=app), base_url="http://test"
    ) as async_client:
        # Define the task to be performed by each "user"
        async def user_session(user_id: int):
            # 1. Get dashboard
            response = await async_client.get("/api/neurohub/projects")
            assert response.status_code == 200

            # 2. Get projects
            response = await async_client.get("/api/neurohub/projects")
            assert response.status_code == 200

            # 3. Get health
            response = await async_client.get("/api/neurohub/health")
            assert response.status_code == 200

            return f"User {user_id} finished"

        # Simulate 5 concurrent users
        num_users = 5
        tasks = [user_session(i) for i in range(num_users)]

        results = await asyncio.gather(*tasks)

        assert len(results) == num_users
        for i in range(num_users):
            # Match user_id in result string
            assert f"User {i} finished" in results


@pytest.mark.asyncio
async def test_concurrent_project_creation(client: TestClient) -> None:
    """Test concurrent project creation to check for race conditions or DB locks."""
    async with httpx.AsyncClient(
        transport=httpx.ASGITransport(app=app), base_url="http://test"
    ) as async_client:

        async def create_project(user_id: int):
            proj_id = f"concurrent_proj_{user_id}"
            response = await async_client.post(
                "/api/neurohub/projects",
                json={
                    "id": proj_id,
                    "name": f"Project {user_id}",
                    "description": "Concurrent creation test",
                    "created_at": "2026-03-20T10:00:00Z",
                    "updated_at": "2026-03-20T10:00:00Z",
                    "owner": "test-user",
                    "members": [],
                    "links": {},
                    "tags": [],
                    "status": "not_started",
                },
            )
            if response.status_code != 201:
                print(f"Error for {proj_id}: {response.text}")
            return response.status_code

        num_users = 10
        status_codes = []
        for i in range(num_users):
            status_codes.append(await create_project(i))

        # All should succeed (201 Created)
        for i, code in enumerate(status_codes):
            if code != 201:
                print(f"Task {i} failed with status code {code}")
        assert all(code == 201 for code in status_codes)

        # Verify they were all created
        # Increase limit to ensure we see all projects in case of concurrent noise
        response = await async_client.get("/api/neurohub/projects?limit=100")
        projects = response.json()
        project_ids = [p["id"] for p in projects]
        for i in range(num_users):
            assert f"concurrent_proj_{i}" in project_ids
