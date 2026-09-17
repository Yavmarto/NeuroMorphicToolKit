"""Registry of per-node-type notebook codegen emitters for `_dag_node_code`.

Each function here is a mechanical extraction of one `case` arm (or group of
`|`-combined arms) from the former `_dag_node_code` match statement in
`backend.app.routers.notebook`. Bodies are copied verbatim — behavior,
strings, and comments are unchanged.

`_resolve_spike_reg_target` and `_custom_pipeline_node_code` also used to
live in `backend.app.routers.notebook` and were imported back from there via
local (in-function) imports. They have moved here instead: this is where
`_resolve_spike_reg_target` is actually called from (`_emit_l1_spike_reg`/
`_emit_l2_spike_reg`), and `dag_node_code` below is the sole consumer of a
`custom_code_resolver` callable like `_custom_pipeline_node_code`.
`notebook.py` re-exports both for compatibility, and
`notebook_dag_lowering.py` imports `_custom_pipeline_node_code` from here
directly instead of from `notebook.py`.

A few emitters still call helper functions that live in
`backend.app.routers.notebook` (e.g. `_akida_exporter_code`,
`_weight_visualizer_code`, `_attribution_visualizer_code` — extracted into
`notebook_target_codegen.py` but still re-exported from `notebook.py`).
Those are imported locally, inside the emitter functions that need them,
rather than at module scope: `notebook.py` imports `dag_node_code` from this
module during its own import phase, before any of its own functions are
defined, so a module-level import here would create a circular-import
failure. Dataset-loading helpers (`_pt_loading_code`, `_dataset_loading_code`,
`_pt_named_loading_code`, `_spike_generator_code`, `_TONIC_DATASET_CLASS`,
`_TONIC_EXTRA_CTOR_KWARGS`) have no such problem — their real home,
`notebook_dataset_codegen.py`, does not depend on `notebook.py` or this
module, so they are imported at module scope below.
"""

from __future__ import annotations

import re
from collections.abc import Callable
from pathlib import Path

from backend.app.schemas.notebook import PipelineConfigPayload
from backend.app.schemas.pipeline_dag import DagNodePayload
from backend.app.services.notebook_dataset_codegen import (
    _TONIC_DATASET_CLASS,
    _TONIC_EXTRA_CTOR_KWARGS,
    _dataset_loading_code,
    _pt_loading_code,
    _pt_named_loading_code,
    _spike_generator_code,
)


def _resolve_spike_reg_target(raw: object) -> tuple[str, str | None]:
    """Resolve a l1SpikeReg/l2SpikeReg node's `target_layer` to the tensor
    variable in scope in the generated training loop. Only `spk_out` (final
    output layer) and `mem_out` (despite the name — the stacked HIDDEN-layer
    spike train for recurrent nets, see `_generate_snntorch_code`'s
    `Net.forward`) ever exist. The Studio UI's "Target Layer (blank = all
    hidden)" field sends a raw architecture-node label (e.g. "cnl.RSynaptic"),
    which can't be resolved to a distinct variable since only one hidden
    aggregate exists; treat it (and blank) as "regularize the hidden layer"
    -> mem_out, matching the reference implementation this was ported from
    (paper/03_rnn/Braille_training_snntorch.ipynb, which regularizes
    hid_rec, not the output spikes).

    Returns (resolved_variable_name, original_value_if_fallback_else_None).
    """
    layer = str(raw).strip() if raw is not None else ""
    if not layer or layer == "mem_out":
        return "mem_out", None
    if layer == "spk_out":
        return "spk_out", None
    return "mem_out", layer


def _custom_pipeline_node_code(node: DagNodePayload) -> str | None:
    """Resolve an optional custom DAG implementation by stable component ID.

    A generated clone that does not override ``to_pipeline`` deliberately
    returns ``None`` so the built-in node implementation below remains the
    behavior-preserving fallback.
    """
    component_id = node.custom_component_id
    if not component_id:
        return None

    from nmtk_sdk.custom_node import CustomNode
    from nmtk_sdk.loader import load_custom_node

    custom_dir = Path.home() / ".nmtk" / "custom_nodes"
    for source_path in sorted(custom_dir.glob("*.py")):
        try:
            node_class = load_custom_node(source_path)
        except Exception:
            continue
        author = node_class.author or "user"
        legacy_id = "custom_" + re.sub(
            r"[^a-z0-9]+",
            "_",
            f"{author}_{node_class.name}".lower(),
        ).strip("_")
        candidate_id = getattr(node_class, "node_id", None) or legacy_id
        if candidate_id != component_id:
            continue
        if getattr(node_class, "base_pipeline_type", None) != node.type:
            raise ValueError(
                f"Custom node '{component_id}' no longer matches its {node.type} pipeline role."
            )
        if node_class.to_pipeline is CustomNode.to_pipeline:
            return None
        rendered = node_class().to_pipeline(dict(node.parameters))
        if not isinstance(rendered, str) or not rendered.strip():
            raise ValueError(
                f"Custom node '{component_id}' must return non-empty Python from to_pipeline()."
            )
        return rendered
    raise ValueError(
        f"Custom node '{component_id}' is unavailable. Add it again from the component palette."
    )


