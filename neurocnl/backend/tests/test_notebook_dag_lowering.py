"""Tests for ``backend.app.services.notebook_dag_lowering`` (phase-DAG
lowering: ``_phase_dag_to_code`` / ``_training_phase_to_code`` and the
val/eval loader wiring), which are re-exported from
``backend.app.routers.notebook``.
"""

from __future__ import annotations

import os
from pathlib import Path
from unittest.mock import patch

import pytest

from backend.app.routers.notebook import (
    DagNodePayload,
    PhaseDAGPayload,
    PipelineConfigPayload,
    PipelinePhasesPayload,
    _build_v2_notebook,
)
from backend.tests.notebook_test_fixtures import (
    VALID_SPEC,
    _braille_training_phase,
    client,
)


def _val_loop_train_phase(
    *,
    shared_loader: bool,
    val_node_type: str = "dataLoader",
    val_format: str = "pt",
):
    """Train phase with a validationLoop, wired two ways.

    `shared_loader=False` is the two-Data-Loader layout the MNIST/Braille
    guides prescribe: a train file feeding forwardPass and a *separate* val
    file wired only to validationLoop.val_data.
    `shared_loader=True` is one loader with two output wires.

    `val_node_type`/`val_format` let a caller wire a `testLoader`-typed node
    (the Braille workspace's actual layout) or a non-`'pt'` `dataLoader` into
    val_data instead of the default `dataLoader`+`'pt'` combo.
    """
    from backend.app.routers.notebook import (
        DagEdgePayload,
        DagNodePayload,
        PhaseDAGPayload,
    )

    nodes = [
        DagNodePayload(
            id="train_dl",
            type="dataLoader",
            parameters={
                "format": "pt",
                "dataset_path": "train.pt",
                "batch_size": 128,
                "shuffle": True,
            },
        ),
        DagNodePayload(id="fwd", type="forwardPass", parameters={}),
        DagNodePayload(id="loss", type="ceCountLoss", parameters={}),
        DagNodePayload(id="bwd", type="surrogateBackward", parameters={}),
        DagNodePayload(id="opt", type="adamOptimiser", parameters={"lr": 0.0005}),
        DagNodePayload(id="vloop", type="validationLoop", parameters={}),
    ]
    edges = [
        DagEdgePayload(
            id="e1",
            source_node_id="train_dl",
            source_port="data",
            target_node_id="fwd",
            target_port="input",
        ),
        DagEdgePayload(
            id="e2",
            source_node_id="fwd",
            source_port="spikes",
            target_node_id="loss",
            target_port="spikes",
        ),
        DagEdgePayload(
            id="e3",
            source_node_id="loss",
            source_port="loss",
            target_node_id="bwd",
            target_port="loss",
        ),
        DagEdgePayload(
            id="e4",
            source_node_id="bwd",
            source_port="gradients",
            target_node_id="opt",
            target_port="gradients",
        ),
    ]
    if shared_loader:
        val_source = "train_dl"
    else:
        val_source = "val_dl"
        params = {
            "format": val_format,
            "dataset_path": "val.pt",
            "batch_size": 128,
            "shuffle": False,
        }
        nodes.append(DagNodePayload(id="val_dl", type=val_node_type, parameters=params))
    edges.append(
        DagEdgePayload(
            id="e5",
            source_node_id=val_source,
            source_port="data",
            target_node_id="vloop",
            target_port="val_data",
        )
    )
    return PhaseDAGPayload(nodes=nodes, edges=edges)


def test_val_only_loader_does_not_clobber_train_loader() -> None:
    """A loader wired *only* to validationLoop.val_data must bind `val_loader`
    and nothing else.

    Regression: its generic `_pt_loading_code` also ran, re-binding
    `train_loader`/`test_loader` to the validation file. Emitted after the
    training loader, it silently overwrote the training set with the
    validation set — the model trained on the val split and then "validated"
    on those same samples (MNIST FCN baseline: 95.8% val, 82.25% test).
    """
    from backend.app.routers.notebook import PipelineConfigPayload, _phase_dag_to_code

    code = _phase_dag_to_code(
        _val_loop_train_phase(shared_loader=False),
        PipelineConfigPayload(epochs=5),
        "custom",
    )

    train_bindings = [
        ln
        for ln in code.splitlines()
        if ln.startswith(("train_loader = DataLoader", "test_loader  = DataLoader"))
    ]
    assert len(train_bindings) == 2, train_bindings  # exactly one loader's worth
    assert all("val.pt" not in ln for ln in train_bindings)
    assert "'train.pt'" in code
    assert "val_loader = DataLoader" in code
    assert "'val.pt'" in code


def test_shared_val_loader_still_binds_train_loader() -> None:
    """One dataLoader feeding both the pipeline and val_data still needs its
    generic codegen — otherwise nothing binds `train_loader` for this phase."""
    from backend.app.routers.notebook import PipelineConfigPayload, _phase_dag_to_code

    code = _phase_dag_to_code(
        _val_loop_train_phase(shared_loader=True),
        PipelineConfigPayload(epochs=5),
        "custom",
    )

    assert "train_loader = DataLoader" in code
    assert "val_loader = DataLoader" in code


