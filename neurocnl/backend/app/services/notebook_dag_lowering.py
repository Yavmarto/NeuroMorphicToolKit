"""Training-DAG-to-code lowering for `backend.app.routers.notebook`.

Mechanical extraction of the phase-DAG-to-notebook-cell lowering logic that
used to live in `backend.app.routers.notebook` between the `_dag_node_code`
compatibility wrapper and `_TONIC_DATASET_CLASS`, plus `_val_loader_code`
(originally defined between `_pt_named_loading_code` and
`_spike_generator_code`). Bodies are copied verbatim — behavior, strings, and
comments are unchanged.

Unlike `notebook_dag_node_emitters.py` (one public `dag_node_code` entry
point with private internals), this module keeps its five externally-called
functions under their original private (leading-underscore) names —
`_phase_dag_to_code`, `_phase_has_eval_loop`, `_phase_has_training_loop`,
`_effective_notebook_dataset`, `_phase_surrogate_backward` — mirroring
`notebook_graph_analysis.py`'s convention instead. With five distinct call
sites in `notebook.py` (rather than one dispatch point), introducing a single
public wrapper name per function would just be a rename with no functional
benefit, and would break the existing test suite's direct
`from backend.app.routers.notebook import _phase_dag_to_code`-style imports
(which are re-exported from `notebook.py` via compatibility imports) for no
gain.

Calls into `_dag_node_code` (the compatibility wrapper still in
`notebook.py`) go instead directly to `dag_node_code` from
`notebook_dag_node_emitters`, passing `custom_code_resolver=_custom_pipeline_node_code`
exactly like `notebook.py`'s own wrapper does. `_custom_pipeline_node_code`
and `_pt_named_loading_code` still live in `notebook.py` and are imported
locally, inside the functions that need them, rather than at module scope:
`notebook.py` imports from this module at its own top level, so a
module-level import back into `notebook.py` here would create a circular
import.
"""

from __future__ import annotations

from backend.app.schemas.notebook import PipelineConfigPayload
from backend.app.schemas.pipeline_dag import (
    _LOADER_TYPES,
    _LOSS_TYPES,
    _OPTIMISER_TYPES,
    _SCHEDULER_TYPES,
    DagEdgePayload,
    DagNodePayload,
    PhaseDAGPayload,
    PipelinePhasesPayload,
)
from backend.app.services.notebook_dag_node_emitters import dag_node_code
from neurocnl.training.dag_topology import classify_phase
from neurocnl.training.dag_topology import topo_sort_nodes as _topo_sort

_METRIC_TYPES = {
    "accuracyMetric",
    "f1Score",
    "confusionMatrix",
    "ttfsLatency",
    "traceMetric",
}


def _phase_loader_dataset(phase: PhaseDAGPayload) -> str:
    """Return the concrete dataset identity implied by the phase's loader nodes."""
    for node in _topo_sort(phase.nodes, phase.edges):
        if node.type not in {"dataLoader", "testLoader"}:
            continue
        fmt = str(node.parameters.get("format", "") or "")
        if fmt.startswith("tonic_"):
            return fmt
        if fmt == "pt":
            return "custom"
    return ""


def _phase_surrogate_backward(phase: PhaseDAGPayload) -> DagNodePayload | None:
    """Return the phase's `surrogateBackward` node, if any (first in DAG order)."""
    for node in _topo_sort(phase.nodes, phase.edges):
        if node.type == "surrogateBackward":
            return node
    return None


def _phase_loader_dataset_path(phase: PhaseDAGPayload) -> str:
    """Return the `dataset_path` of the phase's first `format=pt` loader node."""
    for node in _topo_sort(phase.nodes, phase.edges):
        if node.type not in {"dataLoader", "testLoader"}:
            continue
        fmt = str(node.parameters.get("format", "") or "")
        if fmt == "pt":
            return str(node.parameters.get("dataset_path", "") or "")
    return ""


