"""Tests for ``backend.app.services.notebook_dag_node_emitters`` (per-node DAG
code emitters such as ``dag_node_code`` and ``_custom_pipeline_node_code``).
Exercises the emitter surface re-exported from ``backend.app.routers.notebook``.
"""

from __future__ import annotations

import pytest

from backend.app.routers.notebook import PhaseDAGPayload


def test_ce_count_loss_dag_node() -> None:
    from backend.app.routers.notebook import (
        DagNodePayload,
        PipelineConfigPayload,
        _dag_node_code,
    )

    node = DagNodePayload(id="loss1", type="ceCountLoss", parameters={})
    cfg = PipelineConfigPayload()
    code = _dag_node_code(node, cfg, "")
    assert "SF.ce_count_loss()" in code
    assert "loss_val" in code


def test_custom_pipeline_node_overrides_builtin_code(tmp_path, monkeypatch) -> None:
    from backend.app.routers.notebook import (
        DagNodePayload,
        PipelineConfigPayload,
        _dag_node_code,
    )

    custom_dir = tmp_path / ".nmtk" / "custom_nodes"
    custom_dir.mkdir(parents=True)
    (custom_dir / "custom_adam.py").write_text(
        """
from nmtk_sdk import CustomNode

class CustomAdam(CustomNode):
    name = "Custom Adam"
    category = "optimiser"
    canvases = ["training"]
    frameworks = ["snntorch_sim"]
    node_id = "custom_adam_12345678"
    base_pipeline_type = "adamOptimiser"

    def to_pipeline(self, params):
        return f"custom_lr = {params['lr']}"
""",
        encoding="utf-8",
    )
    monkeypatch.setattr("backend.app.routers.notebook.Path.home", lambda: tmp_path)
    node = DagNodePayload(
        id="optimiser",
        type="adamOptimiser",
        custom_component_id="custom_adam_12345678",
        parameters={"lr": 0.004},
    )

    code = _dag_node_code(node, PipelineConfigPayload(), "")

    assert code == "custom_lr = 0.004"


def test_custom_pipeline_clone_falls_back_to_builtin_code(
    tmp_path, monkeypatch
) -> None:
    from backend.app.routers.notebook import (
        DagNodePayload,
        PipelineConfigPayload,
        _dag_node_code,
    )

    custom_dir = tmp_path / ".nmtk" / "custom_nodes"
    custom_dir.mkdir(parents=True)
    (custom_dir / "custom_adam.py").write_text(
        """
from nmtk_sdk import CustomNode

class CustomAdam(CustomNode):
    name = "Custom Adam"
    category = "optimiser"
    canvases = ["training"]
    frameworks = ["snntorch_sim"]
    node_id = "custom_adam_12345678"
    base_pipeline_type = "adamOptimiser"
""",
        encoding="utf-8",
    )
    monkeypatch.setattr("backend.app.routers.notebook.Path.home", lambda: tmp_path)
    node = DagNodePayload(
        id="optimiser",
        type="adamOptimiser",
        custom_component_id="custom_adam_12345678",
        parameters={"lr": 0.004},
    )

    code = _dag_node_code(node, PipelineConfigPayload(), "")

    assert code is not None
    assert "torch.optim.Adam" in code


def test_l1_spike_reg_falls_back_to_mem_out_on_unresolvable_target_layer() -> None:
    from backend.app.routers.notebook import (
        DagNodePayload,
        PipelineConfigPayload,
        _dag_node_code,
    )

    node = DagNodePayload(
        id="reg1",
        type="l1SpikeReg",
        parameters={"weight": 0.001, "target_layer": "cnl.RSynaptic"},
    )
    code = _dag_node_code(node, PipelineConfigPayload(), "")
    assert "torch.mean(torch.sum(mem_out, dim=0))" in code
    assert "ponytail: target_layer='cnl.RSynaptic'" in code


def test_l2_spike_reg_falls_back_to_mem_out_on_unresolvable_target_layer() -> None:
    from backend.app.routers.notebook import (
        DagNodePayload,
        PipelineConfigPayload,
        _dag_node_code,
    )

    node = DagNodePayload(
        id="reg2",
        type="l2SpikeReg",
        parameters={"weight": 1e-6, "target_layer": "cnl.RSynaptic"},
    )
    code = _dag_node_code(node, PipelineConfigPayload(), "")
    assert "torch.mean(torch.sum(torch.sum(mem_out, dim=0), dim=1) ** 2)" in code
    assert "ponytail: target_layer='cnl.RSynaptic'" in code


