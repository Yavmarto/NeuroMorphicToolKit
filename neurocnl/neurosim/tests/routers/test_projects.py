import tempfile
from collections.abc import Iterator
from datetime import UTC, datetime
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from neurosim.app.main import app
from neurosim.app.routers.projects import get_project_store
from neurosim.app.schemas.projects import Project
from neurosim.app.services.project_store import ProjectStore
from neurosim.contracts.design_contracts import CanvasGraph

client = TestClient(app)

from typing import Any

VALID_GRAPH: dict[str, Any] = {"nodes": [], "edges": [], "metadata": {}}


@pytest.fixture
def temp_db() -> Iterator[str]:
    with tempfile.NamedTemporaryFile(suffix=".db", delete=False) as tmp:
        db_path = tmp.name
    yield db_path
    Path(db_path).unlink(missing_ok=True)


@pytest.fixture
def override_project_store(temp_db: str) -> Iterator[ProjectStore]:
    store = ProjectStore(temp_db)
    app.dependency_overrides[get_project_store] = lambda: store
    yield store
    app.dependency_overrides.clear()


@pytest.mark.usefixtures("override_project_store")
def test_projects_crud() -> None:
    # 1. List
    response = client.get("/api/neurosim/projects")
    assert response.status_code == 200
    assert len(response.json()) == 0

    # 2. Create
    project_req = {
        "name": "Test Project",
        "description": "Desc",
        "graph": VALID_GRAPH,
    }
    response = client.post("/api/neurosim/projects", json=project_req)
    assert response.status_code == 200
    project_id = response.json()["id"]

    # 3. Get
    response = client.get(f"/api/neurosim/projects/{project_id}")
    assert response.status_code == 200
    assert response.json()["id"] == project_id

    # 4. List again
    response = client.get("/api/neurosim/projects")
    assert len(response.json()) == 1


@pytest.mark.asyncio
async def test_project_persistence(temp_db: Any) -> None:
    # Create first store and save project
    store1 = ProjectStore(temp_db)
    project = Project(
        id="test-id",
        name="Persistent Project",
        updated_at=datetime.now(UTC).isoformat(),
        graph=CanvasGraph(nodes=[], edges=[], metadata={}),
    )
    await store1.save_project(project)

    # Create second store (simulated restart) and retrieve project
    store2 = ProjectStore(temp_db)
    retrieved = await store2.get_project("test-id")

    assert retrieved is not None
    assert retrieved.name == "Persistent Project"
    assert retrieved.id == "test-id"


@pytest.mark.asyncio
async def test_project_pagination(temp_db: Any) -> None:
    store = ProjectStore(temp_db)
    # Create 60 projects
    for i in range(60):
        project = Project(
            id=f"proj-{i:03d}",
            name=f"Project {i}",
            updated_at=datetime.now(UTC).isoformat(),
            graph=CanvasGraph(nodes=[], edges=[], metadata={}),
        )
        await store.save_project(project)

    # Test first page (default 50)
    projects_p1 = await store.list_projects(skip=0, limit=50)
    assert len(projects_p1) == 50

    # Test second page
    projects_p2 = await store.list_projects(skip=50, limit=50)
    assert len(projects_p2) == 10


@pytest.mark.asyncio
async def test_api_pagination(override_project_store: Any) -> None:
    # Create 10 projects
    for i in range(10):
        await override_project_store.save_project(
            Project(
                id=f"api-proj-{i}",
                name=f"API Project {i}",
                updated_at=datetime.now(UTC).isoformat(),
                graph=CanvasGraph(nodes=[], edges=[], metadata={}),
            ),
        )

    response = client.get("/api/neurosim/projects?limit=5")
    assert response.status_code == 200
    assert len(response.json()) == 5

    response = client.get("/api/neurosim/projects?skip=5&limit=5")
    assert response.status_code == 200
    assert len(response.json()) == 5

    response = client.get("/api/neurosim/projects?skip=10&limit=5")
    assert response.status_code == 200
    assert len(response.json()) == 0


@pytest.mark.asyncio
async def test_project_store_lifecycle_uses_shared_default(temp_db: Any) -> None:
    await ProjectStore.initialize(temp_db)
    shared_store = ProjectStore.get_default()

    assert shared_store.db_path == temp_db
    assert await shared_store.ping() is True

    await ProjectStore.close()

    replacement_store = ProjectStore.get_default()
    assert replacement_store is not shared_store
    assert replacement_store.db_path == "projects.db"

    await ProjectStore.close()


@pytest.mark.usefixtures("override_project_store")
def test_project_create_persists_threshold_aware_cnl() -> None:
    project_req = {
        "name": "Reflex Arc",
        "description": "Threshold regression",
        "graph": {
            "nodes": [
                {
                    "id": "sensory_input",
                    "component_id": "lif_population",
                    "parameters": {
                        "name": "sensory_input",
                        "n_neurons": 50,
                        "tau_rc": 0.02,
                        "tau_ref": 0.002,
                        "threshold": 1.0,
                    },
                    "position": [0, 0],
                },
                {
                    "id": "motor_output",
                    "component_id": "lif_population",
                    "parameters": {
                        "name": "motor_output",
                        "n_neurons": 50,
                        "tau_rc": 0.02,
                        "tau_ref": 0.002,
                        "threshold": 0.8,
                    },
                    "position": [320, 0],
                },
            ],
            "edges": [
                {
                    "id": "edge_0",
                    "source_node_id": "sensory_input",
                    "source_port": "out",
                    "target_node_id": "motor_output",
                    "target_port": "in",
                    "parameters": {"weight": 1.0, "delay": 0.001},
                },
            ],
            "metadata": {},
        },
    }

    response = client.post("/api/neurosim/projects", json=project_req)

    assert response.status_code == 200
    payload = response.json()
    assert "firing threshold 0.8" in payload["cnl_spec"]