def _emit_data_loader(
    node: DagNodePayload, cfg: PipelineConfigPayload, dataset: str
) -> str | None:
    p = node.parameters
    bs = p.get("batch_size", cfg.batch_size)
    fmt = str(p.get("format", "auto") or "auto")
    if fmt.startswith("tonic_"):
        tw = int(p.get("time_window_ms", 1) or 1)
        ds_cls = _TONIC_DATASET_CLASS.get(fmt, "NMNIST")
        extra_kwargs = _TONIC_EXTRA_CTOR_KWARGS.get(ds_cls, "")
        time_window_us = tw * 1000
        # tonic ≥1.0.0 removed the `download` kwarg; the dataset auto-
        # fetches if the save_to directory does not already contain data.
        # batch_first=False (below) is not independently
        # user-configurable: it's coupled to the generated
        # model's forward() below, which assumes a fixed
        # (T, B, ...) time-first shape for every batch it
        # iterates over. Flipping batch_first here without also
        # rewriting forward()'s indexing would silently swap the
        # time and batch axes and desync the model from its data.
        return (
            "import tonic\n"
            "import tonic.transforms as transforms\n"
            "from torch.utils.data import DataLoader\n\n"
            f"_sensor_size = tonic.datasets.{ds_cls}.sensor_size\n"
            f"_frame_tf = transforms.ToFrame(sensor_size=_sensor_size, time_window={time_window_us})\n"
            f"_pad_collate = tonic.collation.PadTensors(batch_first=False)  # pad variable-length event frames\n\n"
            f"train_ds = tonic.datasets.{ds_cls}(save_to='./data', train=True,  transform=_frame_tf{extra_kwargs})\n"
            f"test_ds  = tonic.datasets.{ds_cls}(save_to='./data', train=False, transform=_frame_tf{extra_kwargs})\n\n"
            f"train_loader = DataLoader(train_ds, batch_size={bs}, shuffle=True,  num_workers=0, collate_fn=_pad_collate)\n"
            f"test_loader  = DataLoader(test_ds,  batch_size={bs}, shuffle=False, num_workers=0, collate_fn=_pad_collate)"
        )
    if fmt == "pt":
        path = str(
            p.get("dataset_path", "") or cfg.custom_dataset_path or "./dataset.pt"
        )
        shuffle = bool(p.get("shuffle", True))
        return _pt_loading_code(path, batch_size=bs, shuffle=shuffle)
    return _dataset_loading_code(
        dataset, bs, time_window_ms=int(p.get("time_window_ms", 1) or 1)
    )


def _emit_test_loader(
    node: DagNodePayload, cfg: PipelineConfigPayload, dataset: str
) -> str | None:
    p = node.parameters
    bs = int(p.get("batch_size", cfg.batch_size))
    fmt = str(p.get("format", "auto") or "auto")
    if fmt == "pt":
        # A .pt loader binds `_ds`/`train_loader`/`test_loader`, never a
        # `test_ds` dataset object — re-wrapping `test_ds` here would
        # raise NameError in the generated eval cell.
        return _pt_named_loading_code(
            str(p.get("dataset_path", "") or cfg.custom_dataset_path or "./dataset.pt"),
            batch_size=bs,
            loader_var="test_loader",
            label="test",
        )
    collate = ", collate_fn=_pad_collate" if fmt.startswith("tonic_") else ""
    # ponytail: test_ds from top-level dataset cell; re-wrap with node's batch_size
    return f"test_loader = DataLoader(test_ds, batch_size={bs}, shuffle=False, num_workers=0{collate})"


def _emit_spike_generator(
    node: DagNodePayload, cfg: PipelineConfigPayload, dataset: str
) -> str | None:
    p = node.parameters
    return _spike_generator_code(
        n_neurons=int(p.get("n_neurons", 1)),
        n_timesteps=int(p.get("n_timesteps", 100)),
        pattern=str(p.get("pattern", "isi_regular")),
        isi_period=int(p.get("isi_period", 10)),
        rate_hz=float(p.get("rate_hz", 10.0)),
        seed=int(p.get("seed", 42)),
    )


def _emit_spike_encoder(
    node: DagNodePayload, cfg: PipelineConfigPayload, dataset: str
) -> str | None:
    p = node.parameters
    encoding = p.get("encoding", "rate")
    return f"# Spike encoder: {encoding} coding (input treated as spikes)"


def _emit_time_loop(
    node: DagNodePayload, cfg: PipelineConfigPayload, dataset: str
) -> str | None:
    p = node.parameters
    steps = p.get("num_steps", 25)
    return f"num_steps = {steps}"


def _emit_state_reset(
    node: DagNodePayload, cfg: PipelineConfigPayload, dataset: str
) -> str | None:
    return (
        "# Reset network membrane potentials\n"
        "for layer in net.modules():\n"
        "    if hasattr(layer, 'reset_mem'):\n"
        "        layer.reset_mem()"
    )


def _emit_forward_pass(
    node: DagNodePayload, cfg: PipelineConfigPayload, dataset: str
) -> str | None:
    # ponytail: eval phase already wrapped in torch.no_grad() by _phase_dag_to_code
    return "spk_out, mem_out = net(data)"


def _emit_spike_recorder(
    node: DagNodePayload, cfg: PipelineConfigPayload, dataset: str
) -> str | None:
    return "# spike output (spk_out) captured from forward pass"


def _emit_membrane_recorder(
    node: DagNodePayload, cfg: PipelineConfigPayload, dataset: str
) -> str | None:
    return "# membrane potential (mem_out) captured from forward pass"


def _emit_mse_count_loss(
    node: DagNodePayload, cfg: PipelineConfigPayload, dataset: str
) -> str | None:
    p = node.parameters
    cr = p.get("correct_rate", 0.8)
    ir = p.get("incorrect_rate", 0.2)
    return (
        f"import snntorch.functional as SF\n"
        f"loss_fn = SF.mse_count_loss(correct_rate={cr}, incorrect_rate={ir})\n"
        f"loss_val = loss_fn(spk_out, targets)"
    )


def _emit_ce_count_loss(
    node: DagNodePayload, cfg: PipelineConfigPayload, dataset: str
) -> str | None:
    return (
        "import snntorch.functional as SF\n"
        "loss_fn = SF.ce_count_loss()\n"
        "loss_val = loss_fn(spk_out, targets)"
    )


