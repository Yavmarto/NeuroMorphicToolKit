"""Notebook-assembly logic for `backend.app.routers.notebook`.

Mechanical extraction of the nineteen functions/constants that turn a
compiled `nir.NIRGraph` plus a pipeline config into the actual cell list and
kernel metadata for a generated notebook: the cell-builder primitives
(`_code_cell`, `_md_cell`, `_support_warning_markdown`), the kernel/framework
tables (`_BASE_KERNEL_SLUG`, `_BASE_KERNEL_DISPLAY`, `_FRAMEWORKS`,
`_TRAINABLE_NOTEBOOK_TARGETS`, `_not_trainable_reason`, `_juv_cell`,
`_kernelspec_for`), the weights-artifact helpers (`_spec_hash`,
`_weights_artifact_name`, `_weight_key_check_lines`, `_WEIGHTED_NODE_TYPES`,
`_transplant_real_weights`, `_placeholder_weights_warning_markdown`), and the
three top-level notebook builders (`_build_v2_notebook`,
`_collect_uploaded_dataset_artifacts`, `_build_akida_mnist_notebook`).
Bodies are copied verbatim — behavior, strings, and comments are unchanged.

This is the fifth slice of the same ongoing `notebook.py` split; see
`notebook_graph_analysis.py`, `notebook_dag_node_emitters.py`,
`notebook_dag_lowering.py`, and `notebook_target_codegen.py` for the earlier
four and their shared conventions.

`_flatten_and_classify`, `_effective_notebook_dataset`, and
`_phase_loader_dataset_path` are imported directly from their real homes
(`notebook_graph_analysis` and `notebook_dag_lowering` respectively) rather
than via `notebook.py`'s compatibility re-export, the same way
`notebook_target_codegen.py` already imports `_scalar`/`_python_identifier`/
`_declared_endpoint_width` directly from `notebook_graph_analysis` (see that
module's own docstring for the precedent). `_ordered_graph_node_names` and
`_implausible_lif_thresholds` get the same direct-import treatment for the
same reason. `_phase_dag_to_code` and `_phase_surrogate_backward` are
imported directly from `notebook_dag_lowering`; `_generate_arch_code` and
`_auto_weight_visualizer_cell` directly from `notebook_target_codegen`
(the previous slice).

`_build_v2_notebook` also calls several names that still live in
`backend.app.routers.notebook` itself — `NMTK_EMIT_CELL_SOURCE`,
`_dataset_loading_code`, and `_dag_node_code`. Those are imported locally,
inside the function that needs them, rather than at module scope:
`notebook.py` imports `_build_v2_notebook` from this module during its own
import phase, before any of its own functions are defined, so a
module-level import back into `notebook.py` here would create a circular
import. `_LOADER_TYPES` and `PipelinePhasesPayload` are not defined in
`notebook.py` itself (it only re-imports them from
`backend.app.schemas.pipeline_dag`), so this module imports them directly
from that schema module instead, avoiding the circular-import problem
entirely for names that never lived in `notebook.py`.

`_collect_uploaded_dataset_artifacts` imports `DATA_DIR` locally, from
`backend.app.routers.notebook` rather than its real home
(`backend.app.services.dataset_cache`), because the test suite patches
`backend.app.routers.notebook.DATA_DIR` directly — a module-level import
from `dataset_cache` here would bind a separate reference that patching
notebook.py's attribute would not reach.
"""

from __future__ import annotations

import dataclasses
import hashlib
from pathlib import Path
from typing import Any

import nir
import numpy as np
from fastapi import HTTPException

from backend.app.schemas.notebook import PipelineConfigPayload
from backend.app.schemas.pipeline_dag import _LOADER_TYPES, PipelinePhasesPayload
from backend.app.services.notebook_dag_lowering import (
    _effective_notebook_dataset,
    _phase_dag_to_code,
    _phase_loader_dataset_path,
    _phase_surrogate_backward,
)
from backend.app.services.notebook_graph_analysis import (
    flatten_and_classify as _flatten_and_classify,
)
from backend.app.services.notebook_graph_analysis import (
    implausible_lif_thresholds as _implausible_lif_thresholds,
)
from backend.app.services.notebook_graph_analysis import (
    ordered_graph_node_names as _ordered_graph_node_names,
)
from backend.app.services.notebook_target_codegen import (
    _auto_weight_visualizer_cell,
    _generate_arch_code,
)
from neurocnl.runtime.nir_support import SupportClassification

