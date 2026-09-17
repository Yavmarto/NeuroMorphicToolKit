"""Tests for the custom nodes REST API router."""

import textwrap
from pathlib import Path
from typing import Any

import pytest
from fastapi.testclient import TestClient

import neurosim.app.routers.custom_nodes as m
import neurosim.app.services.components as component_service
from neurosim.app.main import app

client = TestClient(app)

VALID_SOURCE = textwrap.dedent(
    """
    from nmtk_sdk import CustomNode, param, port

    class TestNode(CustomNode):
        name = "Test Node"
        category = "neurons"
        canvases = ["model"]
        frameworks = ["nengo"]
        base_component_id = "lif_population"

        @param(type="float", default=0.02, label="Tau")
        def tau_rc(self): ...

        @port(id="in", direction="input", label="In")
        def input_port(self): ...
    """
)


def _use_custom_dir(monkeypatch: pytest.MonkeyPatch, path: Any) -> None:
    monkeypatch.setattr(m, "CUSTOM_NODES_DIR", path)
    monkeypatch.setattr(component_service, "CUSTOM_NODES_DIR", path)
    component_service._invalidate_cache()


def test_list_custom_nodes_empty(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    _use_custom_dir(monkeypatch, tmp_path / "custom_nodes")
    resp = client.get("/api/neurosim/custom-nodes")
    assert resp.status_code == 200
    assert resp.json() == []


def test_save_then_list(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    custom_dir = tmp_path / "custom_nodes"
    _use_custom_dir(monkeypatch, custom_dir)

    save_resp = client.post(
        "/api/neurosim/custom-nodes/save",
        json={
            "filename": "test_node.py",
            "source": VALID_SOURCE,
        },
    )
    assert save_resp.status_code == 200
    assert save_resp.json()["filename"] == "test_node.py"

    list_resp = client.get("/api/neurosim/custom-nodes")
    assert "test_node.py" in list_resp.json()


def test_delete_nonexistent_returns_404(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    _use_custom_dir(monkeypatch, tmp_path / "custom_nodes")
    resp = client.delete("/api/neurosim/custom-nodes/ghost.py")
    assert resp.status_code == 404


def test_traversal_via_save_returns_400(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    _use_custom_dir(monkeypatch, tmp_path / "custom_nodes")
    # Path traversal attempt goes through _validate_filename in the request body
    resp = client.post(
        "/api/neurosim/custom-nodes/save",
        json={
            "filename": "../evil.py",
            "source": "malicious",
        },
    )
    assert resp.status_code == 400


def test_save_non_py_returns_400(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    _use_custom_dir(monkeypatch, tmp_path / "custom_nodes")
    resp = client.post(
        "/api/neurosim/custom-nodes/save",
        json={
            "filename": "evil.sh",
            "source": "rm -rf /",
        },
    )
    assert resp.status_code == 400


def test_save_creates_file_on_disk(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    custom_dir = tmp_path / "custom_nodes"
    _use_custom_dir(monkeypatch, custom_dir)

    source = VALID_SOURCE
    resp = client.post(
        "/api/neurosim/custom-nodes/save",
        json={
            "filename": "hello.py",
            "source": source,
        },
    )
    assert resp.status_code == 200
    saved = (custom_dir / "hello.py").read_text()
    assert "class TestNode(CustomNode):" in saved
    assert 'name = "Test Node"' in saved
    assert 'node_id = "custom_test_node_' in saved


def test_source_and_save_reject_stale_revision(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    custom_dir = tmp_path / "custom_nodes"
    _use_custom_dir(monkeypatch, custom_dir)
    saved = client.post(
        "/api/neurosim/custom-nodes/save",
        json={"filename": "revision.py", "source": VALID_SOURCE},
    )
    assert saved.status_code == 200
    component_id = saved.json()["component_id"]

    source_response = client.post(
        "/api/neurosim/custom-nodes/source",
        json={
            "component_id": component_id,
            "display_name": "Test Node",
            "parameters": {},
        },
    )
    assert source_response.status_code == 200
    payload = source_response.json()
    (custom_dir / "revision.py").write_text(payload["source"] + "\n# external edit\n")

    conflict = client.post(
        "/api/neurosim/custom-nodes/save",
        json={
            "source": payload["source"],
            "target_component_id": component_id,
            "expected_revision": payload["revision"],
        },
    )
    assert conflict.status_code == 409
    assert "Reload" in conflict.json()["detail"]


def test_failed_runtime_load_restores_previous_source(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    custom_dir = tmp_path / "custom_nodes"
    _use_custom_dir(monkeypatch, custom_dir)
    saved = client.post(
        "/api/neurosim/custom-nodes/save",
        json={"filename": "rollback.py", "source": VALID_SOURCE},
    )
    assert saved.status_code == 200
    payload = saved.json()
    original_source = (custom_dir / "rollback.py").read_text(encoding="utf-8")
    broken_source = payload["source"].replace(
        'category = "neurons"',
        'category = "neurons"\n    runtime_failure = 1 / 0',
    )

    response = client.post(
        "/api/neurosim/custom-nodes/save",
        json={
            "source": broken_source,
            "target_component_id": payload["component_id"],
            "expected_revision": payload["revision"],
        },
    )

    assert response.status_code == 422
    assert "previous version was restored" in response.json()["detail"]
    assert (custom_dir / "rollback.py").read_text(encoding="utf-8") == original_source


def test_delete_removes_file(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    custom_dir = tmp_path / "custom_nodes"
    custom_dir.mkdir(parents=True)
    _use_custom_dir(monkeypatch, custom_dir)

    node_file = custom_dir / "to_delete.py"
    node_file.write_text("# node")

    resp = client.delete("/api/neurosim/custom-nodes/to_delete.py")
    assert resp.status_code == 200
    assert resp.json() == {"deleted": "to_delete.py"}
    assert not node_file.exists()
