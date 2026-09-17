"""Tests for the notebook assembly/``generate-v2`` router surface
(split out of the former ``test_notebook_generate_v2.py``).
"""

from __future__ import annotations

import base64
import io as _io
from pathlib import Path
from typing import Any
from unittest.mock import patch

import httpx
import nir
import numpy as np
import pytest
from fastapi import HTTPException

from backend.app.routers.notebook import (
    DagNodePayload,
    PhaseDAGPayload,
    PipelineConfigPayload,
    PipelinePhasesPayload,
    _build_akida_mnist_notebook,
    _build_v2_notebook,
    _publish_via_contents_api,
)
from backend.tests.notebook_test_fixtures import (
    CNN_SINABS_NIR,
    RESHAPED_SPEC,
    SMALL_LIF_FIRST_SPEC,
    VALID_SPEC,
    _build_nb_for_braille,
    _code_sources,
    _FakeJupyterContents,
    _generate_v2,
    _generate_with_pt_loader,
    _second_code_after_md,
    _unsupported_type_graph,
    client,
)
from neurocnl.nir_cnl.renderer import NIR_Renderer


def test_pipeline_config_payload_defaults() -> None:
    cfg = PipelineConfigPayload()
    assert cfg.dataset == ""
    assert cfg.framework == "snntorch_sim"
    assert cfg.epochs == 50
    assert cfg.seed == 42
    assert cfg.batch_size == 32
    assert cfg.learning_rate == pytest.approx(1e-3)
    assert cfg.optimizer == "Adam"
    assert cfg.run_evaluation is True
    assert cfg.export_nir is False


def test_snntorch_sim_juv_cell_pins_snntorch_and_torch_versions(default_nb) -> None:
    juv_src = "".join(default_nb["cells"][0]["source"])
    assert '"snntorch==0.9.4"' in juv_src
    assert '"torch==2.13.0"' in juv_src


def test_notebook_has_cells(default_nb) -> None:
    assert len(default_nb["cells"]) >= 4


def test_config_cell_is_second_code_cell(default_nb) -> None:
    code_cells = [c for c in default_nb["cells"] if c["cell_type"] == "code"]
    # Index 0 is the hidden juv dep cell; index 1 is the config dict.
    config_src = "".join(code_cells[1]["source"])
    assert "config = {" in config_src
    # ponytail: only user-configured workspace fields are emitted; defaults omitted
    assert '"framework"' in config_src
    assert '"dataset"' in config_src
    assert '"epochs"' not in config_src
    assert '"batch_size"' not in config_src


def test_config_cell_reflects_custom_values() -> None:
    from backend.app.routers.notebook import compile_to_nir

    graph = compile_to_nir(VALID_SPEC)
    cfg = PipelineConfigPayload(framework="nengo", dataset="tonic_nmnist")
    nb, _ = _build_v2_notebook(
        VALID_SPEC,
        graph,
        cfg,
        "2026-01-01 00:00 UTC",
        pipeline_phases=PipelinePhasesPayload(),
    )
    code_cells = [c for c in nb["cells"] if c["cell_type"] == "code"]
    config_src = "".join(code_cells[1]["source"])
    assert "nengo" in config_src  # framework
    assert "tonic_nmnist" in config_src  # dataset


def test_evaluate_section_present_when_enabled(default_nb) -> None:
    md_src = " ".join(
        "".join(c["source"])
        for c in default_nb["cells"]
        if c["cell_type"] == "markdown"
    )
    assert "## Evaluate" in md_src


def test_evaluate_section_absent_when_disabled() -> None:
    from backend.app.routers.notebook import compile_to_nir

    graph = compile_to_nir(VALID_SPEC)
    nb, _ = _build_v2_notebook(
        VALID_SPEC,
        graph,
        PipelineConfigPayload(run_evaluation=False),
        "2026-01-01 00:00 UTC",
        pipeline_phases=PipelinePhasesPayload(),
    )
    md_src = " ".join(
        "".join(c["source"]) for c in nb["cells"] if c["cell_type"] == "markdown"
    )
    assert "## Evaluate" not in md_src


def test_generate_v2_rejects_empty_spec() -> None:
    resp = client.post("/api/notebook/generate-v2", json={"spec": ""})
    assert resp.status_code == 422


def test_generate_v2_rejects_whitespace_spec() -> None:
    resp = client.post("/api/notebook/generate-v2", json={"spec": "   \n  "})
    assert resp.status_code == 422


def test_generate_v2_dual_writes_when_jupyter_worker_configured(tmp_path: Path) -> None:
    with (
        patch("backend.app.routers.notebook.NOTEBOOK_DIR", tmp_path),
        patch("backend.app.routers.notebook.JUPYTER_WORKER_URL", "http://jupyter:8008"),
        patch("backend.app.routers.notebook._publish_via_contents_api") as mock_publish,
    ):
        resp = client.post(
            "/api/notebook/generate-v2",
            json={"spec": VALID_SPEC, "pipeline_config": {"framework": "snntorch_sim"}},
        )
    assert resp.status_code == 200
    mock_publish.assert_called_once()
    filename = resp.json()["notebooks"][0]["filename"]
    workspace_folder = resp.json()["workspace_folder"]
    # workspace_folder is "{slug}/notebooks" — file lives at NOTEBOOK_DIR / workspace_folder / filename
    on_disk = tmp_path / workspace_folder / filename
    assert on_disk.exists(), f"expected mirror at {on_disk}"


def test_generate_v2_succeeds_when_optional_execution_mirror_is_read_only(
    tmp_path: Path,
    caplog: pytest.LogCaptureFixture,
) -> None:
    """A Jupyter Contents publish is durable even if the local cache is unavailable."""
    blocked_dir = tmp_path / "not-a-directory"
    blocked_dir.write_text("blocked", encoding="utf-8")

    with (
        patch("backend.app.routers.notebook.NOTEBOOK_DIR", blocked_dir),
        patch("backend.app.routers.notebook.JUPYTER_WORKER_URL", "http://jupyter:8008"),
        patch("backend.app.routers.notebook._publish_via_contents_api") as mock_publish,
    ):
        resp = client.post(
            "/api/notebook/generate-v2",
            json={"spec": VALID_SPEC, "pipeline_config": {"framework": "snntorch_sim"}},
        )

    assert resp.status_code == 200
    mock_publish.assert_called_once()
    assert "notebook_execution_mirror_unavailable" in caplog.text


@pytest.mark.parametrize("node_type", ["dataLoader", "testLoader"])
def test_generate_v2_republishes_uploaded_dataset_as_artifact(
    tmp_path: Path,
    node_type: str,
) -> None:
    """Regression: a Data Loader node's dataset_path pointing at a file
    uploaded via POST /datasets/upload-raw (DATA_DIR/pipeline_uploads/...)
    must ride along as a published artifact — not be baked in as a raw
    suite_api-local path the Jupyter worker container can never see."""
    uploaded = tmp_path / "pipeline_uploads" / "abc123" / "lif_stimulus_d.pt"
    uploaded.parent.mkdir(parents=True)
    uploaded.write_bytes(b"fake-tensor-bytes")

    with (
        patch("backend.app.routers.notebook.NOTEBOOK_DIR", tmp_path),
        patch("backend.app.routers.notebook.JUPYTER_WORKER_URL", "http://jupyter:8008"),
        patch("backend.app.routers.notebook.DATA_DIR", tmp_path),
        patch("backend.app.routers.notebook._publish_via_contents_api") as mock_publish,
    ):
        resp = client.post(
            "/api/notebook/generate-v2",
            json={
                "spec": VALID_SPEC,
                "pipeline_config": {"framework": "snntorch_sim"},
                "pipeline_phases": {
                    "train": {
                        "nodes": [
                            {
                                "id": "dl1",
                                "type": node_type,
                                "parameters": {
                                    "format": "pt",
                                    "dataset_path": str(uploaded),
                                },
                            }
                        ],
                        "edges": [],
                    }
                },
            },
        )

    assert resp.status_code == 200
    mock_publish.assert_called_once()
    _workspace_folder, _built, artifacts = mock_publish.call_args.args
    assert artifacts["dl1_lif_stimulus_d.pt"] == b"fake-tensor-bytes"

    nb = _built[0][1]
    code_cells = [c for c in nb["cells"] if c["cell_type"] == "code"]
    dataset_cell_source = "".join(
        "".join(c["source"]) for c in code_cells if "torch.load" in "".join(c["source"])
    )
    assert "torch.load('dl1_lif_stimulus_d.pt'" in dataset_cell_source
    assert str(uploaded) not in dataset_cell_source