# ── Platform-specific notebook cells ─────────────────────────────────────────


def _code_cell(source: str) -> dict[str, Any]:
    return {
        "cell_type": "code",
        "execution_count": None,
        "metadata": {},
        "outputs": [],
        "source": source,
    }


def _md_cell(source: str) -> dict[str, Any]:
    return {"cell_type": "markdown", "metadata": {}, "source": source}


def _support_warning_markdown(
    target: str, classification: SupportClassification
) -> str:
    """Render a classify_nir_graph() result as a notebook warning blockquote."""
    header = f"> **⚠️ {classification.level.upper()} support for `{target}`**"
    body = "\n".join(f"> {d}" for d in classification.diagnostics)
    return f"{header}\n>\n{body}" if body else header


# ── Kernel assignment ─────────────────────────────────────────────────────────
# Maps notebook target ids to pip package, kernel slug/display, and juv deps.
# Targets absent here (sc_neurocore_*, generic, unknown) fall back to the
# immutable base kernel.  Keep in sync with:
#   workers/jupyter_server/nmtk_env_manager/framework_envs.py → FRAMEWORK_ENVS
_BASE_KERNEL_SLUG = "neurocnl"
_BASE_KERNEL_DISPLAY = "Python (NeuroStudio)"

_FRAMEWORKS: dict[str, dict[str, Any]] = {
    "lava_sim": {
        "pip": "lava-nc",
        "kernel": ("nmtk-lava", "Python (Lava)"),
        "juv": ["lava-nc"],
    },
    "lava": {
        "pip": "lava-nc",
        "kernel": ("nmtk-lava", "Python (Lava)"),
        "juv": ["lava-nc"],
    },
    "snntorch_sim": {
        # Pinned to the version last verified in this environment (see
        # `~/.cache/uv/archive-v0/...`) so regenerated notebooks stay
        # reproducible across machines/time under a fixed torch.manual_seed.
        # NOT verified to match whatever version the original reference
        # notebook (paper/03_rnn/) was run against — that version was never
        # recorded and isn't discoverable at this point.
        "pip": "snntorch==0.9.4",
        "kernel": ("nmtk-snntorch", "Python (snnTorch)"),
        "juv": ["snntorch", "torch"],
    },
    "sc_neurocore_sim": {
        "pip": "sc-neurocore",
        "kernel": None,
        "juv": ["sc-neurocore"],
    },
    "sc_neurocore_fpga": {
        "pip": "sc-neurocore",
        "kernel": None,
        "juv": ["sc-neurocore"],
    },
    "akida": {
        "pip": "akida",
        "kernel": ("nmtk-akida", "Python (Akida)"),
        "juv": ["akida"],
    },
    "brian2": {
        "pip": "brian2",
        "kernel": ("nmtk-brian2", "Python (Brian2)"),
        "juv": ["brian2"],
    },
    "sinabs": {
        "pip": "sinabs",
        "kernel": ("nmtk-sinabs", "Python (Sinabs)"),
        "juv": ["sinabs"],
    },
    "rockpool": {
        "pip": "rockpool",
        "kernel": ("nmtk-rockpool", "Python (Rockpool)"),
        "juv": ["rockpool"],
    },
    "pynn": {
        "pip": "pyNN",
        "kernel": ("nmtk-pynn", "Python (PyNN / SpiNNaker)"),
        "juv": ["pyNN"],
    },
    "nengo": {
        "pip": "nengo",
        "kernel": ("nmtk-nengo", "Python (Nengo)"),
        "juv": ["nengo"],
    },
    "generic": {"pip": "", "kernel": None, "juv": []},
}

# Only this target currently has a Studio-generated, end-to-end verified
# optimiser loop. Other targets are conversion/inference/code-generation
# surfaces; running the generic snnTorch loop against them is invalid.
_TRAINABLE_NOTEBOOK_TARGETS: frozenset[str] = frozenset({"snntorch_sim"})