def _effective_notebook_dataset(
    cfg: PipelineConfigPayload, pipeline_phases: PipelinePhasesPayload
) -> str:
    """Prefer executable Data Loader node provenance over workspace selection."""
    return (
        _phase_loader_dataset(pipeline_phases.eval)
        or _phase_loader_dataset(pipeline_phases.train)
        or cfg.dataset
    )


def _phase_has_eval_loop(phase: PhaseDAGPayload) -> bool:
    node_types = {n.type for n in phase.nodes}
    return bool(node_types & _METRIC_TYPES) and bool(node_types & _LOADER_TYPES)


def _phase_has_training_loop(phase: PhaseDAGPayload) -> bool:
    """True when the phase has a real optimiser-driven training loop.

    Weights compiled from CNL are always placeholders (the NIR-to-CNL
    renderer drops real tensor values), but a phase with an optimiser and a
    loader will genuinely train them via backprop when the notebook runs —
    that's not the "missing/expired NIR import" case the placeholder-weight
    warning and eval guard exist for.
    """
    node_types = {n.type for n in phase.nodes}
    return bool(node_types & _OPTIMISER_TYPES) and bool(node_types & _LOADER_TYPES)


# How often the training loop captures a real per-neuron activity sample,
# in addition to always capturing epoch 1 and the final epoch regardless of
# cadence. No config knob yet on PipelineConfigPayload for this — a constant
# keeps the surface area minimal until the frontend epoch-scrubber needs to
# tune it per-run.
_ACTIVITY_CAPTURE_CADENCE_EPOCHS = 5