def test_val_testloader_node_loads_dedicated_pt_file() -> None:
    """Regression: a `testLoader`-typed node (the Braille workspace's actual
    val_data wiring) with format='pt' must load its own dataset_path via
    `_pt_named_loading_code`, not reuse a bare `test_ds` global — which is
    never defined for `.pt`-file workflows and raises `NameError: test_ds`
    in the generated training cell.
    """
    from backend.app.routers.notebook import PipelineConfigPayload, _phase_dag_to_code

    code = _phase_dag_to_code(
        _val_loop_train_phase(shared_loader=False, val_node_type="testLoader"),
        PipelineConfigPayload(epochs=5),
        "custom",
    )

    assert "val_loader = DataLoader(_val_ds" in code
    assert "'val.pt'" in code
    assert "val_loader = DataLoader(test_ds" not in code


def test_val_dataloader_unsupported_format_does_not_reference_undefined_test_ds() -> (
    None
):
    """A `dataLoader` node wired to val_data with a format that defines
    neither `.pt` loading nor a bare tonic `test_ds` global must not emit a
    `val_loader = DataLoader(test_ds, ...)` line — that's a guaranteed
    NameError. It should fail loudly at codegen time instead.
    """
    from backend.app.routers.notebook import PipelineConfigPayload, _phase_dag_to_code

    code = _phase_dag_to_code(
        _val_loop_train_phase(
            shared_loader=False, val_node_type="dataLoader", val_format="auto"
        ),
        PipelineConfigPayload(epochs=5),
        "custom",
    )

    assert "val_loader = DataLoader(test_ds" not in code
    assert "raise RuntimeError" in code


def _eval_phase(loader_type: str, loader_params: dict) -> PhaseDAGPayload:
    from backend.app.routers.notebook import DagNodePayload, PhaseDAGPayload

    return PhaseDAGPayload(
        nodes=[
            DagNodePayload(id="e1", type=loader_type, parameters=loader_params),
            DagNodePayload(id="e2", type="forwardPass", parameters={}),
            DagNodePayload(id="e3", type="accuracyMetric", parameters={}),
        ],
        edges=[],
    )


def test_eval_loop_captures_activity_only_on_first_batch() -> None:
    """The eval loop must arm `net._capture_activity` only for batch 0, build
    the activity zip immediately after that batch's forward pass, and never
    touch it again for later batches — this is "one representative eval
    sample", not a running/repeated capture.
    """
    from backend.app.routers.notebook import PipelineConfigPayload, _phase_dag_to_code

    phase = _eval_phase("dataLoader", {"format": "pt", "dataset_path": "ds.pt"})
    code = _phase_dag_to_code(phase, PipelineConfigPayload(), "")

    assert "if batch_idx == 0:" in code
    assert "net._capture_activity = True" in code
    assert "net._capture_activity = False" in code
    assert "_nmtk_emit_activity(" in code
    assert "base64.b64encode(_activity_buf.getvalue()).decode('ascii'))" in code
    assert "zipfile.ZipFile(_activity_buf, 'w')" in code
    assert "f'{_act_k}_spikes.npy'" in code
    # Exactly one arm/disarm pair — not re-armed every batch.
    assert code.count("net._capture_activity = True") == 1
    assert code.count("net._capture_activity = False") == 1


# ── from test_notebook_generate_v2.py (dag/phase lowering) ──