def test_generate_v2_leaves_non_uploaded_dataset_path_untouched(
    tmp_path: Path,
) -> None:
    """A dataset_path the user typed by hand (not under DATA_DIR/pipeline_uploads/)
    must pass through unchanged, even with a Jupyter worker configured — the
    republish-as-artifact rewrite only applies to paths this app itself wrote."""
    with (
        patch("backend.app.routers.notebook.NOTEBOOK_DIR", tmp_path),
        patch("backend.app.routers.notebook.JUPYTER_WORKER_URL", "http://jupyter:8008"),
        patch("backend.app.routers.notebook.DATA_DIR", tmp_path / "unrelated_data_dir"),
        patch("backend.app.routers.notebook._publish_via_contents_api") as mock_publish,
    ):
        resp = client.post(
            "/api/notebook/generate-v2",
            json={
                "spec": VALID_SPEC,
                "pipeline_config": {"framework": "snntorch_sim"},
                "pipeline_phases": {
                    "train": {
                        "nodes": [
                            {
                                "id": "dl1",
                                "type": "dataLoader",
                                "parameters": {
                                    "format": "pt",
                                    "dataset_path": "/tmp/hand_typed_ds.pt",
                                },
                            }
                        ],
                        "edges": [],
                    }
                },
            },
        )

    assert resp.status_code == 200
    mock_publish.assert_called_once()
    _workspace_folder, _built, artifacts = mock_publish.call_args.args
    # Weight-placeholder artifacts (e.g. weights_*.npz) may still be present —
    # only the dataset-rewrite path is under test here.
    assert not any("hand_typed_ds" in name for name in artifacts)

    nb = _built[0][1]
    code_cells = [c for c in nb["cells"] if c["cell_type"] == "code"]
    dataset_cell_source = "".join(
        "".join(c["source"]) for c in code_cells if "torch.load" in "".join(c["source"])
    )
    assert "torch.load('/tmp/hand_typed_ds.pt'" in dataset_cell_source


def test_generate_v2_happy_path_returns_notebook_entry(tmp_path: Path) -> None:
    with patch("backend.app.routers.notebook.NOTEBOOK_DIR", tmp_path):
        resp = client.post(
            "/api/notebook/generate-v2",
            json={
                "spec": VALID_SPEC,
                "pipeline_config": {
                    "dataset": "NMNIST",
                    "framework": "snntorch_sim",
                    "epochs": 50,
                    "batch_size": 32,
                    "learning_rate": 1e-3,
                    "optimizer": "Adam",
                    "run_evaluation": True,
                    "export_nir": False,
                },
            },
        )
    assert resp.status_code == 200
    data = resp.json()
    assert "workspace_folder" in data
    assert "notebooks" in data
    assert len(data["notebooks"]) == 1
    assert data["notebooks"][0]["target"] == "snntorch_sim"


def test_generate_v2_framework_reflected_in_filename(tmp_path: Path) -> None:
    with patch("backend.app.routers.notebook.NOTEBOOK_DIR", tmp_path):
        resp = client.post(
            "/api/notebook/generate-v2",
            json={"spec": VALID_SPEC, "pipeline_config": {"framework": "nengo"}},
        )
    assert resp.status_code == 200
    filename = resp.json()["notebooks"][0]["filename"]
    assert "nengo" in filename


def test_generate_v2_response_includes_generated_at(tmp_path: Path) -> None:
    import time

    before = time.time()
    with patch("backend.app.routers.notebook.NOTEBOOK_DIR", tmp_path):
        resp = client.post(
            "/api/notebook/generate-v2",
            json={"spec": VALID_SPEC, "pipeline_config": {"framework": "snntorch_sim"}},
        )
    after = time.time()
    assert resp.status_code == 200
    generated_at = resp.json()["generated_at"]
    assert before <= generated_at <= after


def test_notebook_last_modified_reports_local_mtime_after_generation(
    tmp_path: Path,
) -> None:
    with patch("backend.app.routers.notebook.NOTEBOOK_DIR", tmp_path):
        gen_resp = client.post(
            "/api/notebook/generate-v2",
            json={"spec": VALID_SPEC, "pipeline_config": {"framework": "snntorch_sim"}},
        )
        assert gen_resp.status_code == 200
        data = gen_resp.json()
        workspace_folder = data["workspace_folder"]
        filename = data["notebooks"][0]["filename"]

        status_resp = client.get(
            "/api/notebook/last-modified",
            params={"workspace_folder": workspace_folder, "filename": filename},
        )
    assert status_resp.status_code == 200
    last_modified = status_resp.json()["last_modified"]
    assert last_modified is not None
    assert last_modified >= data["generated_at"]


def test_notebook_last_modified_returns_none_when_missing(tmp_path: Path) -> None:
    with patch("backend.app.routers.notebook.NOTEBOOK_DIR", tmp_path):
        resp = client.get(
            "/api/notebook/last-modified",
            params={"workspace_folder": "nope/notebooks", "filename": "missing.ipynb"},
        )
    assert resp.status_code == 200
    assert resp.json()["last_modified"] is None


def test_pipeline_config_payload_eval_metrics_default() -> None:
    cfg = PipelineConfigPayload()
    assert cfg.eval_metrics == ["accuracy", "loss"]
    assert cfg.generate_py_download is True


def test_dataset_loading_cell_present(default_nb) -> None:
    """A dataset loading code cell must appear before the architecture cell."""
    code_cells = [c for c in default_nb["cells"] if c["cell_type"] == "code"]
    dataset_cells = [
        c
        for c in code_cells
        if "DataLoader" in "".join(c["source"]) or "tonic" in "".join(c["source"])
    ]
    assert len(dataset_cells) >= 1, "Expected at least one dataset loading cell"


def test_dataset_loading_code_resolves_catalog_entry() -> None:
    """Regression: an unrecognized dataset id that IS in the dataset catalog
    must produce an informative comment naming the real dataset, not the
    generic 'replace with your DataLoader' placeholder with no information."""
    from backend.app.routers.notebook import _dataset_loading_code

    # "mnist_spike" is a real fixture entry in backend/assets/datasets/catalog.json.
    code = _dataset_loading_code("mnist_spike", 32)
    assert "MNIST Spike Encoded" in code
    assert "datasets/mnist_spike/mnist_spike.h5" in code
    assert "# Dataset 'mnist_spike' — replace with your DataLoader" not in code


def test_dataset_loading_code_nmnist_bin_uses_real_nmnist_loader() -> None:
    """Regression: a catalog entry whose format is nmnist_bin IS N-MNIST's own
    raw format — it must reuse the real tonic.datasets.NMNIST loader, not a
    placeholder, even though its catalog id isn't the literal string 'NMNIST'."""
    from backend.app.services.dataset_catalog import DatasetCatalog, DatasetCatalogEntry

    fake_entry = DatasetCatalogEntry(
        id="nmnist-abc123",
        label="N-MNIST (mirror)",
        description="N-MNIST binary mirror",
        storage_path="datasets/nmnist-abc123/Test.zip",
        format="nmnist_bin",
    )
    with patch(
        "backend.app.routers.notebook.load_dataset_catalog",
        return_value=DatasetCatalog(datasets=[fake_entry]),
    ):
        from backend.app.routers.notebook import _dataset_loading_code

        code = _dataset_loading_code("nmnist-abc123", 32)
    assert "tonic.datasets.NMNIST(save_to=" in code
    assert "replace with your DataLoader" not in code


def test_dataset_loading_code_custom_with_path_loads_for_real() -> None:
    """Regression: a `custom` dataset with a real path must produce a working
    torch.load(...) — not a placeholder with a live DataLoader(train_ds, ...)
    referencing a name that was only ever defined in a commented-out line."""
    from backend.app.routers.notebook import _dataset_loading_code

    code = _dataset_loading_code("custom", 32, "/tmp/regression_ds.pt")
    assert "torch.load('/tmp/regression_ds.pt'" in code
    assert "# train_ds = torch.load" not in code
    assert "DataLoader(train_ds" not in code


def test_dataset_loading_code_custom_without_path_never_nameerrors() -> None:
    """Regression: a `custom` dataset with no path configured anywhere must
    stay inert (every DataLoader(...) line commented, or an explicit raise) —
    never a live line referencing an undefined train_ds/test_ds."""
    from backend.app.routers.notebook import _dataset_loading_code

    code = _dataset_loading_code("custom", 32, "")
    for line in code.splitlines():
        stripped = line.strip()
        if "DataLoader(train_ds" in stripped or "DataLoader(test_ds" in stripped:
            assert stripped.startswith(
                "#"
            ), f"live DataLoader line with no dataset_path configured: {line!r}"
    assert "NotImplementedError" in code


def test_phase_loader_dataset_path_pt_node() -> None:
    """Regression: a phase's `format=pt` loader node's dataset_path must be
    recoverable on its own (not collapsed to the bare 'custom' sentinel)."""
    # type: ignore[attr-defined]
    # type: ignore[attr-defined]
    from backend.app.routers.notebook import (
        DagNodePayload,
        PhaseDAGPayload,
        _phase_loader_dataset_path,
    )

    phase = PhaseDAGPayload(
        nodes=[
            DagNodePayload(
                id="dl1",
                type="dataLoader",
                parameters={"format": "pt", "dataset_path": "/tmp/regression_ds.pt"},
            ),
        ],
        edges=[],
    )
    assert _phase_loader_dataset_path(phase) == "/tmp/regression_ds.pt"