def _training_phase_to_code(
    ordered: list[DagNodePayload],
    cfg: PipelineConfigPayload,
    dataset: str,
    edges: list[DagEdgePayload] | None = None,
) -> str:
    """Training phase — real per-epoch, per-batch loop.

    Loader/optimiser/scheduler/early-stopping/validationLoop nodes are
    setup-only (run once, outside the loop). Everything else runs once per
    batch. The loop wrapper itself (not individual node codegens) places
    `zero_grad`/`step`/scheduler/early-stop/validation/progress calls at the
    correct positions — the node codegens for those types return
    construction/init code only.
    """
    from backend.app.routers.notebook import _custom_pipeline_node_code

    def _dag_node_code(
        node: DagNodePayload, cfg: PipelineConfigPayload, dataset: str
    ) -> str | None:
        return dag_node_code(node, cfg, dataset, custom_code_resolver=_custom_pipeline_node_code)

    edges = edges or []
    node_types = {n.type for n in ordered}
    node_by_id = {n.id: n for n in ordered}
    classification = classify_phase(ordered)
    weight_clip_nodes = [n for n in ordered if n.type == "weightClip"]
    body_nodes = classification.body_nodes
    post_training_nodes = classification.post_training_nodes

    val_loop_node = next((n for n in ordered if n.type == "validationLoop"), None)
    val_loader_node: DagNodePayload | None = None
    if val_loop_node is not None:
        val_edge = next(
            (
                e
                for e in edges
                if e.target_node_id == val_loop_node.id and e.target_port == "val_data"
            ),
            None,
        )
        val_loader_node = node_by_id.get(val_edge.source_node_id) if val_edge is not None else None
        save_best = bool(val_loop_node.parameters.get("save_best_checkpoint", True))
        if save_best and val_loader_node is None:
            raise ValueError(
                "validationLoop.save_best_checkpoint is enabled but no loader is "
                "wired to its val_data port — connect a Data Loader (or Test "
                "Loader) node to validationLoop's val_data port, or disable "
                "save_best_checkpoint, then regenerate this notebook."
            )

    # A loader wired to validationLoop's val_data port needs one of two
    # treatments, depending on whether it also feeds the main pipeline:
    #
    #   shared   — one dataLoader with two output wires (data to spikeEncoder,
    #              data to val_data). Its generic codegen must still run, or
    #              nothing binds `train_loader`/`test_loader` from this phase's
    #              dataset and the training loop falls back on whichever
    #              `train_loader` a still-in-scope earlier cell happened to
    #              define (e.g. the Eval phase's).
    #   val-only — a second dataLoader pointing at a separate validation file,
    #              wired *only* to val_data. Its generic codegen would re-bind
    #              `train_loader`/`test_loader` (`_pt_loading_code` always does)
    #              and, emitted after the training loader, silently overwrite
    #              the training set with the validation set — training on the
    #              val split and then "validating" on the same samples.
    #
    # So: skip the generic pass for a val-only loader, but only when another
    # loader in this phase will bind `train_loader` — a canvas whose sole
    # loader hangs off val_data is already broken, and dropping its codegen
    # too would turn that into a NameError instead of today's behaviour.
    _val_only_loader = (
        val_loader_node is not None
        and val_loop_node is not None
        and not any(
            e.source_node_id == val_loader_node.id
            and not (e.target_node_id == val_loop_node.id and e.target_port == "val_data")
            for e in edges
        )
        and any(
            n.type in _LOADER_TYPES and n.id != val_loader_node.id
            for n in classification.setup_nodes
        )
    )
    # A `.pt` Data Loader binds `test_loader` as well as `train_loader` (see
    # `_pt_loading_code`), as a fallback for pipelines with no explicit test
    # set. An explicit Test Loader node must therefore be emitted *after* every
    # other loader, or whichever happens to come later in the canvas wins --
    # and when the Data Loader wins, `test_loader` silently becomes the
    # training split. That is invisible in the notebook and inflates every
    # number computed from it, including the Akida Exporter's accuracy and the
    # evaluation set it ships to the card.
    _test_loader_nodes = [n for n in classification.setup_nodes if n.type == "testLoader"]
    setup_parts = [
        _dag_node_code(n, cfg, dataset)
        for n in classification.setup_nodes
        if n.type != "testLoader" and not (_val_only_loader and n.id == val_loader_node.id)
    ]
    setup_parts.extend(_dag_node_code(n, cfg, dataset) for n in _test_loader_nodes)
    if val_loader_node is not None:
        setup_parts.append(_val_loader_code(val_loader_node, cfg))
    elif val_loop_node is not None:
        setup_parts.append(
            "# validationLoop has no val_data input wired — connect a Data Loader "
            "(or Test Loader) node to its val_data port, then regenerate this "
            "notebook, to enable real per-epoch validation."
        )
    body_snippets = [_dag_node_code(n, cfg, dataset) for n in body_nodes]
    body = "\n\n".join(s for s in body_snippets if s)

    has_optimiser = bool(node_types & _OPTIMISER_TYPES)
    has_loss = bool(node_types & _LOSS_TYPES)
    has_scheduler = bool(node_types & _SCHEDULER_TYPES)
    is_plateau = "reduceLROnPlateau" in node_types
    has_early_stop = "earlyStopping" in node_types
    has_val_loop = val_loop_node is not None and val_loader_node is not None

    # Per-epoch activity capture piggybacks on batch 0's forward pass — the
    # training loop already calls net(data) every batch, so arming
    # net._capture_activity here costs nothing extra on non-capture epochs
    # (the gate lives inside forward(), see _capture_activity in the Net
    # codegen) and adds no extra forward pass on capture epochs either, only
    # the zip/base64 packaging done once capture is armed.
    batch_lines: list[str] = [
        "if _capture_this_epoch and batch_idx == 0:",
        "    net._capture_activity = True",
    ]
    if has_optimiser:
        batch_lines.append("optimizer.zero_grad()")
    batch_lines.extend(body.splitlines())
    if has_optimiser:
        batch_lines.append("optimizer.step()")
    for n in weight_clip_nodes:
        # ponytail: weightClip always runs immediately post-step regardless
        # of where it's wired in the graph — clamping only makes sense after
        # the weight update.
        clip_code = _dag_node_code(n, cfg, dataset)
        if clip_code:
            batch_lines.extend(clip_code.splitlines())
    if has_loss:
        batch_lines.append("_epoch_loss_sum += loss_val.item(); _epoch_batches += 1")
    # ponytail: jupyter worker kills cells after 30 min without iopub output;
    # full N-MNIST epochs can exceed that — heartbeat every 100 batches.
    batch_lines += [
        "if batch_idx % 100 == 0:",
        f"    print('[nmtk] epoch {{epoch + 1}}/{cfg.epochs} batch {{batch_idx}}', flush=True)",
    ]
    batch_lines += [
        "if _capture_this_epoch and batch_idx == 0:",
        "    net._capture_activity = False",
        "    import io, zipfile, base64",
        "    _activity_buf = io.BytesIO()",
        "    with zipfile.ZipFile(_activity_buf, 'w') as _activity_zf:",
        "        for _act_k, _act_arr in getattr(net, '_layer_activity', {}).items():",
        "            _npy_buf = io.BytesIO()",
        "            np.save(_npy_buf, _act_arr)",
        "            _activity_zf.writestr(f'{_act_k}_spikes.npy', _npy_buf.getvalue())",
        "    _nmtk_emit_activity(",
        "        epoch + 1, base64.b64encode(_activity_buf.getvalue()).decode('ascii')",
        "    )",
    ]
    batch_indented = "\n".join("        " + ln for ln in batch_lines if ln)

    # layer_spike_rates (net._layer_rates) reflects only the epoch's final
    # batch, same ceiling as the eval-path fix — now one entry per spiking
    # layer, not just the network's final output.
    epoch_tail: list[str] = []
    if has_loss:
        epoch_tail.append("avg_loss = _epoch_loss_sum / _epoch_batches if _epoch_batches else 0.0")
    if has_scheduler:
        if is_plateau and has_loss:
            epoch_tail.append("scheduler.step(avg_loss)")
        elif not is_plateau:
            epoch_tail.append("scheduler.step()")
    epoch_tail.append(
        "_nmtk_emit(\n"
        "    epoch=epoch + 1,\n"
        f"    total={cfg.epochs},\n"
        f"    loss={'avg_loss' if has_loss else '0.0'},\n"
        "    accuracy=None,\n"
        "    layer_rates=net._layer_rates,\n"
        "    phase='train',\n"
        ")"
    )
    if has_val_loop:
        val_lines = [
            "if (epoch + 1) % _vl_every_n_epochs == 0:",
            "    net.eval()",
            "    _vl_correct = 0",
            "    _vl_total = 0",
        ]
        if has_loss:
            val_lines += ["    _vl_loss_sum = 0.0", "    _vl_batches = 0"]
        val_lines += [
            "    with torch.no_grad():",
            "        for _vl_data, _vl_targets in val_loader:",
            "            _vl_spk_out, _vl_mem_out = net(_vl_data)",
        ]
        if has_loss:
            # Mirror the training loop's own per-loss-type input shape
            # (`_dag_node_code`'s crossEntropyLoss/membraneLoss/*CountLoss
            # cases): crossEntropyLoss needs spikes reduced over time into
            # (B,C) logits; membraneLoss compares membrane trace, not spikes;
            # the two count-losses (SF.mse_count_loss/ce_count_loss) operate
            # on the raw (T,B,C) spike train directly.
            if "crossEntropyLoss" in node_types:
                val_loss_call = "loss_fn(_vl_spk_out.sum(0), _vl_targets)"
            elif "membraneLoss" in node_types:
                val_loss_call = "loss_fn(_vl_mem_out, _vl_targets.float())"
            else:
                val_loss_call = "loss_fn(_vl_spk_out, _vl_targets)"
            val_lines.append(
                f"            _vl_loss_sum += {val_loss_call}.item(); _vl_batches += 1"
            )
        val_lines += [
            "            _vl_correct += (_vl_spk_out.sum(0).argmax(-1) == "
            "_vl_targets).sum().item()",
            "            _vl_total += _vl_targets.size(0)",
            (
                "    val_loss = _vl_loss_sum / _vl_batches if _vl_batches else 0.0"
                if has_loss
                else "    val_loss = None"
            ),
            "    val_accuracy = _vl_correct / _vl_total if _vl_total else 0.0",
            "    _nmtk_emit(",
            "        epoch=epoch + 1,",
            f"        total={cfg.epochs},",
            "        loss=(val_loss if val_loss is not None else 0.0),",
            "        accuracy=val_accuracy,",
            "        layer_rates=net._layer_rates,",
            "        phase='val',",
            "    )",
            "    _vl_metric_value = (",
            "        val_accuracy if _vl_checkpoint_metric == 'val_accuracy'",
            "        else (val_loss if val_loss is not None else val_accuracy)",
            "    )",
            "    _vl_improved = (",
            "        _vl_metric_value >= _vl_best if _vl_checkpoint_mode == 'max'",
            "        else _vl_metric_value <= _vl_best",
            "    )",
            "    if _vl_improved:",
            "        _vl_best = _vl_metric_value",
            "        if _vl_save_best_checkpoint:",
            "            torch.save(net.state_dict(), 'best_model.pt')",
            "    net.train()",
        ]
        if has_early_stop and has_loss:
            # Early stopping now monitors real held-out validation loss
            # (rather than training loss) whenever a validationLoop node
            # with a wired val_data loader is present.
            val_lines += [
                "    if val_loss < _es_best - _es_min_delta:",
                "        _es_best = val_loss; _es_counter = 0",
                "    else:",
                "        _es_counter += 1",
                "    if _es_counter >= _es_patience:",
                "        break",
            ]
        epoch_tail += val_lines
    elif has_early_stop and has_loss:
        epoch_tail += [
            "if avg_loss < _es_best - _es_min_delta:",
            "    _es_best = avg_loss; _es_counter = 0",
            "else:",
            "    _es_counter += 1",
            "if _es_counter >= _es_patience:",
            "    break",
        ]
    epoch_tail_indented = "\n".join("    " + sub for ln in epoch_tail for sub in ln.splitlines())

    lines = [s for s in setup_parts if s]
    lines.append("net.train()")
    lines.append(f"for epoch in range({cfg.epochs}):")
    # Always capture epoch 1 and the final epoch; every Nth epoch in between
    # (see _ACTIVITY_CAPTURE_CADENCE_EPOCHS) so the frontend epoch-scrubber
    # has more than a single one-shot activity sample to page through.
    lines.append(
        "    _capture_this_epoch = ("
        "epoch == 0 or epoch == "
        f"{cfg.epochs} - 1 or (epoch + 1) % {_ACTIVITY_CAPTURE_CADENCE_EPOCHS} == 0"
        ")"
    )
    if has_loss:
        lines.append("    _epoch_loss_sum = 0.0; _epoch_batches = 0")
    lines.append("    for batch_idx, (data, targets) in enumerate(train_loader):")
    lines.append(batch_indented)
    lines.append(epoch_tail_indented)
    for node in post_training_nodes:
        post_code = _dag_node_code(node, cfg, dataset)
        if post_code:
            lines.append(post_code)
    return "\n".join(lines)