def test_training_loop_is_real_and_runnable() -> None:
    """DAG-generated training cell must build a real epoch/batch loop with a
    working optimizer step — not a flat, unlooped stub that references
    `data`/`targets` before anything binds them."""
    from backend.app.routers.notebook import PipelineConfigPayload, _phase_dag_to_code

    code = _phase_dag_to_code(
        _braille_training_phase(), PipelineConfigPayload(epochs=2), "NMNIST"
    )

    assert "for epoch in range(2):" in code
    assert "for batch_idx, (data, targets) in enumerate(train_loader):" in code
    assert "optimizer.zero_grad()" in code
    assert "optimizer.step()" in code
    assert "# After backward: optimizer.step()" not in code
    assert "_nmtk_emit(" in code

    # Execute the loop body for real (stub net/loader) — this is the check
    # that catches the original NameError-on-`data` bug. Skips cleanly (not a
    # failure) when the active environment's torch install is broken at the
    # C-extension level — an environment problem, not a codegen bug.
    pytest.importorskip("torch", exc_type=ImportError)
    import torch
    import torch.nn as nn

    class _StubLayer(nn.Module):
        def __init__(self) -> None:
            super().__init__()
            self.fc = nn.Linear(4, 3)

        def forward(self, x: torch.Tensor) -> tuple[torch.Tensor, torch.Tensor]:
            out = torch.relu(self.fc(x))
            return out.unsqueeze(0), out.unsqueeze(0)

        def reset_mem(self) -> None:
            pass

    class _StubNet(nn.Module):
        def __init__(self) -> None:
            super().__init__()
            self.layer = _StubLayer()

        def modules(self):  # type: ignore[override]
            return [self.layer]

        def parameters(self):  # type: ignore[override]
            return self.layer.parameters()

        def __call__(self, x: torch.Tensor) -> tuple[torch.Tensor, torch.Tensor]:
            # Mirrors the real generated Net.forward(), which now sets this
            # attribute before returning (see _generate_snntorch_code) — the
            # training loop's _nmtk_emit call reads net._layer_rates.
            self._layer_rates = {"stub": 0.0}
            return self.layer(x)

    emitted: list[dict] = []

    def _nmtk_emit(
        epoch: int,
        total: int,
        loss: float,
        accuracy,
        layer_rates: dict,
        phase: str = "train",  # mirrors NMTK_EMIT_CELL_SOURCE's signature
    ) -> None:
        emitted.append(
            {
                "epoch": epoch,
                "total": total,
                "loss": loss,
                "accuracy": accuracy,
                "layer_rates": layer_rates,
            }
        )

    def _nmtk_emit_activity(epoch: int, activity_npy_b64: str) -> None:
        pass

    # Drop the loader-setup preamble (tonic dataset download) — keep
    # everything from the optimizer construction onward.
    body = (
        "optimizer = torch.optim.Adam"
        + code.split("optimizer = torch.optim.Adam", 1)[1]
    )
    exec_globals = {
        "torch": torch,
        "net": _StubNet(),
        "train_loader": [(torch.randn(2, 4), torch.tensor([0, 1])) for _ in range(3)],
        "_nmtk_emit": _nmtk_emit,
        "_nmtk_emit_activity": _nmtk_emit_activity,
    }
    exec(compile(body, "<training-loop>", "exec"), exec_globals)  # noqa: S102

    assert len(emitted) == 2, f"Expected one progress event per epoch, got {emitted}"
    assert all(e["accuracy"] is None for e in emitted)
    assert all(isinstance(e["loss"], float) for e in emitted)


def test_training_loop_scheduler_and_early_stopping_are_real() -> None:
    """reduceLROnPlateau/earlyStopping nodes must generate real per-epoch
    step()/break logic (using epoch-mean training loss), not comments."""
    from backend.app.routers.notebook import (
        DagNodePayload,
        PipelineConfigPayload,
        _phase_dag_to_code,
    )

    phase = _braille_training_phase()
    phase.nodes += [
        DagNodePayload(id="sched", type="reduceLROnPlateau", parameters={}),
        DagNodePayload(id="es", type="earlyStopping", parameters={"patience": 5}),
    ]
    code = _phase_dag_to_code(phase, PipelineConfigPayload(epochs=3), "NMNIST")

    assert "scheduler.step(avg_loss)" in code
    assert "# Call scheduler.step(val_loss) at end of each epoch" not in code
    assert "if avg_loss < _es_best - _es_min_delta:" in code
    assert "if _es_counter >= _es_patience:" in code
    assert "    break" in code
    assert "# if _es_counter >= _es_patience: break" not in code


def test_surrogate_backward_threads_spike_grad_into_architecture_cell() -> None:
    """Regression for the reported RuntimeError: the surrogateBackward node's
    spike_grad must reach every neuron constructor in the Architecture cell,
    not just be recreated (and discarded) in the Train cell."""
    from backend.app.routers.notebook import compile_to_nir

    graph = compile_to_nir(VALID_SPEC)
    phases = PipelinePhasesPayload(
        train=PhaseDAGPayload(
            nodes=[
                DagNodePayload(
                    id="t1", type="dataLoader", parameters={"batch_size": 32}
                ),
                DagNodePayload(id="t2", type="forwardPass", parameters={}),
                DagNodePayload(id="t3", type="ceCountLoss", parameters={}),
                DagNodePayload(
                    id="t4",
                    type="surrogateBackward",
                    parameters={"function": "fast_sigmoid", "slope": 5.0},
                ),
                DagNodePayload(id="t5", type="adamOptimiser", parameters={"lr": 0.001}),
            ],
            edges=[],
        )
    )
    nb, _ = _build_v2_notebook(
        VALID_SPEC,
        graph,
        PipelineConfigPayload(epochs=1),
        "2026-01-01 00:00 UTC",
        pipeline_phases=phases,
    )
    code_cells = [c for c in nb["cells"] if c["cell_type"] == "code"]
    arch_cells = [
        c for c in code_cells if "class Net(nn.Module)" in "".join(c["source"])
    ]
    assert arch_cells, "Expected an Architecture cell defining Net(nn.Module)"
    arch_src = "".join(arch_cells[0]["source"])

    assert "spike_grad = surrogate.fast_sigmoid(slope=5.0)" in arch_src
    leaky_ctor_lines = [ln for ln in arch_src.splitlines() if "snn.Leaky(" in ln]
    assert leaky_ctor_lines, "Expected at least one snn.Leaky(...) constructor"
    assert all("spike_grad=spike_grad" in ln for ln in leaky_ctor_lines)

    train_cells = [
        c for c in code_cells if "for epoch in range(" in "".join(c["source"])
    ]
    assert train_cells, "Expected a Train cell with the epoch loop"
    train_src = "".join(train_cells[0]["source"])
    assert "spike_grad = surrogate.fast_sigmoid" not in train_src
    assert "loss_val.backward()" in train_src