def _not_trainable_reason(target: str) -> str:
    """Explain, for a user, why pressing Play will not train *target*.

    One wording, two consumers: the notebook's own "Inference / code generation
    only" markdown cell and `GenerateV2Response.not_trainable_reason`, which the
    Run step shows on that platform's tab. Returns "" for a trainable target.
    """
    if target in _TRAINABLE_NOTEBOOK_TARGETS:
        return ""
    return (
        f"{target} has no Studio training adapter, so this notebook contains no "
        "training loop and Play does not run it. Train on snnTorch, then reach "
        "this target by exporting the trained model from the Training canvas."
    )


def _juv_cell(deps: list[str]) -> dict[str, Any]:
    """Build a hidden PEP 723 ``# /// script`` code cell compatible with juv.

    The cell is hidden by default (``source_hidden: true``) so it does not
    clutter the notebook UI.  ``uvx juv run <file>.ipynb`` reads it to create
    a matching uv environment automatically.
    """
    dep_lines = [f'#     "{d}",\n' for d in deps]
    source: list[str] = (
        ["# /// script\n", '# requires-python = ">=3.11"\n', "# dependencies = [\n"]
        + dep_lines
        + ["# ]\n", "# ///"]
    )
    return {
        "cell_type": "code",
        "execution_count": None,
        "id": "juv00000",
        "metadata": {"jupyter": {"source_hidden": True}},
        "outputs": [],
        "source": source,
    }


def _kernelspec_for(target: str) -> dict[str, Any]:
    kernel = _FRAMEWORKS.get(target, {}).get("kernel") or (
        _BASE_KERNEL_SLUG,
        _BASE_KERNEL_DISPLAY,
    )
    slug, display = kernel
    return {"display_name": display, "language": "python", "name": slug}


# ── Helpers ───────────────────────────────────────────────────────────────────


def _spec_hash(spec: str, target: str) -> str:
    return hashlib.sha256(f"{spec}:{target}".encode()).hexdigest()[:8]


def _weights_artifact_name(spec: str, target: str) -> str:
    """Per-target, per-spec weights filename.

    Regression fix: a bare 'weights.npz' shared by every notebook in a
    workspace folder let a later regeneration (different target, or the same
    target after a materially different Architecture-tab edit) silently
    leave behind — or load — a structurally incompatible weights file,
    surfacing as a bare KeyError deep inside model construction. Tying the
    filename to sha256(spec:target) means a given notebook's generated code
    and its weights file are always either an exact match or the file is
    simply absent (a clear FileNotFoundError), never a silent mismatch.
    """
    return f"weights_{target}_{_spec_hash(spec, target)}.npz"


def _weight_key_check_lines(
    weights: dict[str, np.ndarray[Any, Any]], weights_filename: str
) -> list[str]:
    """Fail-closed key-presence check emitted right after ``_w = np.load(...)``.

    Regenerating a notebook after a materially different Architecture-tab
    edit must never silently run against a stale/mismatched weights file —
    raise an actionable error instead of a bare KeyError deep inside model
    construction (see NeuroMorphicToolKit/AGENTS.md's actionable-error rule).
    """
    if not weights:
        return []
    expected = ", ".join(repr(k) for k in weights)
    return [
        "",
        f"_expected_weight_keys = [{expected}]",
        "_missing_weight_keys = [k for k in _expected_weight_keys if k not in _w.files]",
        "if _missing_weight_keys:",
        "    raise RuntimeError(",
        f"        f\"'{weights_filename}' is missing {{_missing_weight_keys}} — this weights \"",
        '        "file does not match the current network. Regenerate the notebook from "',
        '        "the Architecture tab so its weights file matches this architecture."',
        "    )",
    ]


_WEIGHTED_NODE_TYPES = (nir.Linear, nir.Affine, nir.Conv2d)