def _phase_dag_to_code(
    phase: PhaseDAGPayload,
    cfg: PipelineConfigPayload,
    dataset: str,
    *,
    block_placeholder_eval: bool = False,
) -> str:
    from backend.app.routers.notebook import _custom_pipeline_node_code

    def _dag_node_code(
        node: DagNodePayload, cfg: PipelineConfigPayload, dataset: str
    ) -> str | None:
        return dag_node_code(node, cfg, dataset, custom_code_resolver=_custom_pipeline_node_code)

    if not phase.nodes:
        return "# No nodes in this phase"
    ordered = _topo_sort(phase.nodes, phase.edges)
    node_types = {n.type for n in ordered}
    is_eval = bool(node_types & _METRIC_TYPES) and bool(node_types & _LOADER_TYPES)

    if not is_eval:
        return _training_phase_to_code(ordered, cfg, dataset, edges=phase.edges)

    if block_placeholder_eval:
        return (
            "raise RuntimeError(\n"
            "    'This notebook has placeholder weights, not the trained weights from the imported NIR file. '\n"
            "    'Import the original .nir file again and regenerate the notebook before running evaluation.'\n"
            ")"
        )

    # Eval phase — loader setup runs flat, then body runs inside a test_loader loop.
    # This ensures `data` and `targets` are always bound before forwardPass/metrics use them.
    loader_nodes = [n for n in ordered if n.type in _LOADER_TYPES]
    body_nodes = [n for n in ordered if n.type not in _LOADER_TYPES]

    loader_parts = [_dag_node_code(n, cfg, dataset) for n in loader_nodes]
    want_best_checkpoint = any(
        bool(n.parameters.get("load_best_checkpoint", True))
        for n in loader_nodes
        if n.type in {"dataLoader", "testLoader"}
    )
    if cfg.evaluation_profile == "lif_trace":
        trace_node = next((n for n in body_nodes if n.type == "traceMetric"), None)
        filename = (
            str(trace_node.parameters.get("filename", "lif_trace.csv"))
            if trace_node is not None
            else "lif_trace.csv"
        )
        lines = [s for s in loader_parts if s]
        lines += [
            "import numpy as np",
            "net.eval()",
            "with torch.no_grad():",
            "    data, _targets = next(iter(test_loader))",
            "    spk_out, mem_out = net(data)",
            "input_trace = data[0].detach().cpu().reshape(data.shape[1], -1)[:, 0].numpy()",
            "spike_trace = spk_out[:, 0].detach().cpu().reshape(spk_out.shape[0], -1)[:, 0].numpy()",
            "if hasattr(mem_out, 'detach') and mem_out.shape[0] == spk_out.shape[0]:",
            "    mem_trace = mem_out[:, 0].detach().cpu().reshape(mem_out.shape[0], -1)[:, 0].numpy()",
            "else:",
            "    mem_trace = np.full_like(spike_trace, np.nan, dtype=float)",
            "trace = np.column_stack([input_trace, mem_trace, spike_trace])",
            f"np.savetxt({filename!r}, trace, delimiter=',')",
            f"print('LIF trace saved to {filename}')",
        ]
        return "\n".join(lines)

    body_snippets = [_dag_node_code(n, cfg, dataset) for n in body_nodes]
    body = "\n\n".join(s for s in body_snippets if s)
    indented = "\n".join("        " + ln for ln in body.splitlines())

    max_batches = (
        cfg.max_eval_batches if cfg.evaluation_profile == "bounded_classification" else None
    )
    lines = [s for s in loader_parts if s]
    if want_best_checkpoint:
        lines += [
            "try:",
            "    net.load_state_dict(torch.load('best_model.pt', weights_only=True))",
            "    print('Loaded best checkpoint from best_model.pt')",
            "except FileNotFoundError:",
            '    print("best_model.pt not found — evaluating with current in-memory weights "',
            "          \"(enable 'Save Best Checkpoint' on the Validation Loop node and train first).\")",
        ]
    lines += [
        "correct = 0; total = 0",
        "net.eval()",
        "with torch.no_grad():",
        "    for batch_idx, (data, targets) in enumerate(test_loader):",
    ]
    if max_batches is not None:
        lines += [
            f"        if batch_idx >= {max_batches}:",
            "            break",
        ]
    # net._layer_rates reflects only the final eval batch, not a
    # full-dataset average — accumulate a running sum/count alongside
    # correct/total if a true average matters later.
    lines += [
        "        if batch_idx == 0:",
        "            net._capture_activity = True",
        indented,
    ]
    # One real eval sample's full per-timestep activity, every spiking layer,
    # captured only on the first eval batch — feeds the Results step's Network
    # Playback Grid/Raster views (previously always empty: nothing ever
    # produced activity_npy_b64 for them to fetch). Tagged with the final
    # training epoch number: eval runs after training completes, so this is
    # by construction the "final epoch" activity sample — and, being a real
    # held-out sample rather than a training batch, it deliberately takes
    # precedence over the training loop's own final-epoch capture (see
    # kernel_runner._maybe_capture_activity, last-write-wins per epoch key).
    lines += [
        "        if batch_idx == 0:",
        "            net._capture_activity = False",
        "            import io, zipfile, base64",
        "            _activity_buf = io.BytesIO()",
        "            with zipfile.ZipFile(_activity_buf, 'w') as _activity_zf:",
        "                for _act_k, _act_arr in getattr(net, '_layer_activity', {}).items():",
        "                    _npy_buf = io.BytesIO()",
        "                    np.save(_npy_buf, _act_arr)",
        "                    _activity_zf.writestr(f'{_act_k}_spikes.npy', _npy_buf.getvalue())",
        f"            _nmtk_emit_activity({cfg.epochs}, "
        "base64.b64encode(_activity_buf.getvalue()).decode('ascii'))",
    ]
    lines += [
        "        _nmtk_emit(\n"
        "            epoch=batch_idx + 1,\n"
        "            total=len(test_loader),\n"
        "            loss=0.0,\n"
        "            accuracy=(correct / total if total else None),\n"
        "            layer_rates=net._layer_rates,\n"
        "            phase='eval',\n"
        "        )",
        "print(f'Accuracy (top-1): {correct/total:.2%}' if total else 'Accuracy (top-1): n/a')",
        "_nmtk_emit(\n"
        "    epoch=1,\n"
        "    total=1,\n"
        "    loss=0.0,\n"
        "    accuracy=(correct / total if total else None),\n"
        "    layer_rates=net._layer_rates,\n"
        "    phase='eval',\n"
        ")",
    ]
    return "\n".join(lines)


