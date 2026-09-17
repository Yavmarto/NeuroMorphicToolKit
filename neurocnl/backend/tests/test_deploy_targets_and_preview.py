"""Tests for GET /api/deploy-targets and POST /api/notebook/preview (Phase G)."""

from __future__ import annotations

from fastapi.testclient import TestClient

from backend.app.main import app
from neurocnl.runtime.nir_support import (
    SIMULATOR_RUNTIME_BACKENDS,
    list_supported_backends,
)

client = TestClient(app)

VALID_SPEC = "\n".join(
    [
        "Define a network named feedforward.",
        "Define an input port named input with shape (4,).",
        "Define a linear transformation named w1 with weight matrix shape (3, 4).",
        "Define a LIF neuron named hidden"
        " with time constant 0.02, resistance 1.0, leak voltage 0.0,"
        " and firing threshold 1.0.",
        "Define an output port named output with shape (3,).",
        "input connects to w1.",
        "w1 connects to hidden.",
        "hidden connects to output.",
    ]
)


def test_deploy_targets_lists_all_backends() -> None:
    resp = client.get("/api/deploy-targets")
    assert resp.status_code == 200
    data = resp.json()
    ids = {item["id"] for item in data}
    assert ids == set(list_supported_backends())


def test_deploy_targets_capability_flags_match_runtime_and_deploy_sets() -> None:
    resp = client.get("/api/deploy-targets")
    by_id = {item["id"]: item for item in resp.json()}
    framework_runtime = {"brian2", "sinabs", "rockpool", "nengo"}
    deploy_capable = {"akida", "pynq", "lava", "sc_neurocore_fpga"}
    for backend_id in SIMULATOR_RUNTIME_BACKENDS:
        assert by_id[backend_id]["runtime_capable"] is True
        assert by_id[backend_id]["deploy_capable"] is False
    for backend_id in framework_runtime:
        assert by_id[backend_id]["runtime_capable"] is True
        assert by_id[backend_id]["deploy_capable"] is False
    for backend_id in deploy_capable:
        assert by_id[backend_id]["deploy_capable"] is True
    assert by_id["pynn"]["runtime_capable"] is False
    assert by_id["pynn"]["deploy_capable"] is False


def test_preview_returns_code_and_classification_for_rockpool() -> None:
    resp = client.post(
        "/api/notebook/preview", json={"spec": VALID_SPEC, "target": "rockpool"}
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["target"] == "rockpool"
    assert data["support_level"] == "approximate"
    assert "RockpoolIO" in data["code"]


def test_preview_matches_generate_v2_classification_for_same_spec_and_target() -> None:
    """Parity check: the preview endpoint's classification must match what
    /generate-v2 would compute for the identical spec+target.
    """
    from backend.app.services.notebook_graph_analysis import flatten_and_classify
    from neurocnl.compile import compile_to_nir

    graph = compile_to_nir(VALID_SPEC)
    _, expected, _ = flatten_and_classify(graph, "sinabs")

    resp = client.post(
        "/api/notebook/preview", json={"spec": VALID_SPEC, "target": "sinabs"}
    )
    assert resp.status_code == 200
    assert resp.json()["support_level"] == expected.level


def test_preview_rejects_empty_spec() -> None:
    resp = client.post("/api/notebook/preview", json={"spec": "", "target": "rockpool"})
    assert resp.status_code == 422


def test_preview_is_side_effect_free(tmp_path, monkeypatch) -> None:
    """Confirm the preview endpoint never touches NOTEBOOK_DIR."""
    import backend.app.routers.notebook as notebook_module

    monkeypatch.setattr(notebook_module, "NOTEBOOK_DIR", tmp_path)
    resp = client.post(
        "/api/notebook/preview", json={"spec": VALID_SPEC, "target": "nengo"}
    )
    assert resp.status_code == 200
    assert list(tmp_path.iterdir()) == []