def _transplant_real_weights(graph: nir.NIRGraph, original: nir.NIRGraph) -> list[str]:
    """Copy real weight/bias arrays from `original` onto matching nodes in `graph`.

    `graph` may have been recompiled from shapes-only CNL text — the NIR-to-CNL
    renderer intentionally drops real tensor values (see nir_cnl/renderer.py),
    so `compile_to_nir()` can only rebuild placeholder weights. `original` is
    the graph parsed straight from a user's uploaded .nir file, which still
    has the real trained values.

    Matches nodes by name; a node is left untouched (and its name returned)
    when it has no counterpart in `original`, a different node type, or a
    different weight/bias shape — e.g. the user edited the architecture after
    importing, so transplanting would silently mismatch tensors.
    """
    placeholder_nodes: list[str] = []
    for name in _ordered_graph_node_names(graph):
        node = graph.nodes[name]
        if not isinstance(node, _WEIGHTED_NODE_TYPES):
            continue
        original_node = original.nodes.get(name)
        if not isinstance(original_node, type(node)):
            placeholder_nodes.append(name)
            continue
        real_weight = np.asarray(original_node.weight)
        if real_weight.shape != np.asarray(node.weight).shape:
            placeholder_nodes.append(name)
            continue
        updates: dict[str, object] = {"weight": real_weight}
        node_bias = getattr(node, "bias", None)
        if node_bias is not None:
            real_bias = getattr(original_node, "bias", None)
            if (
                real_bias is None
                or np.asarray(real_bias).shape != np.asarray(node_bias).shape
            ):
                placeholder_nodes.append(name)
                continue
            updates["bias"] = np.asarray(real_bias)
        try:
            graph.nodes[name] = dataclasses.replace(node, **updates)
        except TypeError:
            for field_name, value in updates.items():
                setattr(node, field_name, value)
    return placeholder_nodes


def _placeholder_weights_warning_markdown(node_names: list[str]) -> str:
    layers = ", ".join(f"`{n}`" for n in node_names)
    return (
        "⚠️ **Untrained weights**\n\n"
        f"Layer(s) {layers} could not be matched to the originally imported "
        "NIR file's real trained values (missing import, a shape/type change "
        "since import, or an expired import). They were compiled with "
        "placeholder weights and this notebook will not reproduce the "
        "original model's accuracy. Re-import the NIR file from the "
        "Architecture tab and regenerate the notebook without further edits "
        "to those layers to get the real trained values back."
    )