def test_no_surrogate_backward_node_omits_spike_grad() -> None:
    """Without a surrogateBackward node, generated code is unchanged from
    before this fix — no spike_grad kwarg anywhere."""
    from backend.app.routers.notebook import compile_to_nir

    graph = compile_to_nir(VALID_SPEC)
    phases = PipelinePhasesPayload(
        train=PhaseDAGPayload(
            nodes=[
                DagNodePayload(
                    id="t1", type="dataLoader", parameters={"batch_size": 32}
                ),
                DagNodePayload(id="t2", type="forwardPass", parameters={}),
                DagNodePayload(id="t3", type="ceCountLoss", parameters={}),
                DagNodePayload(id="t5", type="adamOptimiser", parameters={"lr": 0.001}),
            ],
            edges=[],
        )
    )
    nb, _ = _build_v2_notebook(
        VALID_SPEC,
        graph,
        PipelineConfigPayload(epochs=1),
        "2026-01-01 00:00 UTC",
        pipeline_phases=phases,
    )
    code_cells = [c for c in nb["cells"] if c["cell_type"] == "code"]
    arch_cells = [
        c for c in code_cells if "class Net(nn.Module)" in "".join(c["source"])
    ]
    arch_src = "".join(arch_cells[0]["source"])
    assert "spike_grad" not in arch_src


def test_snntorch_architecture_cell_seeds_rng_by_default() -> None:
    from backend.app.routers.notebook import compile_to_nir

    graph = compile_to_nir(VALID_SPEC)
    phases = PipelinePhasesPayload(
        train=PhaseDAGPayload(
            nodes=[
                DagNodePayload(
                    id="t1", type="dataLoader", parameters={"batch_size": 32}
                ),
                DagNodePayload(id="t2", type="forwardPass", parameters={}),
                DagNodePayload(id="t3", type="ceCountLoss", parameters={}),
                DagNodePayload(id="t5", type="adamOptimiser", parameters={"lr": 0.001}),
            ],
            edges=[],
        )
    )
    nb, _ = _build_v2_notebook(
        VALID_SPEC,
        graph,
        PipelineConfigPayload(epochs=1),
        "2026-01-01 00:00 UTC",
        pipeline_phases=phases,
    )
    code_cells = [c for c in nb["cells"] if c["cell_type"] == "code"]
    arch_cells = [
        c for c in code_cells if "class Net(nn.Module)" in "".join(c["source"])
    ]
    arch_src = "".join(arch_cells[0]["source"])
    assert "torch.manual_seed(42)" in arch_src
    assert "np.random.seed(42)" in arch_src
    assert arch_src.index("torch.manual_seed(42)") < arch_src.index(
        "class Net(nn.Module)"
    )


def test_snntorch_architecture_cell_honors_custom_seed() -> None:
    from backend.app.routers.notebook import compile_to_nir

    graph = compile_to_nir(VALID_SPEC)
    phases = PipelinePhasesPayload(
        train=PhaseDAGPayload(
            nodes=[
                DagNodePayload(
                    id="t1", type="dataLoader", parameters={"batch_size": 32}
                ),
                DagNodePayload(id="t2", type="forwardPass", parameters={}),
                DagNodePayload(id="t3", type="ceCountLoss", parameters={}),
                DagNodePayload(id="t5", type="adamOptimiser", parameters={"lr": 0.001}),
            ],
            edges=[],
        )
    )
    nb, _ = _build_v2_notebook(
        VALID_SPEC,
        graph,
        PipelineConfigPayload(epochs=1, seed=123),
        "2026-01-01 00:00 UTC",
        pipeline_phases=phases,
    )
    code_cells = [c for c in nb["cells"] if c["cell_type"] == "code"]
    arch_cells = [
        c for c in code_cells if "class Net(nn.Module)" in "".join(c["source"])
    ]
    arch_src = "".join(arch_cells[0]["source"])
    assert "torch.manual_seed(123)" in arch_src
    assert "np.random.seed(123)" in arch_src