def _emit_cross_entropy_loss(
    node: DagNodePayload, cfg: PipelineConfigPayload, dataset: str
) -> str | None:
    p = node.parameters
    ls = p.get("label_smoothing", 0.0)
    return (
        f"loss_fn = torch.nn.CrossEntropyLoss(label_smoothing={ls})\n"
        f"loss_val = loss_fn(spk_out.sum(0), targets)"
    )


def _emit_membrane_loss(
    node: DagNodePayload, cfg: PipelineConfigPayload, dataset: str
) -> str | None:
    return "loss_fn = torch.nn.MSELoss()\nloss_val = loss_fn(mem_out, targets.float())"


def _emit_l1_spike_reg(
    node: DagNodePayload, cfg: PipelineConfigPayload, dataset: str
) -> str | None:
    p = node.parameters
    w = p.get("weight", 1e-5)
    layer, fallback_from = _resolve_spike_reg_target(p.get("target_layer"))
    note = (
        f"# ponytail: target_layer={fallback_from!r} does not match a known "
        f"variable (spk_out/mem_out); treating as hidden layer -> mem_out\n"
        if fallback_from
        else ""
    )
    return (
        f"{note}"
        f"# L1 spike regularization: mean per-unit spike count over time and batch\n"
        f"loss_val = loss_val + {w} * torch.mean(torch.sum({layer}, dim=0))"
    )


def _emit_l2_spike_reg(
    node: DagNodePayload, cfg: PipelineConfigPayload, dataset: str
) -> str | None:
    p = node.parameters
    w = p.get("weight", 1e-5)
    layer, fallback_from = _resolve_spike_reg_target(p.get("target_layer"))
    note = (
        f"# ponytail: target_layer={fallback_from!r} does not match a known "
        f"variable (spk_out/mem_out); treating as hidden layer -> mem_out\n"
        if fallback_from
        else ""
    )
    return (
        f"{note}"
        f"# L2 spike regularization: mean squared per-sample total spike count\n"
        f"loss_val = loss_val + {w} * torch.mean(torch.sum(torch.sum({layer}, dim=0), dim=1) ** 2)"
    )


def _emit_surrogate_backward(
    node: DagNodePayload, cfg: PipelineConfigPayload, dataset: str
) -> str | None:
    # spike_grad itself is built once in the Architecture cell (see
    # _build_v2_notebook -> _phase_surrogate_backward ->
    # _generate_arch_code -> _generate_snntorch_code's
    # spike_grad_expr threading) and passed into every neuron
    # constructor there. Recreating it here, per-batch, would be
    # dead/duplicate code — only the backward call belongs in the
    # per-batch Train body.
    return "loss_val.backward()"


def _emit_bptt_backward(
    node: DagNodePayload, cfg: PipelineConfigPayload, dataset: str
) -> str | None:
    return (
        "# BPTT: accumulate loss across time steps\n"
        "total_loss = torch.zeros(1, device=data.device)\n"
        "for t in range(num_steps):\n"
        "    total_loss += loss_fn(spk_out[t], targets)\n"
        "total_loss.backward()"
    )


def _emit_adam_optimiser(
    node: DagNodePayload, cfg: PipelineConfigPayload, dataset: str
) -> str | None:
    p = node.parameters
    lr = p.get("lr", cfg.learning_rate)
    wd = p.get("weight_decay", 0.0)
    b1 = p.get("beta1", 0.9)
    b2 = p.get("beta2", 0.999)
    # ponytail: zero_grad()/step() are placed by _phase_dag_to_code's
    # training loop wrapper, not here — construction only.
    return (
        f"optimizer = torch.optim.Adam(\n"
        f"    net.parameters(), lr={lr}, weight_decay={wd},\n"
        f"    betas=({b1}, {b2})\n"
        f")"
    )


def _emit_sgd_optimiser(
    node: DagNodePayload, cfg: PipelineConfigPayload, dataset: str
) -> str | None:
    p = node.parameters
    lr = p.get("lr", 1e-2)
    mom = p.get("momentum", 0.9)
    nesterov = p.get("nesterov", False)
    return (
        f"optimizer = torch.optim.SGD(\n"
        f"    net.parameters(), lr={lr}, momentum={mom}, nesterov={nesterov}\n"
        f")"
    )


def _emit_adamw_optimiser(
    node: DagNodePayload, cfg: PipelineConfigPayload, dataset: str
) -> str | None:
    p = node.parameters
    lr = p.get("lr", cfg.learning_rate)
    wd = p.get("weight_decay", 0.01)
    return (
        f"optimizer = torch.optim.AdamW(net.parameters(), lr={lr}, weight_decay={wd})"
    )


def _emit_rmsprop_optimiser(
    node: DagNodePayload, cfg: PipelineConfigPayload, dataset: str
) -> str | None:
    p = node.parameters
    lr = p.get("lr", 1e-2)
    alpha = p.get("alpha", 0.99)
    return f"optimizer = torch.optim.RMSprop(net.parameters(), lr={lr}, alpha={alpha})"


def _emit_step_lr(
    node: DagNodePayload, cfg: PipelineConfigPayload, dataset: str
) -> str | None:
    p = node.parameters
    ss = p.get("step_size", 10)
    g = p.get("gamma", 0.1)
    return f"scheduler = torch.optim.lr_scheduler.StepLR(optimizer, step_size={ss}, gamma={g})"


def _emit_cosine_annealing_lr(
    node: DagNodePayload, cfg: PipelineConfigPayload, dataset: str
) -> str | None:
    p = node.parameters
    tm = p.get("T_max", 50)
    eta = p.get("eta_min", 0.0)
    return f"scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max={tm}, eta_min={eta})"


def _emit_exponential_lr(
    node: DagNodePayload, cfg: PipelineConfigPayload, dataset: str
) -> str | None:
    p = node.parameters
    g = p.get("gamma", 0.95)
    return f"scheduler = torch.optim.lr_scheduler.ExponentialLR(optimizer, gamma={g})"