def _val_loader_code(node: DagNodePayload, cfg: PipelineConfigPayload) -> str:
    """Codegen for the loader node wired into validationLoop's val_data port.

    Always binds `val_loader` — never `train_loader`/`test_loader` — since a
    dedicated validation loader carries its own batch_size/dataset_path
    independent of the phase's primary training loader; reusing the generic
    dataLoader/testLoader codegen unmodified would silently clobber those.
    """
    from backend.app.routers.notebook import _pt_named_loading_code

    p = node.parameters
    bs = int(p.get("batch_size", cfg.batch_size))
    if node.type == "testLoader":
        fmt = str(p.get("format", "auto") or "auto")
        if fmt == "pt":
            # A dedicated testLoader-typed val_data node carries its own
            # dataset_path (e.g. ds_val.pt) — never a bare `test_ds` global,
            # which only tonic/catalog formats define. Load it the same way
            # _dag_node_code's own "testLoader" case loads the eval test set.
            path = str(p.get("dataset_path", "") or cfg.custom_dataset_path or "./val_dataset.pt")
            return _pt_named_loading_code(
                path, batch_size=bs, loader_var="val_loader", label="validation"
            )
        collate = ", collate_fn=_pad_collate" if fmt.startswith("tonic_") else ""
        return (
            f"val_loader = DataLoader(test_ds, batch_size={bs}, shuffle=False, "
            f"num_workers=0{collate})"
        )
    if node.type == "dataLoader":
        fmt = str(p.get("format", "auto") or "auto")
        if fmt == "pt":
            path = str(p.get("dataset_path", "") or cfg.custom_dataset_path or "./val_dataset.pt")
            return _pt_named_loading_code(path, batch_size=bs)
        if fmt.startswith("tonic_"):
            # The tonic dataLoader branch defines bare `train_ds`/`test_ds`
            # globals, so reusing `test_ds` here is valid.
            return (
                f"val_loader = DataLoader(test_ds, batch_size={bs}, shuffle=False, "
                f"num_workers=0, collate_fn=_pad_collate)"
            )
        # Non-'pt', non-tonic dataLoader formats (e.g. 'auto' catalog lookups)
        # do not reliably define a bare `test_ds` global — emitting the reuse
        # here would guarantee a NameError in the generated notebook instead
        # of a working (if unintended) fallback.
        return (
            f"# validationLoop val_data: dataLoader format={fmt!r} has no dedicated "
            "validation-split loader yet (only format='pt' or a tonic_* format "
            "reusing test_ds are supported) — wire a dedicated validation "
            "dataset into val_data, or leave this port unconnected.\n"
            "raise RuntimeError("
            f'"validationLoop val_data: unsupported dataLoader format {fmt!r} — '
            'no val_loader could be generated.")'
        )
    return (
        f"# validationLoop val_data: unsupported source node type {node.type!r} — "
        "no val_loader created"
    )
