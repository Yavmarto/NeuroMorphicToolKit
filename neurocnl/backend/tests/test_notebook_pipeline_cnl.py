"""Tests for the pipeline-CNL endpoints (``generate-pipeline-cnl`` /
``parse-pipeline-cnl``) and the pipeline-CNL audit-metadata field on
``generate-v2`` (split out of the former ``test_notebook_generate_v2.py``).
"""

from __future__ import annotations

from pathlib import Path
from unittest.mock import patch

import pytest

from backend.tests.notebook_test_fixtures import VALID_SPEC, client


def test_generate_pipeline_cnl_renders_train_evaluate_export() -> None:
    # PipelineConfigPayload always has concrete (non-None) defaults for
    # every field, so the rendered Train sentence includes every
    # Train-group field (epochs, learning_rate, batch_size, optimizer,
    # training_strategy, loss_function), not just the ones set here.
    resp = client.post(
        "/api/notebook/generate-pipeline-cnl",
        json={
            "pipeline_config": {
                "epochs": 5,
                "learning_rate": 0.01,
                "run_evaluation": True,
                "eval_metrics": ["accuracy"],
                "export_nir": True,
                "generate_py_download": False,
            }
        },
    )
    assert resp.status_code == 200
    text = resp.json()["cnl_text"]
    first_line = text.splitlines()[0]
    assert first_line.startswith("Train the network for 5 epochs with")
    assert "learning rate 0.01" in first_line
    assert "Evaluate the network with accuracy metrics." in text
    assert "Export the trained network to NIR." in text


def test_generate_pipeline_cnl_default_config_does_not_raise() -> None:
    resp = client.post("/api/notebook/generate-pipeline-cnl", json={})
    assert resp.status_code == 200
    assert resp.json()["cnl_text"] != ""


def test_parse_pipeline_cnl_overrides_epochs_and_learning_rate() -> None:
    resp = client.post(
        "/api/notebook/parse-pipeline-cnl",
        json={
            "cnl_text": "Train the network for 7 epochs with learning rate 0.02.",
            "pipeline_config": {},
        },
    )
    assert resp.status_code == 200
    cfg = resp.json()["pipeline_config"]
    assert cfg["epochs"] == 7
    assert cfg["learning_rate"] == pytest.approx(0.02)
    # Unmentioned fields keep their base_cfg (default) value.
    assert cfg["optimizer"] == "Adam"


def test_parse_pipeline_cnl_overrides_eval_metrics() -> None:
    resp = client.post(
        "/api/notebook/parse-pipeline-cnl",
        json={
            "cnl_text": "Evaluate the network with accuracy metrics.",
            "pipeline_config": {"eval_metrics": ["loss"]},
        },
    )
    assert resp.status_code == 200
    cfg = resp.json()["pipeline_config"]
    assert cfg["eval_metrics"] == ["accuracy"]
    assert cfg["run_evaluation"] is True


def test_parse_pipeline_cnl_overrides_export_nir() -> None:
    resp = client.post(
        "/api/notebook/parse-pipeline-cnl",
        json={
            "cnl_text": "Export the trained network to NIR.",
            "pipeline_config": {"export_nir": False, "generate_py_download": True},
        },
    )
    assert resp.status_code == 200
    cfg = resp.json()["pipeline_config"]
    assert cfg["export_nir"] is True
    # generate_py_download was not mentioned in the CNL text, so its
    # base_cfg value (True) must survive unchanged.
    assert cfg["generate_py_download"] is True


def test_parse_pipeline_cnl_empty_text_returns_base_config_unchanged() -> None:
    base = {"epochs": 42}
    resp = client.post(
        "/api/notebook/parse-pipeline-cnl",
        json={"cnl_text": "", "pipeline_config": base},
    )
    assert resp.status_code == 200
    assert resp.json()["pipeline_config"]["epochs"] == 42