def test_build_v2_notebook_pt_data_loader_dataset_cell_loads_real_path() -> None:
    """End-to-end regression for the reported bug: a Data Loader node with
    format=pt + dataset_path on the train phase must produce a top-level
    dataset-loading cell that actually loads that path, not the
    NameError-inducing './my_dataset' placeholder."""
    # type: ignore[attr-defined]
    from backend.app.routers.notebook import (
        DagNodePayload,
        PhaseDAGPayload,
        PipelineConfigPayload,
        PipelinePhasesPayload,
        _build_v2_notebook,
        compile_to_nir,
    )

    graph = compile_to_nir(VALID_SPEC)
    phases = PipelinePhasesPayload(
        train=PhaseDAGPayload(
            nodes=[
                DagNodePayload(
                    id="dl1",
                    type="dataLoader",
                    parameters={
                        "format": "pt",
                        "dataset_path": "/tmp/regression_ds.pt",
                    },
                ),
            ],
            edges=[],
        )
    )
    nb, _ = _build_v2_notebook(
        VALID_SPEC,
        graph,
        PipelineConfigPayload(),
        "2026-01-01 00:00 UTC",
        pipeline_phases=phases,
    )
    code_cells = [c for c in nb["cells"] if c["cell_type"] == "code"]
    dataset_cells = [c for c in code_cells if "DataLoader" in "".join(c["source"])]
    assert dataset_cells, "Expected at least one dataset loading cell"
    dataset_cell_source = "".join(dataset_cells[0]["source"])
    assert "torch.load('/tmp/regression_ds.pt'" in dataset_cell_source
    assert "./my_dataset" not in dataset_cell_source


def test_snntorch_notebook_preserves_imported_weight_values() -> None:
    """Imported NIR weights must survive into the generated notebook code.

    Regression: the NIR-to-CNL renderer intentionally drops real tensor
    values, keeping only shapes (see nir_cnl/renderer.py's
    `_emit_param_clauses`), so a bare `compile_to_nir(NIR_Renderer().render(g))`
    round trip can only ever rebuild placeholder weights — that's true by
    design, not a bug. The real fix lives in `_transplant_real_weights`,
    which `generate_notebook_v2` uses (keyed by `import_id`, see
    nir_import_store.py) to copy the real values from the original upload
    back onto the recompiled graph before codegen. Without this step, a
    generated notebook silently ships an untrained network (see the
    9.8%-vs-98%-accuracy bug this was reported as)."""
    weight = np.array([[0.125, -0.5], [1.25, -2.0]], dtype=np.float64)
    original_graph = nir.NIRGraph(
        nodes={
            "input": nir.Input(input_type={"input": np.array([2])}),
            "fc": nir.Linear(weight=weight),
            "output": nir.Output(output_type={"output": np.array([2])}),
        },
        edges=[("input", "fc"), ("fc", "output")],
    )
    imported_spec = NIR_Renderer().render(original_graph)

    from backend.app.routers.notebook import (  # type: ignore[attr-defined]
        _transplant_real_weights,
        _weights_artifact_name,
        compile_to_nir,
    )

    rebuilt_graph = compile_to_nir(imported_spec)
    # The CNL round trip alone loses the real value — by design, not a bug.
    assert not np.array_equal(rebuilt_graph.nodes["fc"].weight, weight)

    placeholder_nodes = _transplant_real_weights(rebuilt_graph, original_graph)
    assert placeholder_nodes == []
    assert np.array_equal(rebuilt_graph.nodes["fc"].weight, weight)

    nb, artifacts = _build_v2_notebook(
        imported_spec,
        rebuilt_graph,
        PipelineConfigPayload(framework="snntorch_sim"),
        "2026-01-01 00:00 UTC",
        pipeline_phases=PipelinePhasesPayload(),
        placeholder_weight_nodes=placeholder_nodes,
    )
    arch_src = _second_code_after_md(nb, "## Architecture")
    # weights are in a per-target/per-spec npz file, not embedded inline —
    # this filename is what regeneration-staleness protection hinges on.
    weights_filename = _weights_artifact_name(imported_spec, "snntorch_sim")
    assert f"np.load('{weights_filename}')" in arch_src
    assert "torch.from_numpy(_w['" in arch_src
    assert weights_filename in artifacts
    md_src = " ".join(
        "".join(c["source"]) for c in nb["cells"] if c["cell_type"] == "markdown"
    )
    assert "Untrained weights" not in md_src
    w_npz = np.load(_io.BytesIO(artifacts[weights_filename]))
    assert np.allclose(w_npz["fc_weight"], [[0.125, -0.5], [1.25, -2.0]])


def test_snntorch_imported_cnn_spec_recompiles_flatten_shape() -> None:
    """Regression for imported Notebook 2 CNN graphs.

    NIR_Renderer emits Flatten's start/end dimensions but not the upstream
    input_type object required by newer nir.Flatten constructors. The notebook
    endpoint recompiles that rendered CNL before transplanting real weights, so
    compile_to_nir must infer the Flatten input shape from graph topology.
    """
    conv_weight = np.full((2, 1, 3, 3), 0.5, dtype=np.float32)
    linear_weight = np.arange(320, dtype=np.float32).reshape(10, 32) / 100.0
    original_graph = nir.NIRGraph(
        nodes={
            "input": nir.Input(input_type={"input": np.array([1, 8, 8])}),
            "conv": nir.Conv2d(
                input_shape=(8, 8),
                weight=conv_weight,
                stride=np.array([1, 1]),
                padding=np.array([1, 1]),
                dilation=np.array([1, 1]),
                groups=1,
                bias=np.array([0.0, 0.0], dtype=np.float32),
            ),
            "lif0": nir.LIF(
                tau=np.full(2, 0.02),
                r=np.ones(2),
                v_leak=np.zeros(2),
                v_threshold=np.ones(2),
            ),
            "pool": nir.AvgPool2d(
                kernel_size=np.array([2, 2]),
                stride=np.array([2, 2]),
                padding=np.array([0, 0]),
            ),
            "flat": nir.Flatten(
                input_type={"input": np.array([2, 4, 4])},
                start_dim=0,
                end_dim=-1,
            ),
            "fc": nir.Linear(weight=linear_weight),
            "output": nir.Output(output_type={"output": np.array([10])}),
        },
        edges=[
            ("input", "conv"),
            ("conv", "lif0"),
            ("lif0", "pool"),
            ("pool", "flat"),
            ("flat", "fc"),
            ("fc", "output"),
        ],
        type_check=False,
    )
    imported_spec = NIR_Renderer().render(original_graph)

    from backend.app.routers.notebook import compile_to_nir

    rebuilt_graph = compile_to_nir(imported_spec)
    assert list(np.asarray(rebuilt_graph.nodes["flat"].input_type["input"])) == [
        2,
        4,
        4,
    ]

    nb, _ = _build_v2_notebook(
        imported_spec,
        rebuilt_graph,
        PipelineConfigPayload(framework="snntorch_sim"),
        "2026-01-01 00:00 UTC",
        pipeline_phases=PipelinePhasesPayload(),
    )
    arch_src = _second_code_after_md(nb, "## Architecture")
    assert "self.flat = nn.Flatten(start_dim=1, end_dim=-1)" in arch_src
    # A bias-less nir.Linear is constructed with PyTorch's default bias=True
    # and has its bias discarded immediately after, so the weight tensor draws
    # from the same RNG position as the construct-then-discard reference
    # implementation — see _generate_snntorch_code's Linear/Affine branch.
    assert "self.fc = nn.Linear(32, 10)" in arch_src
    assert "self.fc.bias = None" in arch_src


def test_transplant_real_weights_flags_shape_mismatch_as_placeholder() -> None:
    """A node whose shape changed since import must NOT get the old weights,
    and must be reported back so the notebook can warn about it honestly."""
    from backend.app.routers.notebook import _transplant_real_weights

    original_graph = nir.NIRGraph(
        nodes={
            "input": nir.Input(input_type={"input": np.array([2])}),
            "fc": nir.Linear(weight=np.array([[0.125, -0.5], [1.25, -2.0]])),
            "output": nir.Output(output_type={"output": np.array([2])}),
        },
        edges=[("input", "fc"), ("fc", "output")],
    )
    # User widened "fc" after importing — shape no longer matches the original.
    edited_graph = nir.NIRGraph(
        nodes={
            "input": nir.Input(input_type={"input": np.array([3])}),
            "fc": nir.Linear(weight=np.zeros((2, 3))),
            "output": nir.Output(output_type={"output": np.array([2])}),
        },
        edges=[("input", "fc"), ("fc", "output")],
    )
    placeholder_nodes = _transplant_real_weights(edited_graph, original_graph)
    assert placeholder_nodes == ["fc"]
    assert np.array_equal(edited_graph.nodes["fc"].weight, np.zeros((2, 3)))

    nb, _ = _build_v2_notebook(
        "placeholder spec",
        edited_graph,
        PipelineConfigPayload(framework="snntorch_sim"),
        "2026-01-01 00:00 UTC",
        pipeline_phases=PipelinePhasesPayload(),
        placeholder_weight_nodes=placeholder_nodes,
    )
    md_src = " ".join(
        "".join(c["source"]) for c in nb["cells"] if c["cell_type"] == "markdown"
    )
    assert "Untrained weights" in md_src
    assert "`fc`" in md_src