def test_l1_spike_reg_accepts_valid_target_layer() -> None:
    from backend.app.routers.notebook import (
        DagNodePayload,
        PipelineConfigPayload,
        _dag_node_code,
    )

    node = DagNodePayload(
        id="reg3",
        type="l1SpikeReg",
        parameters={"weight": 0.001, "target_layer": "mem_out"},
    )
    code = _dag_node_code(node, PipelineConfigPayload(), "")
    assert "torch.mean(torch.sum(mem_out, dim=0))" in code
    assert "ponytail" not in code


def test_l1_spike_reg_blank_target_layer_defaults_to_mem_out() -> None:
    from backend.app.routers.notebook import (
        DagNodePayload,
        PipelineConfigPayload,
        _dag_node_code,
    )

    node = DagNodePayload(id="reg4", type="l1SpikeReg", parameters={"weight": 0.001})
    code = _dag_node_code(node, PipelineConfigPayload(), "")
    assert "torch.mean(torch.sum(mem_out, dim=0))" in code
    assert "ponytail" not in code


def test_l2_spike_reg_accepts_spk_out_target_layer() -> None:
    from backend.app.routers.notebook import (
        DagNodePayload,
        PipelineConfigPayload,
        _dag_node_code,
    )

    node = DagNodePayload(
        id="reg5",
        type="l2SpikeReg",
        parameters={"weight": 1e-6, "target_layer": "spk_out"},
    )
    code = _dag_node_code(node, PipelineConfigPayload(), "")
    assert "torch.mean(torch.sum(torch.sum(spk_out, dim=0), dim=1) ** 2)" in code
    assert "ponytail" not in code


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


def test_eval_dataloader_defaults_to_loading_best_checkpoint() -> None:
    from backend.app.routers.notebook import PipelineConfigPayload, _phase_dag_to_code

    phase = _eval_phase("dataLoader", {"format": "pt", "dataset_path": "ds.pt"})
    code = _phase_dag_to_code(phase, PipelineConfigPayload(), "")
    assert "net.load_state_dict(torch.load('best_model.pt'" in code
    assert "except FileNotFoundError:" in code


def test_eval_dataloader_load_best_checkpoint_false_skips_load() -> None:
    from backend.app.routers.notebook import PipelineConfigPayload, _phase_dag_to_code

    phase = _eval_phase(
        "dataLoader",
        {"format": "pt", "dataset_path": "ds.pt", "load_best_checkpoint": False},
    )
    code = _phase_dag_to_code(phase, PipelineConfigPayload(), "")
    assert "best_model.pt" not in code


def test_eval_testloader_defaults_to_loading_best_checkpoint() -> None:
    from backend.app.routers.notebook import PipelineConfigPayload, _phase_dag_to_code

    phase = _eval_phase("testLoader", {"batch_size": 32})
    code = _phase_dag_to_code(phase, PipelineConfigPayload(), "NMNIST")
    assert "net.load_state_dict(torch.load('best_model.pt'" in code


def _dag_code(node_type: str, params: dict) -> str:
    from backend.app.routers.notebook import (
        DagNodePayload,
        PipelineConfigPayload,
        _dag_node_code,
    )

    node = DagNodePayload(id="n1", type=node_type, parameters=params)
    return _dag_node_code(node, PipelineConfigPayload(), "")


def test_gradient_clip_dag_node() -> None:
    code = _dag_code("gradientClip", {"max_norm": 2.0})
    assert "clip_grad_norm_" in code
    assert "max_norm=2.0" in code


def test_weight_clip_dag_node() -> None:
    code = _dag_code("weightClip", {"min_weight": -0.5, "max_weight": 0.5})
    assert "clamp_(-0.5, 0.5)" in code
    assert "no_grad" in code


def test_reduce_lr_on_plateau_dag_node() -> None:
    code = _dag_code(
        "reduceLROnPlateau",
        {"mode": "min", "factor": 0.5, "patience": 5, "min_lr": 1e-6},
    )
    assert "ReduceLROnPlateau" in code
    assert "patience=5" in code
    assert "scheduler" in code


def test_early_stopping_dag_node() -> None:
    # In isolation, this node only emits its variable init — the real
    # per-epoch check/break is emitted by _phase_dag_to_code's training loop
    # wrapper (see test_training_loop_scheduler_and_early_stopping_are_real
    # in test_notebook_generate_v2.py).
    code = _dag_code("earlyStopping", {"patience": 7, "min_delta": 0.001})
    assert "_es_patience" in code
    assert "7" in code


