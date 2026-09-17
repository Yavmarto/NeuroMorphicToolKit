"""End-to-end integration tests for NeuroHub production pipeline (artifact sharing)."""

import os
from collections.abc import Generator

import pytest
from fastapi.testclient import TestClient

from neurohub.tests.mock_suite_server import MockSuiteServer

RUN_PROD_INTEGRATION = os.environ.get("NEUROHUB_RUN_PROD_INTEGRATION", "").lower() == "true"
pytestmark = pytest.mark.skipif(
    not RUN_PROD_INTEGRATION,
    reason="Set NEUROHUB_RUN_PROD_INTEGRATION=true to run local production integration tests.",
)


@pytest.fixture(scope="module")
def mock_server() -> Generator[MockSuiteServer, None, None]:
    """Start the mock suite server for the duration of the module tests."""
    server = MockSuiteServer(port=8082)
    server.start()
    yield server
    server.stop()


def _setup_mock_config(client: TestClient, mock_url: str) -> None:
    config_res = client.put(
        "/api/neurohub/config",
        json={
            "neurosim_url": mock_url,
            "neurochip_url": mock_url,
            "neurobench_url": mock_url,
            "neurosense_url": mock_url,
            "neurocnl_url": mock_url,
            "shared_storage_path": "./shared_assets",
            "default_project_settings": {},
        },
    )
    assert config_res.status_code == 200


def _create_e2e_project(client: TestClient, proj_id: str) -> None:
    create_res = client.post(
        "/api/neurohub/projects",
        json={
            "id": proj_id,
            "name": "E2E Project",
            "description": "End to end integration test project",
            "created_at": "2026-03-20T10:00:00Z",
            "updated_at": "2026-03-20T10:00:00Z",
            "owner": "admin",
            "members": [{"user_id": "admin", "name": "Admin", "role": "admin"}],
            "links": {"neurosim_project_id": "sim_123", "neurochip_target_id": "teensy_41"},
            "tags": ["e2e", "prod"],
        },
    )
    assert create_res.status_code == 201


def _create_shared_asset(client: TestClient, asset_id: str) -> None:
    import hashlib

    os.environ["NEUROHUB_SKIP_ASSET_VALIDATION"] = "true"
    sha256_hash = hashlib.sha256(b"{}").hexdigest()

    asset_res = client.post(
        "/api/neurohub/assets",
        json={
            "id": asset_id,
            "name": "E2E Template",
            "description": "Shared asset for testing",
            "type": "neurosim_template",
            "version": 1,
            "author": "admin",
            "tags": ["e2e"],
            "created_at": "2026-03-20T10:00:00Z",
            "file_path": "shared/e2e_template.json",
            "file_size_bytes": 2,
            "sha256": sha256_hash,
            "metadata": {},
        },
    )
    assert asset_res.status_code == 201


def _verify_asset_retrieval(client: TestClient, asset_id: str) -> None:
    get_asset_res = client.get(f"/api/neurohub/assets/{asset_id}")
    assert get_asset_res.status_code == 200
    assert get_asset_res.json()["name"] == "E2E Template"


def _verify_project_links(client: TestClient, proj_id: str) -> None:
    proj_res = client.get(f"/api/neurohub/projects/{proj_id}")
    assert proj_res.status_code == 200
    proj_data = proj_res.json()
    assert proj_data["links"]["neurosim_project_id"] == "sim_123"


def _export_and_import_project(client: TestClient, proj_id: str) -> None:
    export_res = client.post(f"/api/neurohub/projects/{proj_id}/export")
    assert export_res.status_code == 200
    bundle = export_res.json()
    assert bundle["project"]["id"] == proj_id
    assert bundle["version"] == 2

    new_proj_id = "imported_proj"
    bundle["project"]["id"] = new_proj_id
    import_res = client.post("/api/neurohub/projects/import", json=bundle)
    assert import_res.status_code == 200
    assert import_res.json()["id"] == new_proj_id

    get_res = client.get(f"/api/neurohub/projects/{new_proj_id}")
    assert get_res.status_code == 200


def test_full_pipeline_e2e(client: TestClient, mock_server: MockSuiteServer) -> None:
    """Project → shared asset → export/import bundle."""
    _setup_mock_config(client, mock_server.base_url)

    proj_id = "e2e_proj_1"
    _create_e2e_project(client, proj_id)

    asset_id = "e2e_asset_1"
    _create_shared_asset(client, asset_id)
    _verify_asset_retrieval(client, asset_id)
    _verify_project_links(client, proj_id)
    _export_and_import_project(client, proj_id)