def _emit_loss_logger(
    node: DagNodePayload, cfg: PipelineConfigPayload, dataset: str
) -> str | None:
    return "print(f'  loss: {loss_val.item():.4f}')"


def _emit_spike_rate_logger(
    node: DagNodePayload, cfg: PipelineConfigPayload, dataset: str
) -> str | None:
    return "print(f'  spike rate: {spk_out.mean().item():.4f}')"


def _emit_accuracy_metric(
    node: DagNodePayload, cfg: PipelineConfigPayload, dataset: str
) -> str | None:
    # ponytail: += so this works inside the test_loader loop emitted by _phase_dag_to_code;
    # print is emitted after the loop there, not here
    return "correct += (spk_out.sum(0).argmax(-1) == targets).sum().item()\ntotal   += targets.size(0)"


def _emit_f1_score(
    node: DagNodePayload, cfg: PipelineConfigPayload, dataset: str
) -> str | None:
    p = node.parameters
    avg = p.get("average", "macro")
    return (
        f"from sklearn.metrics import f1_score\n"
        f"preds = spk_out.sum(0).argmax(-1).cpu().numpy()\n"
        f"f1 = f1_score(targets.cpu().numpy(), preds, average='{avg}')\n"
        f"print(f'F1 ({avg}): {{f1:.4f}}')"
    )


def _emit_confusion_matrix(
    node: DagNodePayload, cfg: PipelineConfigPayload, dataset: str
) -> str | None:
    return (
        "from sklearn.metrics import confusion_matrix\n"
        "preds = spk_out.sum(0).argmax(-1).cpu().numpy()\n"
        "cm = confusion_matrix(targets.cpu().numpy(), preds)\n"
        "print('Confusion matrix:\\n', cm)"
    )


def _emit_nir_exporter(
    node: DagNodePayload, cfg: PipelineConfigPayload, dataset: str
) -> str | None:
    p = node.parameters
    fname = p.get("filename", "model.nir")
    return (
        "import dataclasses\n"
        "from pathlib import Path\n"
        "import nir\n"
        "if not Path('best_model.pt').exists():\n"
        "    raise RuntimeError('best_model.pt is missing; finish training before exporting trained NIR.')\n"
        "net.load_state_dict(torch.load('best_model.pt', map_location='cpu', weights_only=True))\n"
        "for _nir_name, _module_name in _nmtk_nir_module_names.items():\n"
        "    _nir_node = graph.nodes[_nir_name]\n"
        "    _module = getattr(net, _module_name)\n"
        "    _updates = {'weight': _module.weight.detach().cpu().numpy().copy()}\n"
        "    if isinstance(_nir_node, nir.Affine) and _module.bias is not None:\n"
        "        _updates['bias'] = _module.bias.detach().cpu().numpy().copy()\n"
        "    try:\n"
        "        graph.nodes[_nir_name] = dataclasses.replace(_nir_node, **_updates)\n"
        "    except TypeError:\n"
        "        for _field_name, _value in _updates.items():\n"
        "            setattr(_nir_node, _field_name, _value)\n"
        # Weights alone are not a runnable network. `graph` was compiled
        # from CNL, which states a neuron as a *shape*, so every LIF in
        # it has tau=0, v_threshold=0 and r=0. Writing that out gives a
        # trained .nir with real weights and blank neurons, which no
        # simulator or deploy target can run. Invert what the Leaky
        # module was built from so the file describes the network that
        # was actually trained: tau = dt/(1-beta), and the threshold
        # un-scaled by the same input_scale the build applied.
        "import numpy as _np\n"
        # Defined in the model cell. Tolerate its absence so this cell
        # still runs standalone, and so a notebook generated before the
        # map existed degrades to the old weights-only behaviour rather
        # than raising NameError.
        "for _nir_name, _spec in globals().get('_nmtk_nir_neuron_params', {}).items():\n"
        "    _nir_node = graph.nodes.get(_nir_name)\n"
        "    _module = getattr(net, _spec['module'], None)\n"
        "    if _nir_node is None or _module is None:\n"
        "        continue\n"
        "    _beta = float(_np.asarray(getattr(_module, 'beta')).reshape(-1)[0])\n"
        "    _thr = float(_np.asarray(getattr(_module, 'threshold')).reshape(-1)[0])\n"
        "    _dt = float(_spec['dt'])\n"
        "    _scale = float(_spec['input_scale']) or 1.0\n"
        "    _n = int(_spec['n'])\n"
        "    _tau = _dt / (1.0 - _beta) if 0.0 < _beta < 1.0 else _dt\n"
        "    _updates = {\n"
        "        'tau': _np.full(_n, _tau, dtype=_np.float32),\n"
        "        'v_threshold': _np.full(_n, _thr * _scale, dtype=_np.float32),\n"
        "        'r': _np.full(_n, float(_spec['r']) or 1.0, dtype=_np.float32),\n"
        "        'v_leak': _np.full(_n, float(_spec['v_leak']), dtype=_np.float32),\n"
        "    }\n"
        "    try:\n"
        "        graph.nodes[_nir_name] = dataclasses.replace(_nir_node, **_updates)\n"
        "    except TypeError:\n"
        "        for _field_name, _value in _updates.items():\n"
        "            setattr(_nir_node, _field_name, _value)\n"
        # CNL states a neuron's parameters once for the whole layer, so
        # every LIF in `graph` carries length-1 arrays. Written as-is,
        # NIR reads the layer back as one neuron wide and refuses the
        # file with "type mismatch: Input.output: [[784]] ->
        # LIF.input: [[1]]", which makes the artifact unusable for deploy.
        "from neurocnl.export.nir_shapes import broadcast_neuron_parameters\n"
        "graph = broadcast_neuron_parameters(graph)\n"
        f"nir.write('{fname}', graph)\n"
        f"print('Trained NIR graph saved to {fname}')"
    )