def test_validation_loop_val_data_dataloader_wiring_does_not_clobber_train_loader() -> (
    None
):
    """A dedicated Data Loader wired into validationLoop's val_data port must
    bind `val_loader` from its own dataset_path, and must not overwrite the
    phase's primary `train_loader`."""
    from backend.app.routers.notebook import PipelineConfigPayload, _phase_dag_to_code

    phase = PhaseDAGPayload(
        nodes=[
            DagNodePayload(
                id="train_dl",
                type="dataLoader",
                parameters={"format": "pt", "dataset_path": "/tmp/train_ds.pt"},
            ),
            DagNodePayload(id="fwd", type="forwardPass", parameters={}),
            DagNodePayload(id="loss", type="ceCountLoss", parameters={}),
            DagNodePayload(id="bwd", type="surrogateBackward", parameters={}),
            DagNodePayload(id="opt", type="adamOptimiser", parameters={"lr": 0.001}),
            DagNodePayload(
                id="val_dl",
                type="dataLoader",
                parameters={"format": "pt", "dataset_path": "/tmp/val_ds.pt"},
            ),
            DagNodePayload(
                id="vl",
                type="validationLoop",
                parameters={"every_n_epochs": 1, "save_best_checkpoint": True},
            ),
        ],
        edges=[
            {
                "id": "e_val",
                "source_node_id": "val_dl",
                "source_port": "data",
                "target_node_id": "vl",
                "target_port": "val_data",
            },
        ],
    )
    code = _phase_dag_to_code(phase, PipelineConfigPayload(epochs=1), "NMNIST")

    assert "torch.load('/tmp/train_ds.pt'" in code
    assert "torch.load('/tmp/val_ds.pt'" in code
    assert "val_loader = DataLoader(_val_ds" in code
    assert "train_loader = DataLoader(_ds" in code
    # The val loader's own load must never be re-bound to train_loader/test_loader.
    val_block_start = code.index("torch.load('/tmp/val_ds.pt'")
    val_block = code[val_block_start : val_block_start + 600]
    assert "train_loader = DataLoader(_val_ds" not in val_block
    assert "test_loader  = DataLoader(_val_ds" not in val_block


def test_validation_loop_and_early_stopping_check_val_loss_not_avg_loss() -> None:
    """When both validationLoop (with wired val_data) and earlyStopping are
    present, early stopping must monitor real held-out val_loss, not the
    epoch-mean training loss."""
    from backend.app.routers.notebook import (
        DagEdgePayload,
        PipelineConfigPayload,
        _phase_dag_to_code,
    )

    phase = _braille_training_phase()
    phase.nodes += [
        DagNodePayload(
            id="val_dl",
            type="testLoader",
            parameters={"batch_size": 32},
        ),
        DagNodePayload(
            id="vl",
            type="validationLoop",
            parameters={"every_n_epochs": 1, "save_best_checkpoint": True},
        ),
        DagNodePayload(id="es", type="earlyStopping", parameters={"patience": 5}),
    ]
    phase.edges += [
        DagEdgePayload(
            id="e_val",
            source_node_id="val_dl",
            source_port="data",
            target_node_id="vl",
            target_port="val_data",
        ),
    ]
    code = _phase_dag_to_code(phase, PipelineConfigPayload(epochs=3), "NMNIST")

    assert "if val_loss < _es_best - _es_min_delta:" in code
    assert "if avg_loss < _es_best - _es_min_delta:" not in code
    assert "if _es_counter >= _es_patience:" in code
    assert "torch.save(net.state_dict(), 'best_model.pt')" in code


def test_validation_loop_without_val_data_and_save_best_checkpoint_fails_fast() -> None:
    """save_best_checkpoint=True (the default) with no val_data wired must
    raise at codegen time rather than silently skip real validation."""
    from backend.app.routers.notebook import PipelineConfigPayload, _phase_dag_to_code

    phase = _braille_training_phase()
    phase.nodes += [
        DagNodePayload(
            id="vl",
            type="validationLoop",
            parameters={"every_n_epochs": 1, "save_best_checkpoint": True},
        ),
    ]
    with pytest.raises(ValueError, match="val_data"):
        _phase_dag_to_code(phase, PipelineConfigPayload(epochs=1), "NMNIST")


def test_validation_loop_without_val_data_but_checkpoint_disabled_is_allowed() -> None:
    """save_best_checkpoint=False with no val_data wired is a valid (if inert)
    configuration — it must not raise, and must fall back to the pre-existing
    comment-only setup line."""
    from backend.app.routers.notebook import PipelineConfigPayload, _phase_dag_to_code

    phase = _braille_training_phase()
    phase.nodes += [
        DagNodePayload(
            id="vl",
            type="validationLoop",
            parameters={"every_n_epochs": 1, "save_best_checkpoint": False},
        ),
    ]
    code = _phase_dag_to_code(phase, PipelineConfigPayload(epochs=1), "NMNIST")
    assert "validationLoop has no val_data input wired" in code


def test_dag_phases_generate_train_section(tmp_path: Path) -> None:
    with patch("backend.app.routers.notebook.NOTEBOOK_DIR", tmp_path):
        resp = client.post(
            "/api/notebook/generate-v2",
            json={
                "spec": VALID_SPEC,
                "pipeline_phases": {
                    "train": {
                        "nodes": [
                            {
                                "id": "n1",
                                "type": "dataLoader",
                                "parameters": {"batch_size": 64},
                            },
                            {"id": "n2", "type": "forwardPass", "parameters": {}},
                            {"id": "n3", "type": "mseCountLoss", "parameters": {}},
                            {"id": "n4", "type": "surrogateBackward", "parameters": {}},
                            {
                                "id": "n5",
                                "type": "adamOptimiser",
                                "parameters": {"lr": 1e-3},
                            },
                        ],
                        "edges": [
                            {
                                "id": "e1",
                                "source_node_id": "n1",
                                "source_port": "data",
                                "target_node_id": "n2",
                                "target_port": "data",
                            },
                        ],
                    },
                    "eval": {"nodes": [], "edges": []},
                },
            },
        )
    assert resp.status_code == 200, resp.text