def test_weighted_layer_warning_order_follows_graph_topology() -> None:
    """Warnings should list trainable layers in model order, not raw dict order."""
    from backend.app.routers.notebook import (
        _transplant_real_weights,  # type: ignore[attr-defined]
    )
    from backend.app.services.notebook_graph_analysis import (
        graph_weighted_node_names as _graph_weighted_node_names,
    )

    graph = nir.NIRGraph(
        nodes={
            "10": nir.Linear(weight=np.zeros((2, 2))),
            "input": nir.Input(input_type={"input": np.array([2])}),
            "2": nir.Conv2d(
                input_shape=(4, 4),
                weight=np.zeros((1, 1, 3, 3)),
                stride=np.array([1, 1]),
                padding=np.array([1, 1]),
                dilation=np.array([1, 1]),
                groups=1,
                bias=np.array([0.0]),
            ),
            "1": nir.Linear(weight=np.zeros((16, 2))),
            "output": nir.Output(output_type={"output": np.array([2])}),
        },
        edges=[("input", "1"), ("1", "2"), ("2", "10"), ("10", "output")],
        type_check=False,
    )
    original_graph = nir.NIRGraph(
        nodes={
            "input": graph.nodes["input"],
            "1": nir.Linear(weight=np.zeros((15, 2))),
            "2": nir.Conv2d(
                input_shape=(4, 4),
                weight=np.zeros((1, 1, 1, 1)),
                stride=np.array([1, 1]),
                padding=np.array([0, 0]),
                dilation=np.array([1, 1]),
                groups=1,
                bias=np.array([0.0]),
            ),
            "10": nir.Linear(weight=np.zeros((1, 2))),
            "output": graph.nodes["output"],
        },
        edges=graph.edges,
        type_check=False,
    )

    assert _graph_weighted_node_names(graph) == ["1", "2", "10"]
    assert _transplant_real_weights(graph, original_graph) == ["1", "2", "10"]


def test_generate_v2_import_id_recovers_real_weights_end_to_end(tmp_path: Path) -> None:
    """Full flow: import a real .nir file, then generate a notebook from its
    (shapes-only) CNL text passing import_id back — the shipped weights.npz
    must contain the real values, not compile_to_nir's placeholders."""
    from backend.app.routers.notebook import _weights_artifact_name

    weight = np.array([[0.25, -0.75], [1.5, -3.0]], dtype=np.float64)
    original_graph = nir.NIRGraph(
        nodes={
            "input": nir.Input(input_type={"input": np.array([2])}),
            "fc": nir.Linear(weight=weight),
            "output": nir.Output(output_type={"output": np.array([2])}),
        },
        edges=[("input", "fc"), ("fc", "output")],
    )
    buf = _io.BytesIO()
    nir.write(buf, original_graph)
    imported_spec = NIR_Renderer().render(original_graph)

    with (
        patch("backend.app.routers.notebook.NOTEBOOK_DIR", tmp_path),
        patch(
            "backend.app.services.nir_import_store.NIR_IMPORT_DIR",
            tmp_path / "nir_imports",
        ),
    ):
        import_resp = client.post(
            "/api/neurosim/nir/import",
            json={"content_b64": base64.b64encode(buf.getvalue()).decode("utf-8")},
        )
        assert import_resp.status_code == 200, import_resp.text
        import_id = import_resp.json()["import_id"]
        assert import_id

        gen_resp = client.post(
            "/api/notebook/generate-v2",
            json={
                "spec": imported_spec,
                "pipeline_config": {"framework": "snntorch_sim"},
                "import_id": import_id,
            },
        )
        assert gen_resp.status_code == 200, gen_resp.text
        data = gen_resp.json()
        workspace_folder = data["workspace_folder"]

        weights_filename = _weights_artifact_name(imported_spec, "snntorch_sim")
        artifact_path = tmp_path / workspace_folder / weights_filename
        assert artifact_path.is_file(), f"expected weights artifact at {artifact_path}"
        w_npz = np.load(artifact_path)
        assert np.allclose(w_npz["fc_weight"], weight)


def test_generate_v2_cnn_without_import_id_blocks_placeholder_eval(
    tmp_path: Path,
) -> None:
    """Notebook 2 regression: shape-only CNL rebuilt from cnn_sinabs.nir
    must not silently evaluate placeholder weights and print chance accuracy.
    """
    import json as _json

    original_graph = nir.read(str(CNN_SINABS_NIR))
    imported_spec = NIR_Renderer().render(original_graph)
    phases = {
        "eval": {
            "nodes": [
                {
                    "id": "loader",
                    "type": "dataLoader",
                    "parameters": {
                        "format": "tonic_nmnist",
                        "batch_size": 128,
                        "time_window_ms": 1,
                    },
                },
                {"id": "forward", "type": "forwardPass", "parameters": {}},
                {"id": "accuracy", "type": "accuracyMetric", "parameters": {}},
            ],
            "edges": [],
        }
    }

    with patch("backend.app.routers.notebook.NOTEBOOK_DIR", tmp_path):
        resp = client.post(
            "/api/notebook/generate-v2",
            json={
                "spec": imported_spec,
                "pipeline_config": {
                    "framework": "snntorch_sim",
                    "dataset": "tonic_nmnist",
                },
                "pipeline_phases": phases,
            },
        )

    assert resp.status_code == 200, resp.text
    workspace_folder = resp.json()["workspace_folder"]
    notebook_path = (
        tmp_path / workspace_folder / resp.json()["notebooks"][0]["filename"]
    )
    nb = _json.loads(notebook_path.read_text())
    md_src = " ".join(
        "".join(c["source"]) for c in nb["cells"] if c["cell_type"] == "markdown"
    )
    code_src = "\n".join(
        "".join(c["source"]) for c in nb["cells"] if c["cell_type"] == "code"
    )

    assert "Untrained weights" in md_src
    assert "placeholder weights" in code_src
    assert "Accuracy (top-1)" not in code_src


def test_generate_v2_no_import_but_real_train_loop_does_not_block_eval(
    tmp_path: Path,
) -> None:
    """Regression: a from-scratch canvas network (no import_id) with a real
    optimiser-driven Train phase must NOT be treated like an expired/missing
    NIR import — the Train phase will genuinely train the weights via
    backprop before Eval ever runs, so the placeholder-weight warning and
    the Eval `raise RuntimeError` guard must not fire."""
    import json as _json

    phases = {
        "train": {
            "nodes": [
                {
                    "id": "loader",
                    "type": "dataLoader",
                    "parameters": {"batch_size": 32},
                },
                {"id": "forward", "type": "forwardPass", "parameters": {}},
                {"id": "loss", "type": "mseCountLoss", "parameters": {}},
                {"id": "backward", "type": "surrogateBackward", "parameters": {}},
                {
                    "id": "opt",
                    "type": "adamOptimiser",
                    "parameters": {"lr": 1e-3},
                },
            ],
            "edges": [],
        },
        "eval": {
            "nodes": [
                {"id": "eloader", "type": "dataLoader", "parameters": {}},
                {"id": "eforward", "type": "forwardPass", "parameters": {}},
                {"id": "eaccuracy", "type": "accuracyMetric", "parameters": {}},
            ],
            "edges": [],
        },
    }

    with patch("backend.app.routers.notebook.NOTEBOOK_DIR", tmp_path):
        resp = client.post(
            "/api/notebook/generate-v2",
            json={
                "spec": VALID_SPEC,
                "pipeline_config": {"framework": "snntorch_sim"},
                "pipeline_phases": phases,
            },
        )

    assert resp.status_code == 200, resp.text
    workspace_folder = resp.json()["workspace_folder"]
    notebook_path = (
        tmp_path / workspace_folder / resp.json()["notebooks"][0]["filename"]
    )
    nb = _json.loads(notebook_path.read_text())
    md_src = " ".join(
        "".join(c["source"]) for c in nb["cells"] if c["cell_type"] == "markdown"
    )
    code_src = "\n".join(
        "".join(c["source"]) for c in nb["cells"] if c["cell_type"] == "code"
    )

    assert "Untrained weights" not in md_src
    assert "placeholder weights" not in code_src


def test_generate_v2_cnn_import_id_recovers_all_real_weights(tmp_path: Path) -> None:
    """The actual Notebook 2 NIR import path must transplant every Conv/Affine
    tensor from cnn_sinabs.nir into the generated weights artifact.
    """
    import json as _json

    from backend.app.routers.notebook import (
        _weights_artifact_name,  # type: ignore[attr-defined]
    )
    from backend.app.services.notebook_graph_analysis import (
        python_identifier as _python_identifier,
    )

    original_graph = nir.read(str(CNN_SINABS_NIR))
    buf = _io.BytesIO()
    nir.write(buf, original_graph)
    imported_spec = NIR_Renderer().render(original_graph)

    with (
        patch("backend.app.routers.notebook.NOTEBOOK_DIR", tmp_path),
        patch(
            "backend.app.services.nir_import_store.NIR_IMPORT_DIR",
            tmp_path / "nir_imports",
        ),
    ):
        import_resp = client.post(
            "/api/neurosim/nir/import",
            json={"content_b64": base64.b64encode(buf.getvalue()).decode("utf-8")},
        )
        assert import_resp.status_code == 200, import_resp.text

        gen_resp = client.post(
            "/api/notebook/generate-v2",
            json={
                "spec": imported_spec,
                "pipeline_config": {
                    "framework": "snntorch_sim",
                    "dataset": "tonic_nmnist",
                },
                "import_id": import_resp.json()["import_id"],
            },
        )

    assert gen_resp.status_code == 200, gen_resp.text
    workspace_folder = gen_resp.json()["workspace_folder"]
    notebook_path = (
        tmp_path / workspace_folder / gen_resp.json()["notebooks"][0]["filename"]
    )
    nb = _json.loads(notebook_path.read_text())
    md_src = " ".join(
        "".join(c["source"]) for c in nb["cells"] if c["cell_type"] == "markdown"
    )
    assert "Untrained weights" not in md_src

    weights_filename = _weights_artifact_name(imported_spec, "snntorch_sim")
    w_npz = np.load(tmp_path / workspace_folder / weights_filename)

    for name, node in original_graph.nodes.items():
        if not isinstance(node, nir.Linear | nir.Affine | nir.Conv2d):
            continue
        key_prefix = _python_identifier(name)
        assert np.allclose(w_npz[f"{key_prefix}_weight"], np.asarray(node.weight))
        if getattr(node, "bias", None) is not None:
            assert np.allclose(w_npz[f"{key_prefix}_bias"], np.asarray(node.bias))


