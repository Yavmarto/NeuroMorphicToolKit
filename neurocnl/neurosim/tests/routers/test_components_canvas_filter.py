import textwrap
from collections.abc import Iterator
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

import neurosim.app.services.components as svc
from neurosim.app.main import app

client = TestClient(app)


@pytest.fixture(autouse=True)
def _reset_cache() -> Iterator[None]:  # noqa: ANN202
    svc._invalidate_cache()  # noqa: SLF001
    yield
    svc._invalidate_cache()  # noqa: SLF001


def test_no_filter_returns_all_components(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    # Without ?canvas= param, all components are returned
    monkeypatch.setattr(svc, "CUSTOM_NODES_DIR", tmp_path / "none")
    resp = client.get("/api/neurosim/components")
    assert resp.status_code == 200
    assert isinstance(resp.json(), list)
    # Built-in JSON components have empty canvas_contexts — all returned
    for c in resp.json():
        # all have required fields
        assert "id" in c
        assert "name" in c


def test_canvas_filter_excludes_wrong_context(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    training_only = textwrap.dedent(
        """
        from nmtk_sdk import CustomNode

        class TrainingOnly(CustomNode):
            name = "Training Only"
            category = "neurons"
            canvases = ["training"]
            frameworks = ["nengo"]
            author = "t"

            def to_nengo(self, params): return object()
    """
    )
    custom_dir = tmp_path / "custom_nodes"
    custom_dir.mkdir()
    (custom_dir / "training_only.py").write_text(training_only)
    monkeypatch.setattr(svc, "CUSTOM_NODES_DIR", custom_dir)
    svc._invalidate_cache()  # noqa: SLF001

    resp = client.get("/api/neurosim/components?canvas=model")
    assert resp.status_code == 200
    names = [c["name"] for c in resp.json()]
    assert "Training Only" not in names


def test_canvas_filter_includes_correct_context(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    model_node = textwrap.dedent(
        """
        from nmtk_sdk import CustomNode

        class ModelNode(CustomNode):
            name = "Model Node"
            category = "neurons"
            canvases = ["model"]
            frameworks = ["nengo"]
            author = "t"

            def to_nengo(self, params): return object()
    """
    )
    custom_dir = tmp_path / "custom_nodes"
    custom_dir.mkdir()
    (custom_dir / "model_node.py").write_text(model_node)
    monkeypatch.setattr(svc, "CUSTOM_NODES_DIR", custom_dir)
    svc._invalidate_cache()  # noqa: SLF001

    resp = client.get("/api/neurosim/components?canvas=model")
    assert resp.status_code == 200
    names = [c["name"] for c in resp.json()]
    assert "Model Node" in names


def test_builtin_components_pass_any_canvas_filter(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    monkeypatch.setattr(svc, "CUSTOM_NODES_DIR", tmp_path / "none")
    svc._invalidate_cache()  # noqa: SLF001
    # Built-in components have empty canvas_contexts — pass any filter
    resp = client.get("/api/neurosim/components?canvas=inference")
    assert resp.status_code == 200
    data = resp.json()
    # All built-ins (empty canvas_contexts) should be present
    builtin = [c for c in data if not c.get("canvas_contexts")]
    assert len(builtin) > 0