def test_dag_node_code_adam_contains_lr() -> None:
    from backend.app.routers.notebook import (
        DagNodePayload,
        PipelineConfigPayload,
        _dag_node_code,
    )

    node = DagNodePayload(id="x", type="adamOptimiser", parameters={"lr": 5e-4})
    code = _dag_node_code(node, PipelineConfigPayload(), "NMNIST")
    assert code is not None
    # 5e-4 may be formatted as 0.0005 or 5e-4 by Python
    assert "0.0005" in code or "5e-4" in code or "5e-04" in code


def test_topo_sort_respects_edges() -> None:
    from backend.app.routers.notebook import DagEdgePayload, DagNodePayload, _topo_sort

    n1 = DagNodePayload(id="n1", type="dataLoader")
    n2 = DagNodePayload(id="n2", type="forwardPass")
    edge = DagEdgePayload(
        id="e1",
        source_node_id="n1",
        source_port="data",
        target_node_id="n2",
        target_port="data",
    )
    # Pass in deliberately wrong order — topo_sort must fix it
    ordered = _topo_sort([n2, n1], [edge])
    assert ordered.index(n1) < ordered.index(n2)


def test_phase_dag_to_code_mse_loss() -> None:
    from backend.app.routers.notebook import (
        DagNodePayload,
        PhaseDAGPayload,
        PipelineConfigPayload,
        _phase_dag_to_code,
    )

    phase = PhaseDAGPayload(
        nodes=[
            DagNodePayload(
                id="n1", type="mseCountLoss", parameters={"correct_rate": 0.9}
            ),
        ],
        edges=[],
    )
    code = _phase_dag_to_code(phase, PipelineConfigPayload(), "NMNIST")
    assert "mse_count_loss" in code
    assert "0.9" in code


def test_eval_phase_forward_pass_wrapped_in_no_grad() -> None:
    """_phase_dag_to_code must wrap the eval forward pass in torch.no_grad()."""
    from backend.app.routers.notebook import (
        DagEdgePayload,
        DagNodePayload,
        PhaseDAGPayload,
        PipelineConfigPayload,
        _phase_dag_to_code,
    )

    # Minimal eval phase: a testLoader (loader) + forwardPass + accuracyMetric
    # The eval path in _phase_dag_to_code requires at least one _LOADER_TYPES node
    # and one _METRIC_TYPES node to detect it as an eval phase.
    phase = PhaseDAGPayload(
        nodes=[
            DagNodePayload(id="l1", type="testLoader", parameters={}),
            DagNodePayload(id="fp", type="forwardPass", parameters={}),
            DagNodePayload(id="m1", type="accuracyMetric", parameters={}),
        ],
        edges=[
            DagEdgePayload(
                id="e1",
                source_node_id="l1",
                source_port="data",
                target_node_id="fp",
                target_port="data",
            ),
        ],
    )
    code = _phase_dag_to_code(phase, PipelineConfigPayload(), "NMNIST")

    assert (
        "with torch.no_grad():" in code
    ), "Eval phase must be wrapped in torch.no_grad()"
    assert (
        "spk_out, mem_out = net(data)" in code
    ), "Eval phase must contain the forward pass call"


def test_eval_phase_can_limit_batches_for_bounded_verification() -> None:
    from backend.app.routers.notebook import (
        DagNodePayload,
        PhaseDAGPayload,
        PipelineConfigPayload,
        _phase_dag_to_code,
    )

    phase = PhaseDAGPayload(
        nodes=[
            DagNodePayload(id="l1", type="testLoader", parameters={}),
            DagNodePayload(id="fp", type="forwardPass", parameters={}),
            DagNodePayload(id="m1", type="accuracyMetric", parameters={}),
        ],
        edges=[],
    )
    cfg = PipelineConfigPayload(
        evaluation_profile="bounded_classification",
        max_eval_batches=3,
    )

    code = _phase_dag_to_code(phase, cfg, "NMNIST")

    assert "for batch_idx, (data, targets) in enumerate(test_loader):" in code
    assert "if batch_idx >= 3:" in code
    assert "break" in code