def test_generate_v2_tonic_dag_loader_controls_notebook_provenance(
    tmp_path: Path,
) -> None:
    """When the workspace dataset and DAG loader disagree, the executable
    Data Loader node is the provenance that matters for deps/config.
    """
    import json as _json

    phases = {
        "eval": {
            "nodes": [
                {
                    "id": "loader",
                    "type": "dataLoader",
                    "parameters": {
                        "format": "tonic_nmnist",
                        "batch_size": 128,
                        "time_window_ms": 1,
                    },
                },
                {"id": "forward", "type": "forwardPass", "parameters": {}},
                {"id": "accuracy", "type": "accuracyMetric", "parameters": {}},
            ],
            "edges": [],
        }
    }

    with patch("backend.app.routers.notebook.NOTEBOOK_DIR", tmp_path):
        resp = client.post(
            "/api/notebook/generate-v2",
            json={
                "spec": VALID_SPEC,
                "pipeline_config": {
                    "framework": "snntorch_sim",
                    "dataset": "davis-24-4a3449acc92a",
                },
                "pipeline_phases": phases,
            },
        )

    assert resp.status_code == 200, resp.text
    workspace_folder = resp.json()["workspace_folder"]
    notebook_path = (
        tmp_path / workspace_folder / resp.json()["notebooks"][0]["filename"]
    )
    nb = _json.loads(notebook_path.read_text())
    first_cell = "".join(nb["cells"][0]["source"])
    config_src = "".join(
        "".join(c["source"])
        for c in nb["cells"]
        if c["cell_type"] == "code" and "config = {" in "".join(c["source"])
    )
    code_src = "\n".join(
        "".join(c["source"]) for c in nb["cells"] if c["cell_type"] == "code"
    )

    assert '"tonic"' in first_cell
    assert '"dataset":   "tonic_nmnist"' in config_src
    assert "davis-24-4a3449acc92a" not in config_src
    assert "tonic.datasets.NMNIST" in code_src


def test_snntorch_notebook_supports_imported_mixed_nir_graph() -> None:
    """The snnTorch notebook scaffold should show all imported node types it handles."""
    conv_weight = np.full((2, 1, 3, 3), 0.5, dtype=np.float32)
    affine_weight = np.arange(320, dtype=np.float32).reshape(10, 32) / 100.0
    mixed_graph = nir.NIRGraph(
        nodes={
            "0": nir.Input(input_type={"input": np.array([1, 8, 8])}),
            "1": nir.Conv2d(
                input_shape=(8, 8),
                weight=conv_weight,
                stride=np.array([1, 1]),
                padding=np.array([1, 1]),
                dilation=np.array([1, 1]),
                groups=1,
                bias=np.array([0.1, -0.2], dtype=np.float32),
            ),
            "2": nir.AvgPool2d(
                kernel_size=np.array([2, 2]),
                stride=np.array([2, 2]),
                padding=np.array([0, 0]),
            ),
            "3": nir.Flatten(
                input_type={"input": np.array([2, 4, 4])},
                start_dim=1,
                end_dim=-1,
            ),
            "9": nir.Affine(
                weight=affine_weight,
                bias=np.linspace(-0.5, 0.4, 10, dtype=np.float32),
            ),
            "12": nir.Delay(delay=np.array([0.005], dtype=np.float32)),
            "11": nir.IF(
                r=np.ones(10, dtype=np.float32),
                v_threshold=np.ones(10, dtype=np.float32),
            ),
            "13": nir.Output(output_type={"output": np.array([10])}),
        },
        edges=[
            ("0", "1"),
            ("1", "2"),
            ("2", "3"),
            ("3", "9"),
            ("9", "12"),
            ("12", "11"),
            ("11", "13"),
        ],
        type_check=False,
    )
    imported_spec = NIR_Renderer().render(mixed_graph)
    nb, artifacts = _build_v2_notebook(
        imported_spec,
        mixed_graph,
        PipelineConfigPayload(framework="snntorch_sim"),
        "2026-01-01 00:00 UTC",
        pipeline_phases=PipelinePhasesPayload(),
    )

    from backend.app.routers.notebook import _weights_artifact_name

    arch_src = _second_code_after_md(nb, "## Architecture")
    # bias is left implicit (PyTorch's default bias=True) so the weight tensor
    # draws from the same RNG position as the construct-then-discard reference
    # implementation — see _generate_snntorch_code's Conv2d branch.
    assert (
        "self.n_1 = nn.Conv2d(1, 2, (3, 3), stride=(1, 1), padding=(1, 1))" in arch_src
    )
    assert (
        "self.n_1.weight.data = torch.from_numpy(_w['n_1_weight'].copy())" in arch_src
    )
    assert "self.n_2 = nn.AvgPool2d(kernel_size=(2, 2), stride=(2, 2))" in arch_src
    assert "self.n_3 = nn.Flatten(start_dim=1, end_dim=-1)" in arch_src
    assert "self.n_9 = nn.Linear(32, 10)" in arch_src  # bias=True is the default
    assert (
        "self.n_9.weight.data = torch.from_numpy(_w['n_9_weight'].copy())" in arch_src
    )
    assert "self.n_9.bias.data = torch.from_numpy(_w['n_9_bias'].copy())" in arch_src
    assert "# Delay node: '12'" in arch_src
    assert (
        "self.n_11 = snn.Leaky(beta=0.900000, threshold=1.0000, "
        "init_hidden=True, reset_delay=False)" in arch_src
    )
    assert _weights_artifact_name(imported_spec, "snntorch_sim") in artifacts


def test_snntorch_notebook_sumpool2d_uses_true_sum() -> None:
    """Regression: nir.SumPool2d must become AvgPool2d(divisor_override=1) —
    a plain AvgPool2d divides by the kernel area, making SumPool2d output
    kernel_area-times too small (see gen_snn.ipynb 9.8%-accuracy bug)."""
    sumpool_graph = nir.NIRGraph(
        nodes={
            "input": nir.Input(input_type={"input": np.array([1, 4, 4])}),
            "0": nir.SumPool2d(
                kernel_size=np.array([2, 2]),
                stride=np.array([2, 2]),
                padding=np.array([0, 0]),
            ),
            "output": nir.Output(output_type={"output": np.array([1, 2, 2])}),
        },
        edges=[("input", "0"), ("0", "output")],
        type_check=False,
    )
    imported_spec = NIR_Renderer().render(sumpool_graph)
    nb, _ = _build_v2_notebook(
        imported_spec,
        sumpool_graph,
        PipelineConfigPayload(framework="snntorch_sim"),
        "2026-01-01 00:00 UTC",
        pipeline_phases=PipelinePhasesPayload(),
    )
    arch_src = _second_code_after_md(nb, "## Architecture")
    assert (
        "self.n_0 = nn.AvgPool2d(kernel_size=(2, 2), stride=(2, 2), divisor_override=1)"
        in arch_src
    )


def test_tonic_dataloader_emits_pad_tensors() -> None:
    """Regression: tonic DataLoaders must use PadTensors to handle variable-length
    event frames (NMNIST recordings have different durations → different # of
    1 ms frame bins).  Without it default_collate raises RuntimeError at eval time.
    """
    from backend.app.routers.notebook import (
        DagNodePayload,
        PipelineConfigPayload,
        _dag_node_code,
    )

    node = DagNodePayload(
        id="n1",
        type="dataLoader",
        parameters={"format": "tonic_nmnist", "batch_size": 128, "time_window_ms": 1},
    )
    cfg = PipelineConfigPayload(framework="snntorch_sim", dataset="tonic_nmnist")
    src = _dag_node_code(node, cfg, "tonic_nmnist")

    assert "PadTensors" in src, "tonic DataLoader must use PadTensors as collate_fn"
    assert (
        "batch_first=False" in src
    ), "PadTensors must be batch_first=False (time-first)"
    assert (
        "collate_fn=_pad_collate" in src
    ), "DataLoader must pass _pad_collate as collate_fn"