def _emit_akida_exporter(
    node: DagNodePayload, cfg: PipelineConfigPayload, dataset: str
) -> str | None:
    from backend.app.routers.notebook import _akida_exporter_code

    p = node.parameters
    fname = p.get("filename", "model.fbz")
    weight_bits = int(p.get("weight_bits", 4) or 4)
    if weight_bits not in (1, 2, 4, 8):
        weight_bits = 4
    max_batches = int(p.get("max_batches", 0) or 0)
    eval_samples = int(p.get("eval_samples", 2000) or 2000)
    return _akida_exporter_code(
        fname,
        weight_bits,
        max_batches,
        deploy_bundle=bool(p.get("deploy_bundle", True)),
        eval_samples=max(1, eval_samples),
    )


def _emit_weight_visualizer(
    node: DagNodePayload, cfg: PipelineConfigPayload, dataset: str
) -> str | None:
    from backend.app.routers.notebook import _weight_visualizer_code

    p = node.parameters
    layer_attr = str(p.get("layer", "fc1") or "fc1")
    n_cols = int(p.get("cols", 16) or 16)
    if n_cols < 1:
        n_cols = 16
    return _weight_visualizer_code(layer_attr, n_cols)


def _emit_attribution_visualizer(
    node: DagNodePayload, cfg: PipelineConfigPayload, dataset: str
) -> str | None:
    from backend.app.routers.notebook import _attribution_visualizer_code

    p = node.parameters
    sample_index = int(p.get("sample_index", 0) or 0)
    if sample_index < 0:
        sample_index = 0
    n_samples = int(p.get("n_samples", 50) or 50)
    if n_samples < 1:
        n_samples = 50
    sigma_scale = float(p.get("sigma_scale", 0.01) or 0.01)
    return _attribution_visualizer_code(sample_index, n_samples, sigma_scale)


def _emit_py_exporter(
    node: DagNodePayload, cfg: PipelineConfigPayload, dataset: str
) -> str | None:
    p = node.parameters
    fname = p.get("filename", "model.py")
    return f"# Python export: see {fname} in workspace folder"


def _emit_torch_script_exporter(
    node: DagNodePayload, cfg: PipelineConfigPayload, dataset: str
) -> str | None:
    return (
        "traced = torch.jit.trace(net, data)\n"
        "traced.save('model_traced.pt')\n"
        "print('TorchScript model saved to model_traced.pt')"
    )


def _emit_lava_node(
    node: DagNodePayload, cfg: PipelineConfigPayload, dataset: str
) -> str | None:
    return f"# Lava {node.type} — see Lava documentation for configuration"


def _emit_gradient_clip(
    node: DagNodePayload, cfg: PipelineConfigPayload, dataset: str
) -> str | None:
    p = node.parameters
    max_norm = p.get("max_norm", 1.0)
    return f"torch.nn.utils.clip_grad_norm_(net.parameters(), max_norm={max_norm})"


def _emit_weight_clip(
    node: DagNodePayload, cfg: PipelineConfigPayload, dataset: str
) -> str | None:
    p = node.parameters
    mn = p.get("min_weight", -1.0)
    mx = p.get("max_weight", 1.0)
    return f"with torch.no_grad():\n    for _wp in net.parameters():\n        _wp.clamp_({mn}, {mx})"


def _emit_reduce_lr_on_plateau(
    node: DagNodePayload, cfg: PipelineConfigPayload, dataset: str
) -> str | None:
    p = node.parameters
    mode = p.get("mode", "min")
    factor = p.get("factor", 0.1)
    patience = p.get("patience", 10)
    min_lr = p.get("min_lr", 0.0)
    # ponytail: the per-epoch scheduler.step(...) call is placed by
    # _phase_dag_to_code's training loop wrapper — construction only.
    return (
        f"scheduler = torch.optim.lr_scheduler.ReduceLROnPlateau(\n"
        f"    optimizer, mode='{mode}', factor={factor}, patience={patience}, min_lr={min_lr}\n"
        f")"
    )


def _emit_early_stopping(
    node: DagNodePayload, cfg: PipelineConfigPayload, dataset: str
) -> str | None:
    p = node.parameters
    patience = p.get("patience", 10)
    min_delta = p.get("min_delta", 0.0)
    # ponytail: the per-epoch check/break is placed by
    # _phase_dag_to_code's training loop wrapper — var init only.
    return (
        f"_es_best, _es_counter, _es_patience = float('inf'), 0, {patience}\n"
        f"_es_min_delta = {min_delta}"
    )


def _emit_validation_loop(
    node: DagNodePayload, cfg: PipelineConfigPayload, dataset: str
) -> str | None:
    # Epoch count is deliberately NOT read from this node's own
    # parameters — the outer pipeline `config["epochs"]` is the sole
    # source of truth for epoch count, to avoid two divergent knobs
    # for the same setting (see PipelineDagNodeType.validationLoop's
    # defaultParameters in pipeline_dag.dart, which no longer has an
    # `epochs` key at all).
    p = node.parameters
    every_n = int(p.get("every_n_epochs", 1) or 1)
    save_best = bool(p.get("save_best_checkpoint", True))
    metric = str(p.get("checkpoint_metric", "val_accuracy") or "val_accuracy")
    mode = str(p.get("checkpoint_mode", "max") or "max")
    if mode not in ("max", "min"):
        mode = "max"
    init_best = "float('-inf')" if mode == "max" else "float('inf')"
    # ponytail: the per-epoch validation pass is placed by
    # _training_phase_to_code's epoch_tail wrapper — var init only.
    return (
        f"_vl_every_n_epochs = {every_n}\n"
        f"_vl_save_best_checkpoint = {save_best}\n"
        f"_vl_checkpoint_metric = {metric!r}\n"
        f"_vl_checkpoint_mode = {mode!r}\n"
        f"_vl_best = {init_best}"
    )