def test_eval_phase_emits_nmtk_progress_event() -> None:
    """An eval-only phase (no training nodes) must emit `_nmtk_emit(...)`
    both per-batch (so the Run step's Live Metrics sidebar updates while the
    eval loop is still running) and once more after the loop closes with the
    definitive full-dataset accuracy (so Results step sees a final event)."""
    from backend.app.routers.notebook import (
        DagNodePayload,
        PhaseDAGPayload,
        PipelineConfigPayload,
        _phase_dag_to_code,
    )

    phase = PhaseDAGPayload(
        nodes=[
            DagNodePayload(id="l1", type="testLoader", parameters={}),
            DagNodePayload(id="fp", type="forwardPass", parameters={}),
            DagNodePayload(id="m1", type="accuracyMetric", parameters={}),
        ],
        edges=[],
    )
    code = _phase_dag_to_code(phase, PipelineConfigPayload(), "NMNIST")

    assert "accuracy=(correct / total if total else None)" in code
    # Emitted at least twice: once per-batch (inside the loop) and once
    # after the loop closes with the final, whole-dataset accuracy.
    assert code.count("_nmtk_emit(") >= 2

    loop_index = code.index("for batch_idx, (data, targets) in enumerate(test_loader):")
    first_emit_index = code.index("_nmtk_emit(")
    last_emit_index = code.rindex("_nmtk_emit(")
    # The per-batch emit lives inside the loop; the final emit is the last
    # one and sits after the loop closes (epoch=1, total=1 marks it final).
    assert first_emit_index > loop_index
    assert "epoch=batch_idx + 1" in code
    assert last_emit_index > first_emit_index
    assert "epoch=1,\n" in code[last_emit_index:]
    assert "total=1,\n" in code[last_emit_index:]


def test_spike_generator_on_eval_canvas_defines_train_loader_before_train_cell() -> (
    None
):
    """Regression: when the train phase has no loader node but the eval phase
    has a spikeGenerator, train_loader must be defined in a cell that appears
    *before* the Train cell — not inside the later Evaluate cell.

    Previously this caused ``NameError: name 'train_loader' is not defined``
    when the Train cell ran first in a fresh kernel.
    """
    import nir as _nir
    import numpy as np

    graph = _nir.NIRGraph(
        nodes={
            "input": _nir.Input(input_type={"input": np.array([4])}),
            "output": _nir.Output(output_type={"output": np.array([4])}),
        },
        edges=[("input", "output")],
    )

    train_phase = PhaseDAGPayload(
        nodes=[
            DagNodePayload(id="fp", type="forwardPass", parameters={}),
        ],
        edges=[],
    )
    eval_phase = PhaseDAGPayload(
        nodes=[
            DagNodePayload(
                id="sg",
                type="spikeGenerator",
                parameters={
                    "n_neurons": 784,
                    "n_timesteps": 100,
                    "pattern": "poisson",
                    "rate_hz": 0.5,
                },
            ),
            DagNodePayload(id="fp2", type="forwardPass", parameters={}),
        ],
        edges=[],
    )

    nb, _ = _build_v2_notebook(
        spec="",
        graph=graph,
        cfg=PipelineConfigPayload(framework="snntorch_sim", dataset=""),
        timestamp="2026-01-01 00:00 UTC",
        pipeline_phases=PipelinePhasesPayload(train=train_phase, eval=eval_phase),
    )

    code_cells = ["".join(c["source"]) for c in nb["cells"] if c["cell_type"] == "code"]
    md_cells = [
        "".join(c["source"]) for c in nb["cells"] if c["cell_type"] == "markdown"
    ]

    # Find the index of the cell that defines train_loader and the index of
    # the Train markdown header cell.
    spike_gen_cell_idx = next(
        (
            i
            for i, src in enumerate(code_cells)
            if "train_loader" in src
            and "spikeGenerator" not in src
            and "torch.rand" in src
            or ("train_loader" in src and "Spike generator" in src)
        ),
        None,
    )
    # The cell that contains "train_loader = DataLoader" must exist
    all_cells_src = ["".join(c["source"]) for c in nb["cells"]]
    setup_cell_idx = next(
        (
            i
            for i, src in enumerate(all_cells_src)
            if "train_loader = DataLoader" in src and "## Train" not in src
        ),
        None,
    )
    train_header_idx = next(
        (i for i, src in enumerate(all_cells_src) if src.strip() == "## Train"),
        None,
    )

    assert (
        setup_cell_idx is not None
    ), "No cell defining train_loader was found — SpikeGenerator hoist is missing"
    assert train_header_idx is not None, "## Train markdown cell not found"
    assert setup_cell_idx < train_header_idx, (
        f"train_loader setup cell (idx {setup_cell_idx}) must come before "
        f"## Train header cell (idx {train_header_idx})"
    )


def test_lif_trace_profile_emits_trace_csv() -> None:
    from backend.app.routers.notebook import (
        DagNodePayload,
        PhaseDAGPayload,
        PipelineConfigPayload,
        _phase_dag_to_code,
    )

    phase = PhaseDAGPayload(
        nodes=[
            DagNodePayload(id="spikes", type="spikeGenerator", parameters={}),
            DagNodePayload(id="fp", type="forwardPass", parameters={}),
            DagNodePayload(
                id="trace", type="traceMetric", parameters={"filename": "lif_trace.csv"}
            ),
        ],
        edges=[],
    )
    cfg = PipelineConfigPayload(evaluation_profile="lif_trace")

    code = _phase_dag_to_code(phase, cfg, "")

    assert "lif_trace.csv" in code
    assert "np.savetxt" in code
    assert "input_trace" in code
    assert "mem_trace" in code
    assert "spike_trace" in code