def _build_v2_notebook(
    spec: str,
    graph: nir.NIRGraph,
    cfg: PipelineConfigPayload,
    timestamp: str,
    pipeline_phases: PipelinePhasesPayload,
    pipeline_cnl: str = "",
    placeholder_weight_nodes: list[str] | None = None,
    block_placeholder_eval: bool = False,
) -> tuple[dict[str, Any], dict[str, bytes]]:
    """Build a pipeline-aware Jupyter notebook.

    Cell layout:
        0  [hidden juv cell] — framework deps for juv run
        1  [md]   Title / metadata
        2  [code] config = { ... }    ← always editable by user
        3  [md]   ## Architecture
        4  [code] compile CNL → NIR → framework model
        5  [md]   ## Train
        6  [code] training loop  (framework-specific)
        7  [md]   ## Evaluate    (conditional on cfg.run_evaluation)
        8  [code] eval block     (conditional)
        9  [md]   ## Infer / Export (conditional on cfg.export_nir)
       10  [code] NIR export     (conditional)
    """
    from backend.app.routers.notebook import (
        NMTK_EMIT_CELL_SOURCE,
        _dag_node_code,
        _dataset_loading_code,
    )

    target = cfg.framework
    graph, classification, cnl_flattened = _flatten_and_classify(graph, target)
    effective_dataset = _effective_notebook_dataset(cfg, pipeline_phases)
    effective_custom_path = (
        _phase_loader_dataset_path(pipeline_phases.eval)
        or _phase_loader_dataset_path(pipeline_phases.train)
        or cfg.custom_dataset_path
    )

    # ── Cell 0: juv dependency cell ──────────────────────────────────────────
    pip_pkg = _FRAMEWORKS.get(target, {}).get("pip", "")
    juv_deps: list[str] = ["neurocnl"]
    if pip_pkg:
        juv_deps.append(pip_pkg)
    if target == "snntorch_sim":
        # torch is otherwise pulled in transitively via snntorch, with
        # whatever version that resolves to — pin it explicitly too, for
        # the same reproducibility reason as the snntorch pin above.
        juv_deps.append("torch==2.13.0")
    if effective_dataset in ("NMNIST", "N-TIDIGITS") or effective_dataset.startswith(
        "tonic_"
    ):
        juv_deps.append("tonic")
    cells: list[dict[str, Any]] = [_juv_cell(juv_deps)]

    # ── Cell 1: title ────────────────────────────────────────────────────────
    target_label = target.replace("_", " ").title()
    cells.append(
        _md_cell(
            f"# NeuroMorphic Pipeline — {target_label}\n\n"
            f"Generated {timestamp}.\n\n"
            f"**Architecture:** defined in the Architecture tab (CNL spec below).\n"
            f"**Pipeline config:** edit `config` in the next cell to change training parameters."
        )
    )

    # ── Cell 2: config dict (always first code cell, always user-editable) ───
    dataset_val = (
        f'"{effective_custom_path}"'
        if effective_dataset == "custom" and effective_custom_path
        else f'"{effective_dataset}"'
    )
    config_src = (
        "# ── Pipeline configuration ───────────────────────────────────────────\n"
        "# Workspace settings used when this notebook was generated.\n\n"
        "config = {\n"
        f'    "dataset":   {dataset_val},\n'
        f'    "framework": "{target}",\n'
        "}\n\n"
        "print('Config loaded:', config)"
    )
    cells.append(_code_cell(config_src))
    cells.append(_code_cell(NMTK_EMIT_CELL_SOURCE))

    # ── Dataset loading cell ──────────────────────────────────────────────────
    cells.append(
        _code_cell(
            _dataset_loading_code(
                effective_dataset, cfg.batch_size, effective_custom_path
            )
        )
    )

    # ── Cell 3 + 4: architecture ──────────────────────────────────────────────
    cells.append(_md_cell("## Architecture\n\nNetwork compiled from CNL spec via NIR."))
    cells.append(
        _code_cell(
            "# CNL spec — auto-generated from the Architecture canvas tab.\n"
            "# To change the network, edit the Architecture tab and regenerate.\n"
            "cnl_spec = '''\n" + spec + "\n'''\n\n"
            "from neurocnl.compile import compile_to_nir\n\n"
            "graph = compile_to_nir(cnl_spec)\n"
            "print(f'Network: {len(graph.nodes)} nodes, {len(graph.edges)} edges')"
        )
    )

    # ── Framework-specific build cell ────────────────────────────────────────
    surrogate_node = _phase_surrogate_backward(pipeline_phases.train)
    spike_grad_expr = (
        f"surrogate.{surrogate_node.parameters.get('function', 'fast_sigmoid')}"
        f"(slope={surrogate_node.parameters.get('slope', 25.0)})"
        if surrogate_node is not None
        else None
    )
    arch_code, arch_weights, io_error = _generate_arch_code(
        target,
        graph,
        cfg,
        cnl_flattened,
        spec,
        spike_grad_expr=spike_grad_expr,
        time_major_input=effective_dataset.startswith("tonic_"),
    )
    if target == "snntorch_sim":
        arch_code = (
            f"import torch\nimport numpy as np\n"
            f"torch.manual_seed({cfg.seed})\nnp.random.seed({cfg.seed})\n"
            f"torch.use_deterministic_algorithms(True)\n\n"
        ) + arch_code
    cells.append(_code_cell(arch_code))
    if io_error:
        cells.append(_md_cell(io_error))
    if classification is not None and classification.level != "exact":
        cells.append(_md_cell(_support_warning_markdown(target, classification)))
    if placeholder_weight_nodes:
        cells.append(
            _md_cell(_placeholder_weights_warning_markdown(placeholder_weight_nodes))
        )
    if target == "snntorch_sim":
        lif_warnings = _implausible_lif_thresholds(graph)
        if lif_warnings:
            cells.append(
                _md_cell(
                    "> **⚠️ Possibly unreachable firing threshold**\n>\n"
                    + "\n".join(lif_warnings)
                )
            )

    # ── Cell 5+: train / eval — DAG-based (canvas drives content) ───────────
    dataset = effective_dataset

    # If the train phase has no loader node but the eval phase has a
    # spikeGenerator, hoist the spike generator setup before the Train cell so
    # train_loader is always defined before the training loop executes.
    train_node_types = {n.type for n in pipeline_phases.train.nodes}
    if (
        pipeline_phases.train.nodes
        and not (train_node_types & _LOADER_TYPES)
        and not dataset
    ):
        eval_spike_gen = next(
            (n for n in pipeline_phases.eval.nodes if n.type == "spikeGenerator"),
            None,
        )
        if eval_spike_gen is not None:
            cells.append(
                _code_cell(
                    "# ── Synthetic spike data (from Eval canvas SpikeGenerator) ──\n"
                    "# train_loader and test_loader are defined here so the Train\n"
                    "# loop below can iterate over them.\n"
                    + (_dag_node_code(eval_spike_gen, cfg, dataset) or "")
                )
            )

    if pipeline_phases.train.nodes and target in _TRAINABLE_NOTEBOOK_TARGETS:
        cells.append(_md_cell("## Train"))
        cells.append(
            _code_cell(_phase_dag_to_code(pipeline_phases.train, cfg, dataset))
        )
        # Auto-append a weight-map visualizer when the first Linear layer has
        # a perfect-square input dimension (i.e. the inputs are spatial, like
        # pixels).  No canvas node required — this fires automatically.
        _wv_src = _auto_weight_visualizer_cell(graph)
        if _wv_src is not None:
            cells.append(_md_cell("## Weight Map"))
            cells.append(_code_cell(_wv_src))
    elif pipeline_phases.train.nodes:
        cells.append(
            _md_cell(
                "## Inference / code generation only\n\n"
                f"{_not_trainable_reason(target)}\n\n"
                "Export trained NIR once after training, then regenerate this "
                "notebook from that NIR artifact."
            )
        )
    if pipeline_phases.eval.nodes:
        cells.append(_md_cell("## Evaluate"))
        cells.append(
            _code_cell(
                _phase_dag_to_code(
                    pipeline_phases.eval,
                    cfg,
                    dataset,
                    block_placeholder_eval=block_placeholder_eval,
                )
            )
        )

    if cfg.generate_py_download:
        cells.append(
            _code_cell(
                "# ── Download as Python script ──────────────────────────────────\n"
                "# Run this cell to download the notebook as a .py script.\n"
                "# A Jupyter kernel has no script-path global, so resolve the\n"
                "# notebook from the working directory instead.\n"
                "import subprocess\n"
                "from pathlib import Path\n"
                "for _nb in sorted(Path.cwd().glob('*.ipynb')):\n"
                "    subprocess.run(['jupyter', 'nbconvert', '--to', 'script',\n"
                "                    str(_nb)], check=False)\n"
                "print('Conversion triggered — check the file listing.')"
            )
        )

    # ── Assemble notebook ─────────────────────────────────────────────────────
    kernelspec = _kernelspec_for(target)
    nb = {
        "nbformat": 4,
        "nbformat_minor": 5,
        "metadata": {
            "kernelspec": kernelspec,
            "language_info": {"name": "python", "version": "3.11"},
            "neurocnl": {
                "generated_at": timestamp,
                "target": target,
                "generator": "generate-v2",
                **({"pipeline_cnl": pipeline_cnl} if pipeline_cnl else {}),
            },
        },
        "cells": cells,
    }
    artifacts: dict[str, bytes] = {}
    if arch_weights:
        import io as _io

        buf = _io.BytesIO()
        np.savez_compressed(buf, **arch_weights)
        artifacts[_weights_artifact_name(spec, target)] = buf.getvalue()
    return nb, artifacts


