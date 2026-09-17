"""Tests for GET /api/datasets/exists."""

from __future__ import annotations

from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from backend.app.main import app


@pytest.fixture
def isolated_data_dir(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    monkeypatch.setattr("backend.app.routers.datasets.DATA_DIR", tmp_path)
    return tmp_path


def test_exists_true_for_a_file_under_data_dir(isolated_data_dir: Path) -> None:
    upload_dir = isolated_data_dir / "pipeline_uploads" / "abc123"
    upload_dir.mkdir(parents=True)
    dataset_file = upload_dir / "ds_train.pt"
    dataset_file.write_bytes(b"tensor-bytes")

    client = TestClient(app)
    response = client.get("/api/datasets/exists", params={"path": str(dataset_file)})
    assert response.status_code == 200
    assert response.json() == {"exists": True}


def test_exists_false_for_a_missing_file_under_data_dir(
    isolated_data_dir: Path,
) -> None:
    missing_path = isolated_data_dir / "pipeline_uploads" / "gone" / "ds_train.pt"

    client = TestClient(app)
    response = client.get("/api/datasets/exists", params={"path": str(missing_path)})
    assert response.status_code == 200
    assert response.json() == {"exists": False}


def test_exists_false_for_a_path_outside_data_dir(
    isolated_data_dir: Path, tmp_path_factory: pytest.TempPathFactory
) -> None:
    outside_dir = tmp_path_factory.mktemp("outside")
    outside_file = outside_dir / "secret.txt"
    outside_file.write_bytes(b"not a dataset")

    client = TestClient(app)
    response = client.get("/api/datasets/exists", params={"path": str(outside_file)})
    assert response.status_code == 200
    assert response.json() == {"exists": False}


def test_exists_false_for_directory_not_a_file(isolated_data_dir: Path) -> None:
    upload_dir = isolated_data_dir / "pipeline_uploads" / "abc123"
    upload_dir.mkdir(parents=True)

    client = TestClient(app)
    response = client.get("/api/datasets/exists", params={"path": str(upload_dir)})
    assert response.status_code == 200
    assert response.json() == {"exists": False}


def test_exists_does_not_shadow_the_dataset_id_route(
    isolated_data_dir: Path,
) -> None:
    # /datasets/exists must resolve to this endpoint, not be swallowed by
    # GET /datasets/{dataset_id} treating "exists" as a dataset id.
    client = TestClient(app)
    response = client.get("/api/datasets/exists", params={"path": str(isolated_data_dir)})
    assert response.status_code == 200
    assert "exists" in response.json()