def test_notebook_export_cell_does_not_use_file_magic() -> None:
    from backend.app.routers.notebook import compile_to_nir

    graph = compile_to_nir(VALID_SPEC)
    nb, _ = _build_v2_notebook(
        VALID_SPEC,
        graph,
        PipelineConfigPayload(framework="snntorch_sim", generate_py_download=True),
        "2026-01-01 00:00 UTC",
        pipeline_phases=PipelinePhasesPayload(),
    )
    export_src = "\n".join(
        "".join(cell["source"])
        for cell in nb["cells"]
        if cell["cell_type"] == "code" and "nbconvert" in "".join(cell["source"])
    )
    assert "Path.cwd().glob('*.ipynb')" in export_src
    assert "__file__" not in export_src
    compile(export_src, "<notebook-export-cell>", "exec")


def test_exact_graph_has_no_support_warning_cell(default_nb) -> None:
    """snntorch_sim + a plain Linear/LIF graph classifies as exact — no
    backend-support warning. Scoped to the support-classification banner's
    own heading text (not a blanket "no ⚠️ anywhere") since VALID_SPEC's
    undeclared-timestep LIF neuron is a separate, legitimate case for the
    unrelated "possibly unreachable firing threshold" guardrail cell added
    alongside the network-timestep grammar fix — see
    test_notebook_codegen_network_timestep.py's own dedicated coverage for
    that cell's presence/absence."""
    md_src = " ".join(
        "".join(c["source"])
        for c in default_nb["cells"]
        if c["cell_type"] == "markdown"
    )
    assert "support for `snntorch_sim`" not in md_src


def test_generate_v2_response_carries_support_level(tmp_path: Path) -> None:
    """The endpoint response must expose the same classification used for the
    in-notebook warning cell, so the UI can eventually render a badge (Phase G).
    """
    with patch("backend.app.routers.notebook.NOTEBOOK_DIR", tmp_path):
        resp = client.post(
            "/api/notebook/generate-v2",
            json={"spec": VALID_SPEC, "pipeline_config": {"framework": "sinabs"}},
        )
    assert resp.status_code == 200
    entry = resp.json()["notebooks"][0]
    # VALID_SPEC is Linear+LIF: Linear=exact, LIF=approximate for sinabs.
    assert entry["support_level"] == "approximate"
    assert any("LIF" in d for d in entry["diagnostics"])


def test_generate_v2_unknown_framework_does_not_crash(tmp_path: Path) -> None:
    """A framework string outside the known deploy-target set (the generic
    'inspect the graph' scaffold arm) must not raise classify_nir_graph's
    ValueError — support_level stays None instead.
    """
    with patch("backend.app.routers.notebook.NOTEBOOK_DIR", tmp_path):
        resp = client.post(
            "/api/notebook/generate-v2",
            json={
                "spec": VALID_SPEC,
                "pipeline_config": {"framework": "totally_custom_target"},
            },
        )
    assert resp.status_code == 200
    assert resp.json()["notebooks"][0]["support_level"] is None


def test_cnl_flatten_gate_is_data_driven_not_hardcoded() -> None:
    """The flatten decision must come from get_supported_node_types(target),
    not a target-name check alone — if a hypothetical future backend marked
    cnl.Leaky 'exact', that specific type must stop triggering flatten while
    other still-unsupported cnl types in the same graph still do.
    """
    from backend.app.services.notebook_graph_analysis import graph_needs_cnl_flatten
    from neurocnl.runtime.cnl_nodes import Leaky, Synaptic

    graph = nir.NIRGraph(
        nodes={
            "input": nir.Input(input_type={"input": np.array([2])}),
            "leaky": Leaky(n_neurons=2),
            "syn": Synaptic(n_neurons=2),
            "output": nir.Output(output_type={"output": np.array([2])}),
        },
        edges=[("input", "leaky"), ("leaky", "syn"), ("syn", "output")],
        type_check=False,
    )
    assert graph_needs_cnl_flatten(graph, "rockpool") is True

    hypothetical_table = {"Leaky": "exact"}
    with patch(
        "backend.app.services.notebook_graph_analysis.get_supported_node_types",
        return_value=hypothetical_table,
    ):
        # Still True: Synaptic is not exact even though Leaky now is.
        assert graph_needs_cnl_flatten(graph, "rockpool") is True

    leaky_only_graph = nir.NIRGraph(
        nodes={
            "input": nir.Input(input_type={"input": np.array([2])}),
            "leaky": Leaky(n_neurons=2),
            "output": nir.Output(output_type={"output": np.array([2])}),
        },
        edges=[("input", "leaky"), ("leaky", "output")],
        type_check=False,
    )
    with patch(
        "backend.app.services.notebook_graph_analysis.get_supported_node_types",
        return_value=hypothetical_table,
    ):
        assert graph_needs_cnl_flatten(leaky_only_graph, "rockpool") is False


def test_cnl_flatten_scoped_to_gap_converter_targets_only() -> None:
    """lava/lava_sim/sc_neurocore_sim/sc_neurocore_fpga are deliberately
    excluded from flattening (flattening would turn a silent no-op on lava
    into a hard AttributeError crash on the pre-existing node.tau bug).
    """
    from backend.app.services.notebook_graph_analysis import graph_needs_cnl_flatten
    from neurocnl.runtime.cnl_nodes import RSynaptic

    graph = nir.NIRGraph(
        nodes={
            "input": nir.Input(input_type={"input": np.array([2])}),
            "rsyn": RSynaptic(n_neurons=2),
            "output": nir.Output(output_type={"output": np.array([2])}),
        },
        edges=[("input", "rsyn"), ("rsyn", "output")],
        type_check=False,
    )
    for target in ("lava", "lava_sim", "sc_neurocore_sim", "sc_neurocore_fpga"):
        assert graph_needs_cnl_flatten(graph, target) is False
    for target in ("brian2", "sinabs", "rockpool", "pynn", "nengo", "akida"):
        assert graph_needs_cnl_flatten(graph, target) is True


def test_braille_graph_rockpool_produces_real_code() -> None:
    nb = _build_nb_for_braille("rockpool")
    code = _code_sources(nb)
    assert "RockpoolIO" in code
    assert "raise ValueError" not in code
    md_src = " ".join(
        "".join(c["source"]) for c in nb["cells"] if c["cell_type"] == "markdown"
    )
    assert "⚠️" in md_src


def test_braille_graph_nengo_produces_real_code() -> None:
    nb = _build_nb_for_braille("nengo")
    code = _code_sources(nb)
    assert "NengoIO scaffold" not in code
    assert "nengo.Ensemble" in code
    assert "nengo.synapses.Lowpass" in code


@pytest.mark.parametrize("framework", ["brian2", "pynn", "sinabs"])
def test_braille_graph_no_crash_but_scaffold(framework: str) -> None:
    """brian2/pynn crash on flattened CubaLIF's missing `.tau` (pre-existing
    bug); sinabs crashes on CubaLIF not being in its _SUPPORTED tuple
    (pre-existing, separate bug). All three must degrade to the existing
    scaffold fallback WITHOUT raising out of _build_v2_notebook.
    """
    nb = _build_nb_for_braille(framework)  # must not raise
    assert nb["cells"]


def test_braille_graph_akida_does_not_crash() -> None:
    """Akida can't run spiking neurons at all — flattening doesn't fix that,
    it only ensures generation completes without an unhandled exception.
    """
    nb = _build_nb_for_braille("akida")  # must not raise
    code = _code_sources(nb)
    assert "nir_to_akida(graph" in code


def test_akida_platform_cell_uses_the_adapter_not_a_second_copy_of_it() -> None:
    """The akida target used to hand-roll layer construction and emitted
    `akl.InputLayer`, which the SDK does not define — so the cell raised
    `AttributeError` on every run. Banning the `akl.` namespace outright is what
    stops a second, drifting copy of the converter reappearing here; the one in
    `neurocnl/converter/akida_adapter.py` is the only one that gets fixed.
    """
    code = _code_sources(_build_nb_for_braille("akida"))
    assert "akl." not in code
    assert "from akida import layers" not in code
    assert "nir_to_akida(graph" in code
    # The weights it converts are the spec's, not trained ones — say so, since
    # `akida` has no training adapter and the cell looks like a deploy path.
    assert "NOT trained ones" in code


def test_generate_v2_response_support_level_matches_flattened_notebook_warning(
    tmp_path: Path,
) -> None:
    """Regression: the API response's support_level/diagnostics must reflect
    the SAME (post-flatten) classification as the notebook's own warning
    cell, not a separately-recomputed classification of the pre-flatten graph.
    """
    from neurocnl.runtime.cnl_nodes import RSynaptic

    graph = nir.NIRGraph(
        nodes={
            "input": nir.Input(input_type={"input": np.array([2])}),
            "rsyn": RSynaptic(n_neurons=2, alpha=0.9, beta=0.8),
            "output": nir.Output(output_type={"output": np.array([2])}),
        },
        edges=[("input", "rsyn"), ("rsyn", "output")],
        type_check=False,
    )
    from backend.app.services.notebook_graph_analysis import flatten_and_classify

    _, expected_classification, _ = flatten_and_classify(graph, "rockpool")

    nb, _ = _build_v2_notebook(
        "",
        graph,
        PipelineConfigPayload(framework="rockpool"),
        "2026-01-01 00:00 UTC",
        pipeline_phases=PipelinePhasesPayload(),
    )
    md_src = " ".join(
        "".join(c["source"]) for c in nb["cells"] if c["cell_type"] == "markdown"
    )
    assert expected_classification.level.upper() in md_src