def _collect_uploaded_dataset_artifacts(
    pipeline_phases: PipelinePhasesPayload,
) -> dict[str, bytes]:
    """Pull bytes for Data Loader/Test Loader nodes pointing at an uploaded file
    (via POST /datasets/upload-raw, which writes under DATA_DIR/pipeline_uploads/),
    and rewrite each such node's dataset_path to the bare filename it will be
    published alongside via _publish_via_contents_api. This is only needed
    when a Jupyter worker executes the notebook in a separate container —
    suite_api's local disk isn't visible there (see JUPYTER_WORKER_URL docstring
    above), whereas the published artifact — like weights.npz — is.
    """
    from backend.app.routers.notebook import DATA_DIR

    uploaded_root = str(DATA_DIR / "pipeline_uploads")
    artifacts: dict[str, bytes] = {}
    for phase in (pipeline_phases.train, pipeline_phases.eval):
        for node in phase.nodes:
            if node.type not in ("dataLoader", "testLoader"):
                continue
            if node.parameters.get("format") not in ("pt", "npy"):
                continue
            dataset_path = str(node.parameters.get("dataset_path", ""))
            if not dataset_path.startswith(uploaded_root):
                continue
            try:
                file_bytes = Path(dataset_path).read_bytes()
            except OSError as exc:
                raise HTTPException(
                    status_code=422,
                    detail=(
                        f"Uploaded dataset file for node '{node.id}' is no longer "
                        f"on the server ({dataset_path}). Browse for the file again "
                        "on the Data Loader node, then retry."
                    ),
                ) from exc
            artifact_name = f"{node.id}_{Path(dataset_path).name}"
            artifacts[artifact_name] = file_bytes
            node.parameters["dataset_path"] = artifact_name
    return artifacts


