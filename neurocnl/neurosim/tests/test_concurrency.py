from typing import Any

import anyio
import httpx
import pytest
from fastapi.testclient import TestClient

from neurosim.app.main import app

client = TestClient(app)


async def create_project_task(name: str) -> str:
    """Task to create a project and return its ID."""
    graph = {
        "nodes": [
            {
                "id": "n1",
                "component_id": "lif_population",
                "parameters": {"name": name, "n_neurons": 10},
                "position": [0, 0],
            },
        ],
        "edges": [],
        "metadata": {},
    }
    create_request = {
        "name": f"Project {name}",
        "description": f"Description for {name}",
        "graph": graph,
    }

    # We use anyio.to_thread to run the synchronous TestClient in an async way
    def post_request() -> httpx.Response:
        response: httpx.Response = client.post(
            "/api/neurosim/projects", json=create_request
        )
        return response

    response = await anyio.to_thread.run_sync(post_request)
    assert response.status_code == 200
    project_id: str = response.json()["id"]
    return project_id


@pytest.mark.anyio
async def test_concurrent_project_creation() -> None:
    """Test that multiple users can create projects concurrently without issues."""
    num_projects = 5
    project_names = [f"User_{i}" for i in range(num_projects)]

    async with anyio.create_task_group() as tg:
        results = []
        for name in project_names:
            # anyio doesn't return results from tg.start_soon directly easily in this way
            # so we'll collect them in a list by using a wrapper
            async def task_wrapper(n: Any) -> None:
                res = await create_project_task(n)
                results.append(res)

            tg.start_soon(task_wrapper, name)

    assert len(results) == num_projects
    assert len(set(results)) == num_projects  # All IDs should be unique

    # Verify all projects exist
    def get_projects() -> httpx.Response:
        response: httpx.Response = client.get("/api/neurosim/projects")
        return response

    response = await anyio.to_thread.run_sync(get_projects)
    assert response.status_code == 200
    all_projects = response.json()
    all_ids = [p["id"] for p in all_projects]
    for project_id in results:
        assert project_id in all_ids


@pytest.mark.anyio
async def test_concurrent_simulations() -> None:
    """Test concurrent simulation requests."""
    graph = {
        "nodes": [
            {
                "id": "n1",
                "component_id": "lif_population",
                "parameters": {"name": "A", "n_neurons": 10},
                "position": [0, 0],
            },
        ],
        "edges": [],
        "metadata": {},
    }

    async def run_preview() -> Any:
        def post_preview() -> httpx.Response:
            response: httpx.Response = client.post(
                "/api/neurosim/preview", json={"graph": graph, "duration_ms": 50}
            )
            return response

        response = await anyio.to_thread.run_sync(post_preview)
        assert response.status_code == 200
        return response.json()

    async with anyio.create_task_group() as tg:
        for _ in range(5):
            tg.start_soon(run_preview)