def _emit_spike_count_metric(
    node: DagNodePayload, cfg: PipelineConfigPayload, dataset: str
) -> str | None:
    return (
        "mean_spike_count = spk_out.sum(0).float().mean().item()\n"
        "print(f'Mean spike count (output): {mean_spike_count:.4f} spk/neuron/sample')"
    )


def _emit_latency_metric(
    node: DagNodePayload, cfg: PipelineConfigPayload, dataset: str
) -> str | None:
    p = node.parameters
    default_lat = p.get("default_latency", -1)
    return (
        "# Time-to-first-spike (TTFS) classification\n"
        "_no_spike = spk_out.sum(0) == 0  # (B, C)\n"
        "_first_spk = spk_out.float().argmax(0).clone()  # (B, C)\n"
        f"_first_spk[_no_spike] = {default_lat}  # sentinel for non-firing neurons\n"
        "_preds_ttfs = _first_spk.argmin(1)\n"
        "ttfs_acc = (_preds_ttfs == targets).float().mean().item()\n"
        "print(f'TTFS Accuracy: {ttfs_acc:.2%}')"
    )


def _emit_lbi_optimizer(
    node: DagNodePayload, cfg: PipelineConfigPayload, dataset: str
) -> str | None:
    p = node.parameters
    lr = p.get("lr", 0.001)
    lambda_reg = p.get("lambda_reg", 0.01)
    kappa = p.get("kappa", 10.0)
    # ponytail: self-contained class definition, embedded as literal
    # source (not imported from neurocnl.training.executors, which a
    # generated/exported notebook must not depend on) — ported
    # verbatim from lbi_optimizer.py's LinearizedBregmanOptimizer.
    # zero_grad()/step() are placed by _training_phase_to_code's
    # training loop wrapper, not here — class + construction only.
    return (
        "class LinearizedBregmanOptimizer(torch.optim.Optimizer):\n"
        '    """Linearized Bregman Iteration (LBI): a sparsity-\n'
        "    promoting alternative to plain gradient descent. Accumulates\n"
        "    the gradient into an auxiliary sub-gradient sum `z`, then\n"
        "    re-derives the parameter from `z` via soft-thresholding\n"
        "    (shrinkage) on every step: z += lr*grad; param = kappa *\n"
        "    shrink(z, lambda_reg), where shrink(z, l) = sign(z) *\n"
        "    max(|z| - l, 0).\n"
        '    """\n'
        "\n"
        "    def __init__(self, params, lr=0.01, lambda_reg=0.01, kappa=1.0):\n"
        "        defaults = {'lr': lr, 'lambda_reg': lambda_reg, 'kappa': kappa}\n"
        "        super().__init__(params, defaults)\n"
        "\n"
        "    @torch.no_grad()\n"
        "    def step(self, closure=None):\n"
        "        loss = None\n"
        "        if closure is not None:\n"
        "            with torch.enable_grad():\n"
        "                loss = closure()\n"
        "        for group in self.param_groups:\n"
        "            lr = group['lr']\n"
        "            lambda_reg = group['lambda_reg']\n"
        "            kappa = group['kappa']\n"
        "            for param in group['params']:\n"
        "                if param.grad is None:\n"
        "                    continue\n"
        "                grad = param.grad\n"
        "                state = self.state[param]\n"
        "                if 'z' not in state:\n"
        "                    state['z'] = torch.zeros_like(param)\n"
        "                z = state['z']\n"
        "                z.add_(grad, alpha=lr)\n"
        "                shrunk = torch.sign(z) * torch.clamp(z.abs() - lambda_reg, min=0.0)\n"
        "                param.copy_(kappa * shrunk)\n"
        "        return loss\n"
        "\n"
        "optimizer = LinearizedBregmanOptimizer(\n"
        f"    net.parameters(), lr={lr}, lambda_reg={lambda_reg}, kappa={kappa}\n"
        ")"
    )