def test_generate_v2_reports_snntorch_as_trainable(tmp_path: Path) -> None:
    body = _generate_v2("snntorch_sim", tmp_path)
    assert body["trainable"] is True
    assert body["not_trainable_reason"] == ""


def test_generate_v2_reports_akida_as_not_trainable_with_a_reason(
    tmp_path: Path,
) -> None:
    """The Run step skips execution on this flag.

    Without it, pressing Play ran a notebook with no optimiser cell and the
    failure read as the user's mistake — so the flag has to be present *and*
    carry text worth showing on the platform tab.
    """
    body = _generate_v2("akida", tmp_path)
    assert body["trainable"] is False
    reason = body["not_trainable_reason"]
    assert "akida" in reason
    assert "snnTorch" in reason


def test_not_trainable_reason_is_the_same_text_the_notebook_shows(
    tmp_path: Path,
) -> None:
    """One wording, two surfaces: the API field and the notebook's own markdown
    cell must not drift into contradicting each other."""
    body = _generate_v2("sinabs", tmp_path)
    notebook, _ = _build_v2_notebook(
        VALID_SPEC,
        __import__("neurocnl.compile", fromlist=["compile_to_nir"]).compile_to_nir(
            VALID_SPEC
        ),
        PipelineConfigPayload(framework="sinabs"),
        "2026-08-06 00:00 UTC",
        pipeline_phases=PipelinePhasesPayload(
            train=PhaseDAGPayload(
                nodes=[DagNodePayload(id="forward", type="forwardPass")]
            )
        ),
    )
    md_src = " ".join(
        "".join(c["source"]) for c in notebook["cells"] if c["cell_type"] == "markdown"
    )
    assert body["not_trainable_reason"] in md_src


@pytest.mark.parametrize(
    "framework,io_name",
    [("brian2", "Brian2IO"), ("pynn", "PyNNIO"), ("lava", "LavaIO")],
)
def test_unsupported_node_surfaces_error_cell(framework: str, io_name: str) -> None:
    """A genuinely-unhandled node type must still produce a notebook (not
    crash _build_v2_notebook) with a visible error cell quoting the real
    exception, not a silently-swallowed scaffold.
    """
    nb, _ = _build_v2_notebook(
        "",
        _unsupported_type_graph(),
        PipelineConfigPayload(framework=framework),
        "2026-01-01 00:00 UTC",
        pipeline_phases=PipelinePhasesPayload(),
    )
    md_src = " ".join(
        "".join(c["source"]) for c in nb["cells"] if c["cell_type"] == "markdown"
    )
    assert "⚠️" in md_src
    assert f"{io_name} conversion failed" in md_src
    assert "not supported" in md_src
    code = _code_sources(nb)
    assert code  # a scaffold code cell is still present


def test_safe_io_call_success_path_has_no_error_cell() -> None:
    """A fully-supported graph must not attach an io_error cell."""
    graph = nir.NIRGraph(
        nodes={
            "input": nir.Input(input_type={"input": np.array([2])}),
            "fc": nir.Linear(weight=np.eye(2)),
            "lif": nir.LIF(
                tau=np.full(2, 0.02),
                r=np.ones(2),
                v_leak=np.zeros(2),
                v_threshold=np.ones(2),
            ),
            "output": nir.Output(output_type={"output": np.array([2])}),
        },
        edges=[("input", "fc"), ("fc", "lif"), ("lif", "output")],
        type_check=False,
    )
    nb, _ = _build_v2_notebook(
        "",
        graph,
        PipelineConfigPayload(framework="brian2"),
        "2026-01-01 00:00 UTC",
        pipeline_phases=PipelinePhasesPayload(),
    )
    md_src = " ".join(
        "".join(c["source"]) for c in nb["cells"] if c["cell_type"] == "markdown"
    )
    assert "conversion failed" not in md_src


def test_akida_unsupported_node_returns_422(tmp_path: Path) -> None:
    """Akida stays unwrapped (not _safe_io_call) — a genuinely unhandled type
    surfaces as a 422 with the exception text in `detail`, not an in-notebook
    error cell like the other 5 hardened converters.
    """
    from neurocnl.nir_cnl.renderer import NIR_Renderer

    graph = nir.NIRGraph(
        nodes={
            "input": nir.Input(input_type={"input": np.array([2])}),
            "delay": nir.Delay(delay=np.ones(2)),
            "output": nir.Output(output_type={"output": np.array([2])}),
        },
        edges=[("input", "delay"), ("delay", "output")],
        type_check=False,
    )
    spec = NIR_Renderer().render(graph)
    with patch("backend.app.routers.notebook.NOTEBOOK_DIR", tmp_path):
        resp = client.post(
            "/api/notebook/generate-v2",
            json={"spec": spec, "pipeline_config": {"framework": "akida"}},
        )
    assert resp.status_code == 422
    detail = resp.json()["detail"]
    assert detail["code"] == "notebook_codegen_unsupported"
    assert "not supported in Akida" in detail["message"]


def test_akida_flatten_if_lif_cubalif_graph_still_succeeds() -> None:
    """Regression guard for the Option-B scoping decision: Flatten/IF/LIF/
    CubaLIF nodes must still degrade to a no-op (matching pre-existing
    behavior), not start raising -- otherwise nearly every real CNN/SNN
    Akida notebook would break.
    """
    graph = nir.NIRGraph(
        nodes={
            "input": nir.Input(input_type={"input": np.array([4])}),
            "fc": nir.Affine(weight=np.eye(4), bias=np.zeros(4)),
            "flat": nir.Flatten(
                input_type={"input": np.array([4])},
                start_dim=1,
                end_dim=-1,
            ),
            "lif": nir.LIF(
                tau=np.full(4, 0.02),
                r=np.ones(4),
                v_leak=np.zeros(4),
                v_threshold=np.ones(4),
            ),
            "output": nir.Output(output_type={"output": np.array([4])}),
        },
        edges=[("input", "fc"), ("fc", "flat"), ("flat", "lif"), ("lif", "output")],
        type_check=False,
    )
    nb, _ = _build_v2_notebook(
        "",
        graph,
        PipelineConfigPayload(framework="akida"),
        "2026-01-01 00:00 UTC",
        pipeline_phases=PipelinePhasesPayload(),
    )  # must not raise
    code = _code_sources(nb)
    assert "nir_to_akida(graph" in code
    # Flatten and the neuron node have to reach the cell without raising
    # `unsupported node`; the adapter decides how to map them at run time.
    assert "#   FullyConnected  'fc'  (4 units)" in code
    assert "#   neuron  'lif'  (4 units)" in code


def test_generate_v2_regenerating_workspace_does_not_corrupt_weights_artifacts(
    tmp_path: Path,
) -> None:
    """Regenerating a notebook in the same workspace with a materially
    different architecture must not let the second notebook's code load the
    first notebook's (structurally incompatible) weights file, and must not
    silently overwrite/corrupt the first notebook's weights file either.
    """
    import json as _json

    from backend.app.routers.notebook import _weights_artifact_name

    with patch("backend.app.routers.notebook.NOTEBOOK_DIR", tmp_path):
        resp1 = client.post(
            "/api/notebook/generate-v2",
            json={
                "spec": VALID_SPEC,
                "pipeline_config": {"framework": "snntorch_sim"},
                "workspace_path": "shared-workspace",
            },
        )
        resp2 = client.post(
            "/api/notebook/generate-v2",
            json={
                "spec": RESHAPED_SPEC,
                "pipeline_config": {"framework": "snntorch_sim"},
                "workspace_path": "shared-workspace",
            },
        )
    assert resp1.status_code == 200
    assert resp2.status_code == 200

    workspace_folder = resp1.json()["workspace_folder"]
    assert workspace_folder == resp2.json()["workspace_folder"]
    notebooks_dir = tmp_path / workspace_folder

    weights_filename_1 = _weights_artifact_name(VALID_SPEC, "snntorch_sim")
    weights_filename_2 = _weights_artifact_name(RESHAPED_SPEC, "snntorch_sim")
    assert weights_filename_1 != weights_filename_2

    # Both weight files coexist on disk — the second generation must not
    # have deleted or overwritten the first.
    npz_1 = np.load(notebooks_dir / weights_filename_1)
    npz_2 = np.load(notebooks_dir / weights_filename_2)
    assert "w_input_hidden_weight" in npz_1.files
    assert "w_solo_weight" in npz_2.files
    assert npz_2["w_solo_weight"].shape == (3, 5)

    # The regenerated (second) notebook — which overwrote the first .ipynb,
    # since both share the same target filename — must reference its OWN
    # weights file, never the stale one from the first generation.
    filename = resp2.json()["notebooks"][0]["filename"]
    nb_on_disk = _json.loads((notebooks_dir / filename).read_text())
    arch_src = "".join(
        "".join(c["source"])
        for c in nb_on_disk["cells"]
        if c["cell_type"] == "code" and "class Net" in "".join(c["source"])
    )
    assert f"np.load('{weights_filename_2}')" in arch_src
    assert weights_filename_1 not in arch_src