def test_parse_pipeline_cnl_malformed_sentence_returns_422() -> None:
    resp = client.post(
        "/api/notebook/parse-pipeline-cnl",
        json={
            "cnl_text": "Train the network for 5 epochs with foo optimizer.",
            "pipeline_config": {},
        },
    )
    assert resp.status_code == 422
    assert "unknown_optimizer_phrase" in resp.json()["detail"]


def test_generate_pipeline_cnl_then_parse_pipeline_cnl_round_trips() -> None:
    base_cfg = {
        "epochs": 20,
        "learning_rate": 0.005,
        "batch_size": 64,
        "optimizer": "SGD",
        "training_strategy": "bptt",
        "loss_function": "cross_entropy",
        "run_evaluation": True,
        "eval_metrics": ["accuracy", "loss"],
        "export_nir": True,
        "generate_py_download": True,
    }
    gen_resp = client.post(
        "/api/notebook/generate-pipeline-cnl", json={"pipeline_config": base_cfg}
    )
    assert gen_resp.status_code == 200
    cnl_text = gen_resp.json()["cnl_text"]

    parse_resp = client.post(
        "/api/notebook/parse-pipeline-cnl",
        json={"cnl_text": cnl_text, "pipeline_config": base_cfg},
    )
    assert parse_resp.status_code == 200
    parsed_cfg = parse_resp.json()["pipeline_config"]
    for key, value in base_cfg.items():
        assert parsed_cfg[key] == value


def test_generate_v2_pipeline_cnl_is_optional_and_defaults_empty(
    tmp_path: Path,
) -> None:
    with patch("backend.app.routers.notebook.NOTEBOOK_DIR", tmp_path):
        resp = client.post(
            "/api/notebook/generate-v2",
            json={"spec": VALID_SPEC, "pipeline_config": {"framework": "snntorch_sim"}},
        )
    assert resp.status_code == 200


def test_generate_v2_pipeline_cnl_stashed_in_notebook_metadata(tmp_path: Path) -> None:
    with patch("backend.app.routers.notebook.NOTEBOOK_DIR", tmp_path):
        resp = client.post(
            "/api/notebook/generate-v2",
            json={
                "spec": VALID_SPEC,
                "pipeline_config": {"framework": "snntorch_sim"},
                "pipeline_cnl": "Train the network for 50 epochs.",
            },
        )
    assert resp.status_code == 200
    workspace_folder = resp.json()["workspace_folder"]
    notebook_path = (
        tmp_path / workspace_folder / resp.json()["notebooks"][0]["filename"]
    )
    import json as _json

    nb = _json.loads(notebook_path.read_text())
    assert (
        nb["metadata"]["neurocnl"]["pipeline_cnl"] == "Train the network for 50 epochs."
    )


def test_generate_v2_pipeline_cnl_not_used_to_override_pipeline_config(
    tmp_path: Path,
) -> None:
    """pipeline_cnl is provenance-only — it must never change notebook
    generation, even if it disagrees with pipeline_config (e.g. a
    stale/unapplied draft). The only allowed difference between two
    otherwise-identical requests is the stashed metadata field itself."""
    import json as _json

    def _generate(pipeline_cnl: str) -> dict:
        with patch(
            "backend.app.routers.notebook.NOTEBOOK_DIR",
            tmp_path / pipeline_cnl.__hash__().__str__(),
        ):
            resp = client.post(
                "/api/notebook/generate-v2",
                json={
                    "spec": VALID_SPEC,
                    "pipeline_config": {"framework": "snntorch_sim", "epochs": 99},
                    "pipeline_cnl": pipeline_cnl,
                },
            )
        assert resp.status_code == 200
        workspace_folder = resp.json()["workspace_folder"]
        notebook_dir = tmp_path / pipeline_cnl.__hash__().__str__()
        notebook_path = (
            notebook_dir / workspace_folder / resp.json()["notebooks"][0]["filename"]
        )
        return _json.loads(notebook_path.read_text())

    nb_disagreeing = _generate("Train the network for 1 epochs.")
    nb_empty = _generate("")

    nb_disagreeing["metadata"]["neurocnl"].pop("pipeline_cnl", None)
    assert nb_disagreeing == nb_empty