def _emit_custom_gradient_step(
    node: DagNodePayload, cfg: PipelineConfigPayload, dataset: str
) -> str | None:
    p = node.parameters
    expression = str(p.get("expression", "grad"))
    clip_value = float(p.get("clip_value", 0.0) or 0.0)
    lr = p.get("lr", cfg.learning_rate)
    # ponytail: safe-expression evaluator embedded as literal source
    # (ported from safe_expr.py's whitelisted-AST logic into a plain
    # function, since a generated notebook must not import from
    # neurocnl.training.safe_expr) followed by a per-batch loop over
    # net.parameters() that mutates .grad in place *before*
    # optimizer.step() is called (this node is a body node — not in
    # _OPTIMISER_TYPES/_SCHEDULER_TYPES/etc, so classify_phase puts it
    # in body_nodes, which _training_phase_to_code always places
    # before the "optimizer.step()" line, mirroring gradientClip's
    # placement).
    return (
        "def _nmtk_safe_eval(expr, namespace):\n"
        '    """Whitelisted-AST expression evaluator for customGradientStep.\n'
        "    Never calls eval()/exec() on the raw string — only\n"
        "    ast.parse(mode='eval') plus a hand-walked, explicitly\n"
        "    whitelisted subset of node types.\n"
        '    """\n'
        "    import ast\n"
        "\n"
        "    allowed_names = {'grad', 'param', 'momentum_buffer', 'step', 'lr'}\n"
        "    allowed_funcs = {'clamp', 'sign', 'abs', 'sqrt'}\n"
        "\n"
        "    def _duck_clamp(v, lo, hi):\n"
        "        return v.clamp(lo, hi) if hasattr(v, 'clamp') else max(lo, min(hi, v))\n"
        "\n"
        "    def _duck_sign(v):\n"
        "        if hasattr(v, 'sign'):\n"
        "            return v.sign()\n"
        "        return 1.0 if v > 0 else (-1.0 if v < 0 else 0.0)\n"
        "\n"
        "    def _duck_abs(v):\n"
        "        return v.abs() if hasattr(v, 'abs') else abs(v)\n"
        "\n"
        "    def _duck_sqrt(v):\n"
        "        import math\n"
        "        return v.sqrt() if hasattr(v, 'sqrt') else math.sqrt(v)\n"
        "\n"
        "    func_impls = {\n"
        "        'clamp': _duck_clamp, 'sign': _duck_sign,\n"
        "        'abs': _duck_abs, 'sqrt': _duck_sqrt,\n"
        "    }\n"
        "\n"
        "    def _eval(node):\n"
        "        if isinstance(node, ast.BinOp):\n"
        "            if not isinstance(node.op, (ast.Add, ast.Sub, ast.Mult, ast.Div, ast.Pow)):\n"
        "                raise ValueError(f'disallowed binary operator: {type(node.op).__name__}')\n"
        "            left, right = _eval(node.left), _eval(node.right)\n"
        "            if isinstance(node.op, ast.Add):\n"
        "                return left + right\n"
        "            if isinstance(node.op, ast.Sub):\n"
        "                return left - right\n"
        "            if isinstance(node.op, ast.Mult):\n"
        "                return left * right\n"
        "            if isinstance(node.op, ast.Div):\n"
        "                return left / right\n"
        "            return left ** right\n"
        "        if isinstance(node, ast.UnaryOp):\n"
        "            if not isinstance(node.op, (ast.UAdd, ast.USub)):\n"
        "                raise ValueError(f'disallowed unary operator: {type(node.op).__name__}')\n"
        "            operand = _eval(node.operand)\n"
        "            return -operand if isinstance(node.op, ast.USub) else +operand\n"
        "        if isinstance(node, ast.Name):\n"
        "            if node.id not in allowed_names or node.id not in namespace:\n"
        "                raise ValueError(f'name not permitted in safe expressions: {node.id!r}')\n"
        "            return namespace[node.id]\n"
        "        if isinstance(node, ast.Constant):\n"
        "            value = node.value\n"
        "            if isinstance(value, bool) or not isinstance(value, (int, float)):\n"
        "                raise ValueError(f'disallowed constant: {value!r}')\n"
        "            return value\n"
        "        if isinstance(node, ast.Call):\n"
        "            if not isinstance(node.func, ast.Name) or node.func.id not in allowed_funcs:\n"
        "                raise ValueError('only whitelisted bare-name function calls are permitted')\n"
        "            if node.keywords:\n"
        "                raise ValueError('keyword arguments are not permitted in safe expressions')\n"
        "            args = [_eval(a) for a in node.args]\n"
        "            return func_impls[node.func.id](*args)\n"
        "        raise ValueError(f'disallowed expression construct: {type(node).__name__}')\n"
        "\n"
        "    tree = ast.parse(expr, mode='eval')\n"
        "    return _eval(tree.body)\n"
        "\n"
        "_nmtk_gradstep_buffers = globals().setdefault('_nmtk_gradstep_buffers', {})\n"
        "for _gs_param in net.parameters():\n"
        "    if _gs_param.grad is None:\n"
        "        continue\n"
        "    _gs_key = id(_gs_param)\n"
        "    _gs_momentum = _nmtk_gradstep_buffers.get(_gs_key)\n"
        "    if _gs_momentum is None:\n"
        "        _gs_momentum = torch.zeros_like(_gs_param)\n"
        "        _nmtk_gradstep_buffers[_gs_key] = _gs_momentum\n"
        "    _gs_namespace = {\n"
        "        'grad': _gs_param.grad,\n"
        "        'param': _gs_param.data,\n"
        "        'momentum_buffer': _gs_momentum,\n"
        "        'step': batch_idx,\n"
        f"        'lr': {lr},\n"
        "    }\n"
        f"    _gs_result = _nmtk_safe_eval({expression!r}, _gs_namespace)\n"
        f"    if {clip_value} > 0:\n"
        "        if hasattr(_gs_result, 'clamp'):\n"
        f"            _gs_result = _gs_result.clamp(-{clip_value}, {clip_value})\n"
        "        else:\n"
        f"            _gs_result = max(-{clip_value}, min({clip_value}, _gs_result))\n"
        "    if torch.is_tensor(_gs_result):\n"
        "        _gs_result_tensor = _gs_result.detach()\n"
        "    else:\n"
        "        _gs_result_tensor = torch.full_like(_gs_param.grad, float(_gs_result))\n"
        "    _gs_momentum.copy_(_gs_result_tensor)\n"
        "    _gs_param.grad.data.copy_(_gs_result_tensor)"
    )