def _build_akida_mnist_notebook(timestamp: str) -> dict[str, Any]:
    """Build BrainChip's documented PyTorch→ONNX MNIST companion notebook."""
    cells: list[dict[str, Any]] = [
        _juv_cell(
            [
                "torch==2.7.0",
                "torchvision",
                "onnx",
                "onnxruntime",
                "numpy",
            ]
        ),
        _md_cell(
            "# Akida 2.0 MNIST companion\n\n"
            "Run all cells to train the documented CNN on full MNIST, verify "
            "PyTorch/ONNX parity, and emit one checksummed bundle for the "
            "Akida panel. Conversion and physical mapping happen on the paired host."
        ),
        _code_cell(
            "from pathlib import Path\n"
            "import random\n"
            "import numpy as np\n"
            "import torch\n"
            "import torchvision\n"
            "from torchvision import transforms\n\n"
            "SEED = 1729\n"
            "random.seed(SEED); np.random.seed(SEED); torch.manual_seed(SEED)\n"
            "torch.use_deterministic_algorithms(True)\n"
            "batch_size, epochs = 128, 10\n"
            "transform = transforms.Compose([transforms.ToTensor(), transforms.Normalize(0.5, 0.5)])\n"
            "train_set = torchvision.datasets.MNIST('datasets/mnist', train=True, download=True, transform=transform)\n"
            "test_set = torchvision.datasets.MNIST('datasets/mnist', train=False, download=True, transform=transform)\n"
            "generator = torch.Generator().manual_seed(SEED)\n"
            "train_loader = torch.utils.data.DataLoader(train_set, batch_size=batch_size, shuffle=True, num_workers=0, generator=generator)\n"
            "test_loader = torch.utils.data.DataLoader(test_set, batch_size=batch_size, shuffle=False, num_workers=0)\n"
            "print(f'Full MNIST ready: {len(train_set)} train / {len(test_set)} test')"
        ),
        _code_cell(
            "model_torch = torch.nn.Sequential(\n"
            "    torch.nn.Conv2d(1, 32, 5, padding=(2, 2)), torch.nn.ReLU6(),\n"
            "    torch.nn.MaxPool2d(kernel_size=2),\n"
            "    torch.nn.Conv2d(32, 64, 3, stride=2), torch.nn.ReLU(),\n"
            "    torch.nn.Dropout(0.25), torch.nn.Flatten(),\n"
            "    torch.nn.Linear(2304, 512), torch.nn.ReLU(),\n"
            "    torch.nn.Dropout(0.5), torch.nn.Linear(512, 10),\n"
            ")\n"
            "optimizer = torch.optim.Adam(model_torch.parameters(), lr=1e-4)\n"
            "criterion = torch.nn.CrossEntropyLoss()\n"
            "for epoch in range(epochs):\n"
            "    model_torch.train(); running_loss = 0.0\n"
            "    for images, labels in train_loader:\n"
            "        optimizer.zero_grad(); outputs = model_torch(images)\n"
            "        loss = criterion(outputs, labels); loss.backward(); optimizer.step()\n"
            "        running_loss += loss.item()\n"
            "    print(f'Epoch {epoch + 1}/{epochs}: loss={running_loss / len(train_loader):.5f}')"
        ),
        _code_cell(
            "model_torch.eval(); correct = total = 0\n"
            "with torch.no_grad():\n"
            "    for images, labels in test_loader:\n"
            "        predicted = model_torch(images).argmax(1)\n"
            "        total += labels.numel(); correct += (predicted == labels).sum().item()\n"
            "pytorch_accuracy = correct / total\n"
            "assert pytorch_accuracy >= 0.98, f'PyTorch accuracy {pytorch_accuracy:.4f} is below 98%'\n"
            "sample, _ = next(iter(train_loader))\n"
            "torch.onnx.export(model_torch, sample, 'model.onnx', input_names=['inputs'], output_names=['outputs'], "
            "dynamic_axes={'inputs': {0: 'batch_size'}, 'outputs': {0: 'batch_size'}}, opset_version=17)\n"
            "print(f'PyTorch accuracy: {pytorch_accuracy:.4%}; ONNX exported')"
        ),
        _code_cell(
            "import onnxruntime as ort\n"
            "session = ort.InferenceSession('model.onnx', providers=['CPUExecutionProvider'])\n"
            "onnx_correct = onnx_total = 0\n"
            "for images, labels in test_loader:\n"
            "    outputs = session.run(None, {'inputs': images.numpy()})[0]\n"
            "    onnx_correct += (outputs.argmax(1) == labels.numpy()).sum()\n"
            "    onnx_total += labels.numel()\n"
            "onnx_accuracy = float(onnx_correct / onnx_total)\n"
            "assert abs(onnx_accuracy - pytorch_accuracy) <= 0.001, 'ONNX parity exceeded 0.1 percentage point'\n"
            "print(f'ONNX accuracy: {onnx_accuracy:.4%}')"
        ),
        _code_cell(
            "import hashlib, importlib.metadata, io, json, zipfile\n"
            "calibration = next(iter(train_loader))[0][:128].numpy().astype(np.float32)\n"
            "evaluation_inputs = test_set.data.numpy().astype(np.uint8)[:, None, :, :]\n"
            "evaluation_labels = test_set.targets.numpy().astype(np.int32)\n"
            "calibration_io = io.BytesIO(); np.save(calibration_io, calibration)\n"
            "evaluation_io = io.BytesIO(); np.savez_compressed(evaluation_io, inputs=evaluation_inputs, labels=evaluation_labels)\n"
            "payloads = {'model.onnx': Path('model.onnx').read_bytes(), 'calibration.npy': calibration_io.getvalue(), 'evaluation.npz': evaluation_io.getvalue()}\n"
            "versions = {}\n"
            "for package in ('torch', 'torchvision', 'onnx', 'onnxruntime', 'numpy'):\n"
            "    versions[package] = importlib.metadata.version(package)\n"
            "manifest = {\n"
            "    'schemaVersion': 1, 'bundleType': 'nmtk.akida.model', 'modelName': 'MNIST CNN',\n"
            "    'sourceFramework': 'pytorch', 'target': 'akida2',\n"
            "    'input': {'shape': [1, 1, 28, 28], 'layout': 'NCHW', 'dtype': 'float32'},\n"
            "    'preprocessing': {'scale': 2.0 / 255.0, 'offset': -1.0, 'calibration_dtype': 'float32', 'evaluation_dtype': 'uint8'},\n"
            "    'labels': [str(i) for i in range(10)],\n"
            "    'sourceMetrics': {'pytorch_accuracy': pytorch_accuracy, 'onnx_accuracy': onnx_accuracy},\n"
            "    'dependencyVersions': versions,\n"
            "    'files': {name: hashlib.sha256(data).hexdigest() for name, data in payloads.items()},\n"
            "}\n"
            "bundle_path = Path('akida_mnist_v1.akida-bundle.zip')\n"
            "with zipfile.ZipFile(bundle_path, 'w', compression=zipfile.ZIP_DEFLATED) as bundle:\n"
            "    bundle.writestr('manifest.json', json.dumps(manifest, indent=2, sort_keys=True))\n"
            "    for name, data in payloads.items(): bundle.writestr(name, data)\n"
            "print(f'Akida bundle ready: {bundle_path} ({hashlib.sha256(bundle_path.read_bytes()).hexdigest()})')"
        ),
    ]
    return {
        "nbformat": 4,
        "nbformat_minor": 5,
        "metadata": {
            "kernelspec": _kernelspec_for("snntorch_sim"),
            "language_info": {"name": "python", "version": "3.11"},
            "neurocnl": {
                "generated_at": timestamp,
                "target": "akida2",
                "generator": "akida-mnist-companion-v1",
            },
        },
        "cells": cells,
    }