def test_validation_loop_dag_node() -> None:
    # In isolation, this node only emits its variable init — the real
    # per-epoch validation pass is emitted by _training_phase_to_code's
    # epoch_tail wrapper (see test_notebook_generate_v2.py for end-to-end
    # coverage of that wiring).
    code = _dag_code(
        "validationLoop",
        {
            "every_n_epochs": 2,
            "save_best_checkpoint": True,
            "checkpoint_metric": "val_accuracy",
            "checkpoint_mode": "max",
        },
    )
    assert "no code generator defined" not in code
    assert "_vl_every_n_epochs = 2" in code
    assert "_vl_save_best_checkpoint = True" in code
    assert "_vl_checkpoint_metric = 'val_accuracy'" in code
    assert "_vl_checkpoint_mode = 'max'" in code
    assert "_vl_best = float('-inf')" in code


def test_validation_loop_dag_node_min_mode_inits_positive_infinity() -> None:
    code = _dag_code(
        "validationLoop",
        {"checkpoint_metric": "val_loss", "checkpoint_mode": "min"},
    )
    assert "_vl_best = float('inf')" in code


def test_validation_loop_dag_node_ignores_stray_epochs_param() -> None:
    """The node schema no longer has an `epochs` field (removed to keep the
    outer pipeline `config["epochs"]` the single source of truth), but
    codegen must also not resurrect one if a stale param dict still has it
    (e.g. an old saved workspace)."""
    code = _dag_code("validationLoop", {"epochs": 500, "every_n_epochs": 1})
    assert "_vl_every_n_epochs = 1" in code
    assert "500" not in code


def test_spike_count_metric_dag_node() -> None:
    code = _dag_code("spikeCountMetric", {})
    assert "mean_spike_count" in code
    assert "spk_out" in code


def test_latency_metric_dag_node() -> None:
    code = _dag_code("latencyMetric", {"default_latency": -1})
    assert "ttfs_acc" in code
    assert "argmin" in code
    assert "_first_spk" in code


def test_lbi_optimizer_dag_node_emits_class_and_construction() -> None:
    code = _dag_code("lbiOptimizer", {"lr": 0.001, "lambda_reg": 0.01, "kappa": 10.0})
    assert "class LinearizedBregmanOptimizer(torch.optim.Optimizer)" in code
    assert "torch.sign(z) * torch.clamp(z.abs() - lambda_reg, min=0.0)" in code
    assert "optimizer = LinearizedBregmanOptimizer(" in code
    assert "lr=0.001" in code
    assert "lambda_reg=0.01" in code
    assert "kappa=10.0" in code
    assert "no code generator defined" not in code


def test_lbi_optimizer_dag_node_uses_default_params() -> None:
    code = _dag_code("lbiOptimizer", {})
    assert "lr=0.001" in code
    assert "lambda_reg=0.01" in code
    assert "kappa=10.0" in code


def test_lbi_optimizer_is_classified_as_setup_not_body() -> None:
    """`lbiOptimizer` must be in `_OPTIMISER_TYPES` so `classify_phase` treats
    it as a once-only setup node (like `adamOptimiser`), not a per-batch body
    node — otherwise the class would be redefined and the optimizer state
    reset every single batch."""
    from neurocnl.training.dag_schema import _OPTIMISER_TYPES

    assert "lbiOptimizer" in _OPTIMISER_TYPES


def test_lbi_optimizer_class_definition_actually_runs() -> None:
    """End-to-end: exec the generated class + construction code against a
    real torch module and confirm a step() call performs the LBI update
    (soft-threshold shrinkage), not merely that the source text looks right."""
    torch = pytest.importorskip("torch")

    code = _dag_code("lbiOptimizer", {"lr": 1.0, "lambda_reg": 0.05, "kappa": 1.0})
    net = torch.nn.Linear(4, 2, bias=False)
    namespace = {"torch": torch, "net": net}
    exec(compile(code, "<generated lbiOptimizer>", "exec"), namespace)
    optimizer = namespace["optimizer"]
    assert isinstance(optimizer, torch.optim.Optimizer)

    # Drive one real backward + step to exercise the LBI update rule.
    out = net(torch.ones(1, 4))
    loss = out.sum()
    loss.backward()
    optimizer.step()

    (param,) = list(net.parameters())
    state = optimizer.state[param]
    assert "z" in state  # LBI's sub-gradient accumulator persisted as state
    # z = lr * grad = 1.0 * grad; shrink(z, 0.05) hard-zeroes any entry whose
    # |grad| <= 0.05 — confirm the update actually ran, not merely that the
    # optimizer constructed without error.
    z = state["z"]
    assert torch.equal(z, param.grad)
    shrunk_expected = torch.sign(z) * torch.clamp(z.abs() - 0.05, min=0.0)
    assert torch.allclose(param.data, shrunk_expected)