def _emit_spike_domain_filter(
    node: DagNodePayload, cfg: PipelineConfigPayload, dataset: str
) -> str | None:
    p = node.parameters
    filter_type = str(p.get("filter_type", "threshold") or "threshold")
    window = int(p.get("window", 1) or 1)
    threshold = float(p.get("threshold", 1.0))
    # ponytail: inline torch code (no helper import) — ported from
    # snntorch_executor.py's _spike_domain_*_filter helpers. Operates
    # on the fixed `spk_out` convention every other node in this
    # match uses (there is no per-port variable tracking in this
    # codegen — nodes read/write the same handful of fixed names),
    # reassigning `spk_out` so a downstream loss/metric node wired
    # after this one in the DAG sees the filtered tensor.
    rolling_sum_code = (
        f"_sdf_window = max(1, {window})\n"
        "_sdf_csum = torch.cumsum(spk_out, dim=0)\n"
        "if _sdf_window >= spk_out.shape[0]:\n"
        "    _sdf_rolling = _sdf_csum\n"
        "else:\n"
        "    _sdf_shifted = torch.zeros_like(_sdf_csum)\n"
        "    _sdf_shifted[_sdf_window:] = _sdf_csum[:-_sdf_window]\n"
        "    _sdf_rolling = _sdf_csum - _sdf_shifted"
    )
    if filter_type == "threshold":
        return (
            rolling_sum_code + "\n"
            f"_sdf_mask = (_sdf_rolling >= {threshold}).to(spk_out.dtype)\n"
            "spk_out = spk_out * _sdf_mask"
        )
    if filter_type == "moving_average":
        return (
            rolling_sum_code + "\n"
            "_sdf_timesteps = spk_out.shape[0]\n"
            "_sdf_counts = torch.clamp(\n"
            "    torch.arange(1, _sdf_timesteps + 1, device=spk_out.device, dtype=spk_out.dtype),\n"
            f"    max=float({window}),\n"
            ")\n"
            "_sdf_shape = [_sdf_timesteps] + [1] * (spk_out.dim() - 1)\n"
            "spk_out = _sdf_rolling / _sdf_counts.reshape(_sdf_shape)"
        )
    if filter_type == "refractory":
        return (
            f"_sdf_window = max(1, {window})\n"
            "_sdf_timesteps = spk_out.shape[0]\n"
            "_sdf_out = torch.zeros_like(spk_out)\n"
            "_sdf_remaining = torch.zeros_like(spk_out[0])\n"
            "for _sdf_t in range(_sdf_timesteps):\n"
            "    _sdf_allowed = (_sdf_remaining <= 0).to(spk_out.dtype)\n"
            "    _sdf_fired = spk_out[_sdf_t] * _sdf_allowed\n"
            "    _sdf_out[_sdf_t] = _sdf_fired\n"
            "    _sdf_remaining = torch.clamp(_sdf_remaining - 1, min=0)\n"
            "    _sdf_remaining = torch.where(\n"
            "        _sdf_fired > 0, torch.full_like(_sdf_remaining, float(_sdf_window)), _sdf_remaining\n"
            "    )\n"
            "spk_out = _sdf_out"
        )
    raise ValueError(
        f"Pipeline node '{node.id}' has unsupported spikeDomainFilter "
        f"filter_type {filter_type!r}; expected threshold, moving_average, "
        "or refractory."
    )


_NODE_EMITTERS: dict[
    str, Callable[[DagNodePayload, PipelineConfigPayload, str], str | None]
] = {
    "dataLoader": _emit_data_loader,
    "testLoader": _emit_test_loader,
    "spikeGenerator": _emit_spike_generator,
    "spikeEncoder": _emit_spike_encoder,
    "timeLoop": _emit_time_loop,
    "stateReset": _emit_state_reset,
    "forwardPass": _emit_forward_pass,
    "spikeRecorder": _emit_spike_recorder,
    "membraneRecorder": _emit_membrane_recorder,
    "mseCountLoss": _emit_mse_count_loss,
    "ceCountLoss": _emit_ce_count_loss,
    "crossEntropyLoss": _emit_cross_entropy_loss,
    "membraneLoss": _emit_membrane_loss,
    "l1SpikeReg": _emit_l1_spike_reg,
    "l2SpikeReg": _emit_l2_spike_reg,
    "surrogateBackward": _emit_surrogate_backward,
    "bpttBackward": _emit_bptt_backward,
    "adamOptimiser": _emit_adam_optimiser,
    "sgdOptimiser": _emit_sgd_optimiser,
    "adamwOptimiser": _emit_adamw_optimiser,
    "rmspropOptimiser": _emit_rmsprop_optimiser,
    "stepLR": _emit_step_lr,
    "cosineAnnealingLR": _emit_cosine_annealing_lr,
    "exponentialLR": _emit_exponential_lr,
    "lossLogger": _emit_loss_logger,
    "spikeRateLogger": _emit_spike_rate_logger,
    "accuracyMetric": _emit_accuracy_metric,
    "f1Score": _emit_f1_score,
    "confusionMatrix": _emit_confusion_matrix,
    "nirExporter": _emit_nir_exporter,
    "akidaExporter": _emit_akida_exporter,
    "weightVisualizer": _emit_weight_visualizer,
    "attributionVisualizer": _emit_attribution_visualizer,
    "pyExporter": _emit_py_exporter,
    "torchScriptExporter": _emit_torch_script_exporter,
    "lavaProcessGraph": _emit_lava_node,
    "lavaSim": _emit_lava_node,
    "lavaHwConfig": _emit_lava_node,
    "loihiExporter": _emit_lava_node,
    "gradientClip": _emit_gradient_clip,
    "weightClip": _emit_weight_clip,
    "reduceLROnPlateau": _emit_reduce_lr_on_plateau,
    "earlyStopping": _emit_early_stopping,
    "validationLoop": _emit_validation_loop,
    "spikeCountMetric": _emit_spike_count_metric,
    "latencyMetric": _emit_latency_metric,
    "lbiOptimizer": _emit_lbi_optimizer,
    "customGradientStep": _emit_custom_gradient_step,
    "spikeDomainFilter": _emit_spike_domain_filter,
}


def dag_node_code(
    node: DagNodePayload,
    cfg: PipelineConfigPayload,
    dataset: str,
    *,
    custom_code_resolver: Callable[[DagNodePayload], str | None] | None = None,
) -> str | None:
    """Dispatch a pipeline DAG node to its registered notebook-codegen emitter."""
    if custom_code_resolver is not None:
        custom_code = custom_code_resolver(node)
        if custom_code is not None:
            return custom_code
    emitter = _NODE_EMITTERS.get(node.type)
    if emitter is not None:
        return emitter(node, cfg, dataset)
    raise ValueError(
        f"Pipeline node '{node.id}' uses unsupported type {node.type!r}; "
        "no notebook emitter is registered for it."
    )