def test_shd_loader_uses_microsecond_time_window_and_time_first_padding() -> None:
    from backend.app.routers.notebook import _dag_node_code, _dataset_loading_code

    node = DagNodePayload(
        id="shd",
        type="dataLoader",
        parameters={"format": "tonic_shd", "time_window_ms": 4, "batch_size": 32},
    )
    dag_src = _dag_node_code(node, PipelineConfigPayload(), "tonic_shd")
    fallback_src = _dataset_loading_code("tonic_shd", 32, time_window_ms=4)

    for src in (dag_src, fallback_src):
        assert "ToFrame(sensor_size=_sensor_size, time_window=4000)" in src
        assert "PadTensors(batch_first=False)" in src
        assert "collate_fn=_pad_collate" in src
    assert "n_time_bins=25" not in dag_src


def test_shd_validation_and_eval_use_time_major_spike_counts() -> None:
    from backend.app.routers.notebook import _phase_dag_to_code

    phase = PhaseDAGPayload(
        nodes=[
            DagNodePayload(
                id="loader",
                type="dataLoader",
                parameters={"format": "tonic_shd", "time_window_ms": 4},
            ),
            DagNodePayload(id="forward", type="forwardPass"),
            DagNodePayload(id="loss", type="ceCountLoss"),
            DagNodePayload(id="backward", type="surrogateBackward"),
            DagNodePayload(id="optimiser", type="adamOptimiser"),
            DagNodePayload(
                id="val_loader",
                type="testLoader",
                parameters={"format": "tonic_shd", "time_window_ms": 4},
            ),
            DagNodePayload(
                id="validation",
                type="validationLoop",
                parameters={"save_best_checkpoint": True},
            ),
        ],
        edges=[
            {
                "id": "validation-data",
                "source_node_id": "val_loader",
                "source_port": "data",
                "target_node_id": "validation",
                "target_port": "val_data",
            }
        ],
    )
    train_src = _phase_dag_to_code(phase, PipelineConfigPayload(epochs=1), "tonic_shd")
    assert "loss_fn(spk_out, targets)" in train_src
    assert "loss_fn(_vl_spk_out, _vl_targets)" in train_src
    assert "_vl_spk_out.sum(0).argmax(-1)" in train_src
    assert "_vl_targets.size(0)" in train_src


def test_generated_pt_notebook_runs_train_and_eval_cells(tmp_path: Path) -> None:
    """Execute a fresh generated notebook against a tiny real PT dataset.

    This is the offline analogue of the SHD smoke path: it verifies that
    dataset loading, model execution, loss/backward, and evaluation are
    executable before a network-dependent tonic download is attempted.
    """
    torch = pytest.importorskip("torch")
    pytest.importorskip("snntorch")
    from torch.utils.data import TensorDataset

    from backend.app.routers.notebook import compile_to_nir

    dataset_path = tmp_path / "smoke.pt"
    torch.save(
        TensorDataset(
            torch.zeros(4, 5, 4, dtype=torch.float32),
            torch.tensor([0, 1, 0, 1], dtype=torch.long),
        ),
        dataset_path,
    )
    phases = PipelinePhasesPayload(
        train=PhaseDAGPayload(
            nodes=[
                DagNodePayload(
                    id="loader",
                    type="dataLoader",
                    parameters={
                        "format": "pt",
                        "dataset_path": str(dataset_path),
                        "batch_size": 2,
                    },
                ),
                DagNodePayload(id="forward", type="forwardPass"),
                DagNodePayload(id="loss", type="ceCountLoss"),
                DagNodePayload(id="backward", type="surrogateBackward"),
                DagNodePayload(id="optimiser", type="adamOptimiser"),
            ],
            edges=[],
        ),
        eval=PhaseDAGPayload(
            nodes=[
                DagNodePayload(
                    id="loader",
                    type="testLoader",
                    parameters={
                        "format": "pt",
                        "dataset_path": str(dataset_path),
                        "batch_size": 2,
                    },
                ),
                DagNodePayload(id="forward", type="forwardPass"),
                DagNodePayload(id="accuracy", type="accuracyMetric"),
            ],
            edges=[],
        ),
    )
    nb, artifacts = _build_v2_notebook(
        VALID_SPEC,
        compile_to_nir(VALID_SPEC),
        PipelineConfigPayload(framework="snntorch_sim", epochs=1),
        "2026-01-01 00:00 UTC",
        pipeline_phases=phases,
    )

    for name, content in artifacts.items():
        (tmp_path / name).write_bytes(content)
    namespace: dict[str, object] = {}

    previous_cwd = os.getcwd()
    os.chdir(tmp_path)
    try:
        for cell in nb["cells"]:
            if cell["cell_type"] != "code":
                continue
            source = "".join(cell["source"])
            if "nbconvert" in source:
                continue
            exec(compile(source, "<generated-smoke-cell>", "exec"), namespace)
    finally:
        os.chdir(previous_cwd)

    assert "net" in namespace
    assert "train_loader" in namespace
    assert "test_loader" in namespace
    assert int(namespace["correct"]) >= 0