def test_custom_gradient_step_dag_node_emits_safe_eval_and_loop() -> None:
    code = _dag_code(
        "customGradientStep",
        {"expression": "grad * 0.5 + momentum_buffer * 0.5", "clip_value": 1.0},
    )
    assert "def _nmtk_safe_eval(expr, namespace):" in code
    assert "ast.parse(expr, mode='eval')" in code
    assert "for _gs_param in net.parameters():" in code
    assert "_nmtk_safe_eval(" in code
    assert "grad * 0.5 + momentum_buffer * 0.5" in code
    assert "_gs_param.grad.data.copy_(_gs_result_tensor)" in code
    assert "no code generator defined" not in code


def _extract_nmtk_safe_eval(code: str):
    """Pull the standalone `_nmtk_safe_eval` function source out of the
    generated `customGradientStep` code (which also contains a per-batch
    loop that references undefined names like `net`/`batch_idx` outside a
    real training context) and exec it in an isolated namespace so it can be
    called directly against adversarial input, mirroring the coverage that
    used to live in the now-deleted `safe_expr.py` security tests."""
    start = code.index("def _nmtk_safe_eval(expr, namespace):")
    end = code.index("_nmtk_gradstep_buffers = globals().setdefault")
    func_source = code[start:end]
    namespace: dict = {}
    exec(compile(func_source, "<generated _nmtk_safe_eval>", "exec"), namespace)
    return namespace["_nmtk_safe_eval"]


def test_nmtk_safe_eval_accepts_whitelisted_expression() -> None:
    code = _dag_code("customGradientStep", {"expression": "grad", "clip_value": 0.0})
    safe_eval = _extract_nmtk_safe_eval(code)
    assert safe_eval("grad * 0.5", {"grad": 4.0}) == 2.0


def test_nmtk_safe_eval_rejects_attribute_access() -> None:
    code = _dag_code("customGradientStep", {"expression": "grad", "clip_value": 0.0})
    safe_eval = _extract_nmtk_safe_eval(code)
    with pytest.raises(ValueError):
        safe_eval("grad.data", {"grad": 4.0})


def test_nmtk_safe_eval_rejects_subscript() -> None:
    code = _dag_code("customGradientStep", {"expression": "grad", "clip_value": 0.0})
    safe_eval = _extract_nmtk_safe_eval(code)
    with pytest.raises(ValueError):
        safe_eval("grad[0]", {"grad": [4.0]})


def test_nmtk_safe_eval_rejects_import_like_call() -> None:
    code = _dag_code("customGradientStep", {"expression": "grad", "clip_value": 0.0})
    safe_eval = _extract_nmtk_safe_eval(code)
    with pytest.raises((ValueError, SyntaxError)):
        safe_eval("__import__('os')", {"grad": 4.0})


def test_nmtk_safe_eval_rejects_non_whitelisted_call() -> None:
    code = _dag_code("customGradientStep", {"expression": "grad", "clip_value": 0.0})
    safe_eval = _extract_nmtk_safe_eval(code)
    with pytest.raises(ValueError):
        safe_eval("print(grad)", {"grad": 4.0})


def test_nmtk_safe_eval_rejects_string_constant() -> None:
    code = _dag_code("customGradientStep", {"expression": "grad", "clip_value": 0.0})
    safe_eval = _extract_nmtk_safe_eval(code)
    with pytest.raises(ValueError):
        safe_eval("'grad'", {"grad": 4.0})


def test_nmtk_safe_eval_rejects_bool_constant() -> None:
    code = _dag_code("customGradientStep", {"expression": "grad", "clip_value": 0.0})
    safe_eval = _extract_nmtk_safe_eval(code)
    with pytest.raises(ValueError):
        safe_eval("True", {"grad": 4.0})