@pytest.mark.parametrize(
    ("raised", "expected_fragment"),
    [
        # Connect-phase failures: the service is not there.
        (
            httpx.ConnectError("refused"),
            "Make sure the jupyter-server service is running",
        ),
        (
            httpx.ConnectTimeout("no route"),
            "Make sure the jupyter-server service is running",
        ),
        # Exchange-phase: connected, then stalled. Different advice.
        (httpx.ReadTimeout("stalled"), "reachable but overloaded"),
    ],
)
def test_publish_distinguishes_unreachable_from_overloaded(
    raised: Exception, expected_fragment: str
) -> None:
    """_publish_via_contents_api must not tell you to go start a server that is
    already running. ReadTimeout/WriteTimeout/PoolTimeout subclass HTTPError, so
    if their handler is ever moved below the generic one it silently becomes dead
    code and every case regresses to the 'is it running?' message — which is the
    bug this parametrisation guards.
    """
    with (
        patch("backend.app.routers.notebook.JUPYTER_WORKER_URL", "http://jupyter:8008"),
        # httpx is imported inside the function body, so there is no
        # notebook.httpx attribute to patch — go at the source module.
        patch("httpx.Client") as mock_client,
    ):
        mock_client.return_value.__enter__.return_value.put.side_effect = raised
        with pytest.raises(HTTPException) as excinfo:
            _publish_via_contents_api("ws", [("nb.ipynb", {})], {})

    assert excinfo.value.status_code == 503
    assert expected_fragment in excinfo.value.detail


def test_akida_mnist_companion_contains_full_acceptance_chain() -> None:
    notebook = _build_akida_mnist_notebook("2026-08-04 00:00 UTC")
    code = _code_sources(notebook)

    assert "batch_size, epochs = 128, 10" in code
    assert "pytorch_accuracy >= 0.98" in code
    assert "abs(onnx_accuracy - pytorch_accuracy) <= 0.001" in code
    assert "schemaVersion': 1" in code
    assert "akida_mnist_v1.akida-bundle.zip" in code


def test_akida_mnist_template_and_latest_bundle_endpoints(tmp_path: Path) -> None:
    with (
        patch("backend.app.routers.notebook.NOTEBOOK_DIR", tmp_path),
        patch("backend.app.routers.notebook.JUPYTER_WORKER_URL", ""),
    ):
        generated = client.post(
            "/api/notebook/templates/akida-mnist",
            json={"workspace_path": "My Akida Demo"},
        )
        assert generated.status_code == 200
        workspace_folder = generated.json()["workspace_folder"]
        notebook = tmp_path / workspace_folder / "akida_mnist_companion.ipynb"
        assert notebook.is_file()
        bundle = notebook.parent / "akida_mnist_v1.akida-bundle.zip"
        bundle.write_bytes(b"PK-model-bundle")

        discovered = client.get(
            "/api/notebook/artifacts/latest-akida-bundle",
            params={"workspace_folder": workspace_folder},
        )

    assert discovered.status_code == 200
    assert discovered.json()["filename"] == bundle.name
    assert base64.b64decode(discovered.json()["bundle_base64"]) == b"PK-model-bundle"


def test_latest_akida_bundle_decodes_jupyters_line_wrapped_base64() -> None:
    """Regression: this returned HTTP 500 for every real bundle.

    `base64.b64decode(content, validate=True)` rejects any character outside the
    base64 alphabet, and Jupyter's `content` is wrapped at 76 columns, so the
    newlines alone raised `binascii.Error: Only base64 data is allowed`.
    """
    payload = b"PK\x03\x04" + bytes(range(256)) * 8
    fake = _FakeJupyterContents(payload)
    with (
        patch("backend.app.routers.notebook.JUPYTER_WORKER_URL", "http://jupyter:8008"),
        patch("httpx.Client", fake),
    ):
        response = client.get(
            "/api/notebook/artifacts/latest-akida-bundle",
            params={"workspace_folder": "My Workspace"},
        )

    assert response.status_code == 200, response.text
    assert base64.b64decode(response.json()["bundle_base64"]) == payload


def test_latest_akida_bundle_reports_corrupt_base64_instead_of_a_500() -> None:
    """A payload that is genuinely not base64 must still be a named 404."""

    class _Corrupt(_FakeJupyterContents):
        def get(self, url: str):
            body: dict[str, Any] = (
                {"format": "base64", "content": "!!! not base64 !!!"}
                if url.endswith(self._filename)
                else {
                    "content": [
                        {
                            "name": self._filename,
                            "last_modified": "2026-08-06T10:00:00Z",
                        }
                    ]
                }
            )
            return type(
                "_Response", (), {"status_code": 200, "json": lambda _self: body}
            )()

    with (
        patch("backend.app.routers.notebook.JUPYTER_WORKER_URL", "http://jupyter:8008"),
        patch("httpx.Client", _Corrupt(b"")),
    ):
        response = client.get(
            "/api/notebook/artifacts/latest-akida-bundle",
            params={"workspace_folder": "My Workspace"},
        )

    assert response.status_code == 404
    assert "not valid base64" in response.json()["detail"]


def test_latest_akida_bundle_reports_actionable_missing_artifact(
    tmp_path: Path,
) -> None:
    with (
        patch("backend.app.routers.notebook.NOTEBOOK_DIR", tmp_path),
        patch("backend.app.routers.notebook.JUPYTER_WORKER_URL", ""),
    ):
        response = client.get(
            "/api/notebook/artifacts/latest-akida-bundle",
            params={"workspace_folder": "missing/notebooks"},
        )

    assert response.status_code == 404
    # Two things write a bundle now; naming only one sends a canvas user to the
    # wrong place.
    detail = response.json()["detail"]
    assert "companion notebook" in detail
    assert "Akida Exporter" in detail


def test_generate_v2_rejects_dataset_wider_than_input_port(tmp_path: Path) -> None:
    """The reported bug: a 784-feature dataset on a 32-wide network is refused."""
    dataset = tmp_path / "mnist_train.pt"
    dataset.write_bytes(b"not really a tensor")

    with (
        patch("backend.app.routers.notebook.NOTEBOOK_DIR", tmp_path),
        patch(
            "backend.app.services.notebook_graph_analysis.pt_feature_width",
            return_value=784,
        ),
    ):
        resp = _generate_with_pt_loader(SMALL_LIF_FIRST_SPEC, dataset, tmp_path)

    assert resp.status_code == 422, resp.text
    detail = resp.json()["detail"]
    # Both numbers and both sources must be named — that is the whole point.
    assert "784" in detail
    assert "32" in detail
    assert "mnist_train.pt" in detail
    assert "Input node" in detail


def test_generate_v2_accepts_dataset_matching_input_port(tmp_path: Path) -> None:
    """A dataset whose width matches the declared Input generates normally."""
    dataset = tmp_path / "small_train.pt"
    dataset.write_bytes(b"not really a tensor")

    with (
        patch("backend.app.routers.notebook.NOTEBOOK_DIR", tmp_path),
        patch(
            "backend.app.services.notebook_graph_analysis.pt_feature_width",
            return_value=32,
        ),
    ):
        resp = _generate_with_pt_loader(SMALL_LIF_FIRST_SPEC, dataset, tmp_path)

    assert resp.status_code == 200, resp.text


def test_generate_v2_skips_check_when_dataset_width_unknown(tmp_path: Path) -> None:
    """An unreadable dataset must never block generation.

    A guard that cannot see the data has nothing to say about it — turning a
    failed probe into a refusal would break every tonic/npy/client-scope run.
    """
    dataset = tmp_path / "mystery.pt"
    dataset.write_bytes(b"not really a tensor")

    with (
        patch("backend.app.routers.notebook.NOTEBOOK_DIR", tmp_path),
        patch(
            "backend.app.services.notebook_graph_analysis.pt_feature_width",
            return_value=None,
        ),
    ):
        resp = _generate_with_pt_loader(SMALL_LIF_FIRST_SPEC, dataset, tmp_path)

    assert resp.status_code == 200, resp.text


def test_generate_v2_skips_check_when_dataset_file_is_absent(tmp_path: Path) -> None:
    """A dataset_path the backend cannot see (client-scope path) is not a mismatch."""
    with patch("backend.app.routers.notebook.NOTEBOOK_DIR", tmp_path):
        resp = _generate_with_pt_loader(
            SMALL_LIF_FIRST_SPEC,
            Path("/Desktop/mnist_train.pt"),
            tmp_path,
        )

    assert resp.status_code == 200, resp.text


def test_snntorch_forward_asserts_input_width(tmp_path: Path) -> None:
    """The generated forward() carries a runtime backstop naming the Input port.

    Covers the cases the static check must skip: tonic datasets, client-scope
    paths, unreadable files. Without it the only symptom is a torch matmul error.
    """
    from backend.app.routers.notebook import _generate_snntorch_code
    from neurocnl.compile import compile_to_nir

    code, _ = _generate_snntorch_code(compile_to_nir(SMALL_LIF_FIRST_SPEC))
    assert "_input_feature_width != 32" in code
    assert "features per sample" in code
    assert "'input' declares 32" in code
    compile(code, "<generated>", "exec")  # emitted code must be valid Python