def test_custom_gradient_step_is_body_node_not_setup() -> None:
    """`customGradientStep` must NOT be in any setup-type set — it needs to
    run every batch, before `optimizer.step()`, mirroring `gradientClip`."""
    from neurocnl.training.dag_schema import (
        _LOADER_TYPES,
        _OPTIMISER_TYPES,
        _SCHEDULER_TYPES,
    )

    setup_types = (
        _LOADER_TYPES
        | _OPTIMISER_TYPES
        | _SCHEDULER_TYPES
        | {
            "timeLoop",
            "earlyStopping",
        }
    )
    assert "customGradientStep" not in setup_types


def test_custom_gradient_step_placed_before_optimizer_step() -> None:
    """Mirrors gradientClip's placement: the generated per-batch loop body
    must mutate .grad before optimizer.step() is called."""
    from backend.app.routers.notebook import (
        DagNodePayload,
        PhaseDAGPayload,
        PipelineConfigPayload,
        _phase_dag_to_code,
    )

    phase = PhaseDAGPayload(
        nodes=[
            DagNodePayload(id="t1", type="dataLoader", parameters={"batch_size": 32}),
            DagNodePayload(id="t2", type="forwardPass", parameters={}),
            DagNodePayload(id="t3", type="ceCountLoss", parameters={}),
            DagNodePayload(id="t4", type="surrogateBackward", parameters={}),
            DagNodePayload(
                id="t5",
                type="customGradientStep",
                parameters={"expression": "grad", "clip_value": 0.0},
            ),
            DagNodePayload(id="t6", type="adamOptimiser", parameters={"lr": 0.001}),
        ],
        edges=[],
    )
    code = _phase_dag_to_code(phase, PipelineConfigPayload(epochs=1), "NMNIST")
    grad_step_pos = code.index("_gs_param.grad.data.copy_")
    optimizer_step_pos = code.index("optimizer.step()")
    assert grad_step_pos < optimizer_step_pos


def test_spike_domain_filter_threshold_dag_node() -> None:
    code = _dag_code(
        "spikeDomainFilter",
        {"filter_type": "threshold", "window": 3, "threshold": 2.0},
    )
    assert "_sdf_window = max(1, 3)" in code
    assert "_sdf_mask = (_sdf_rolling >= 2.0)" in code
    assert "spk_out = spk_out * _sdf_mask" in code
    assert "no code generator defined" not in code


def test_spike_domain_filter_moving_average_dag_node() -> None:
    code = _dag_code(
        "spikeDomainFilter", {"filter_type": "moving_average", "window": 5}
    )
    assert "spk_out = _sdf_rolling / _sdf_counts.reshape(_sdf_shape)" in code
    assert "max=float(5)" in code


def test_spike_domain_filter_refractory_dag_node() -> None:
    code = _dag_code("spikeDomainFilter", {"filter_type": "refractory", "window": 4})
    assert "_sdf_remaining" in code
    assert "spk_out = _sdf_out" in code
    assert "float(_sdf_window)" in code


def test_spike_domain_filter_unknown_type_is_flagged() -> None:
    with pytest.raises(ValueError, match="unsupported spikeDomainFilter"):
        _dag_code("spikeDomainFilter", {"filter_type": "bogus"})


def test_spike_domain_filter_inserted_after_forward_pass() -> None:
    """A spikeDomainFilter node wired directly after forwardPass in the DAG
    must land in the generated per-batch body, reassigning spk_out before
    any downstream loss node reads it."""
    from backend.app.routers.notebook import (
        DagNodePayload,
        PhaseDAGPayload,
        PipelineConfigPayload,
        _phase_dag_to_code,
    )

    phase = PhaseDAGPayload(
        nodes=[
            DagNodePayload(id="t1", type="dataLoader", parameters={"batch_size": 32}),
            DagNodePayload(id="t2", type="forwardPass", parameters={}),
            DagNodePayload(
                id="t3",
                type="spikeDomainFilter",
                parameters={"filter_type": "threshold", "window": 2, "threshold": 1.0},
            ),
            DagNodePayload(id="t4", type="ceCountLoss", parameters={}),
            DagNodePayload(id="t5", type="surrogateBackward", parameters={}),
            DagNodePayload(id="t6", type="adamOptimiser", parameters={"lr": 0.001}),
        ],
        edges=[],
    )
    code = _phase_dag_to_code(phase, PipelineConfigPayload(epochs=1), "NMNIST")
    assert "spk_out = spk_out * _sdf_mask" in code
    filter_pos = code.index("_sdf_mask")
    loss_pos = code.index("loss_fn = SF.ce_count_loss()")
    assert filter_pos < loss_pos
