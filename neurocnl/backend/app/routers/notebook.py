"""POST /api/notebook/from-spec — generate per-target Jupyter notebooks from a CNL spec."""

from __future__ import annotations

import hashlib
import io
import json
import logging as _logging
import os
import zipfile
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

import nir
import numpy as np
from fastapi import APIRouter, HTTPException

from backend.app.schemas.notebook import (  # compatibility re-exports
    AkidaBundleArtifactResponse,
    AkidaMnistNotebookRequest,
    DatasetSampleResponse,
    DeployPreviewRequest,
    DeployPreviewResponse,
    EnsureWorkspaceRequest,
    EnsureWorkspaceResponse,
    GenerateV2Request,
    GenerateV2Response,
    NotebookEntry,
    NotebookLastModifiedResponse,
    ParsePipelineCnlRequest,
    ParsePipelineCnlResponse,
    PipelineCnlRequest,
    PipelineCnlResponse,
    PipelineConfigPayload,
    ProvisionFromNotebookRequest,
    ProvisionFromNotebookResponse,
    TrainedNirArtifactResponse,
)
from backend.app.schemas.pipeline_dag import (  # noqa: F401 — re-exported; tests import it from this module
    _LOADER_TYPES as _LOADER_TYPES,
)
from backend.app.schemas.pipeline_dag import _LOSS_TYPES as _LOSS_TYPES
from backend.app.schemas.pipeline_dag import _OPTIMISER_TYPES as _OPTIMISER_TYPES
from backend.app.schemas.pipeline_dag import _SCHEDULER_TYPES as _SCHEDULER_TYPES
from backend.app.schemas.pipeline_dag import DagEdgePayload as DagEdgePayload
from backend.app.schemas.pipeline_dag import DagNodePayload as DagNodePayload
from backend.app.schemas.pipeline_dag import PhaseDAGPayload as PhaseDAGPayload
from backend.app.schemas.pipeline_dag import (
    PipelinePhasesPayload as PipelinePhasesPayload,
)
from backend.app.services.dataset_cache import (
    DATA_DIR as DATA_DIR,  # Re-exported: notebook_assembly's _collect_uploaded_dataset_artifacts imports it; locally from this module (tests patch it here). The `as DATA_DIR` alias is required; so mypy's --no-implicit-reexport (part of strict mode) treats this as an; intentional re-export rather than an unused import.
)
from backend.app.services.dataset_catalog import (  # noqa: F401 — re-exported; tests patch this name here, and notebook_dataset_codegen's _dataset_loading_code imports it locally from this module
    load_dataset_catalog,
)
from backend.app.services.nir_import_store import load_nir_import
from backend.app.services.notebook_artifacts import (
    WorkspaceArtifact as _WorkspaceArtifact,
)
from backend.app.services.notebook_artifacts import discover_workspace_artifact
from backend.app.services.notebook_assembly import (  # noqa: F401 — compatibility re-exports; only imported elsewhere by tests and other services' local imports
    _BASE_KERNEL_DISPLAY,
    _BASE_KERNEL_SLUG,
    _FRAMEWORKS,
    _TRAINABLE_NOTEBOOK_TARGETS,
    _WEIGHTED_NODE_TYPES,
    _build_akida_mnist_notebook,
    _build_v2_notebook,
    _code_cell,
    _collect_uploaded_dataset_artifacts,
    _juv_cell,
    _kernelspec_for,
    _md_cell,
    _not_trainable_reason,
    _placeholder_weights_warning_markdown,
    _spec_hash,
    _support_warning_markdown,
    _transplant_real_weights,
    _weight_key_check_lines,
    _weights_artifact_name,
)
from backend.app.services.notebook_dag_lowering import (  # noqa: F401 — re-exported; some are still used below, others only by tests importing from this module
    _ACTIVITY_CAPTURE_CADENCE_EPOCHS as _ACTIVITY_CAPTURE_CADENCE_EPOCHS,
)
from backend.app.services.notebook_dag_lowering import _METRIC_TYPES as _METRIC_TYPES
from backend.app.services.notebook_dag_lowering import (
    _effective_notebook_dataset as _effective_notebook_dataset,
)
from backend.app.services.notebook_dag_lowering import (
    _phase_dag_to_code as _phase_dag_to_code,
)
from backend.app.services.notebook_dag_lowering import (
    _phase_has_eval_loop as _phase_has_eval_loop,
)
from backend.app.services.notebook_dag_lowering import (
    _phase_has_training_loop as _phase_has_training_loop,
)
from backend.app.services.notebook_dag_lowering import (
    _phase_loader_dataset as _phase_loader_dataset,
)
from backend.app.services.notebook_dag_lowering import (
    _phase_loader_dataset_path as _phase_loader_dataset_path,
)
from backend.app.services.notebook_dag_lowering import (
    _phase_surrogate_backward as _phase_surrogate_backward,
)
from backend.app.services.notebook_dag_lowering import (
    _training_phase_to_code as _training_phase_to_code,
)
from backend.app.services.notebook_dag_lowering import (
    _val_loader_code as _val_loader_code,
)
from backend.app.services.notebook_dag_node_emitters import (  # noqa: F401 — _custom_pipeline_node_code re-exported; tests import it from this module
    _custom_pipeline_node_code,
    dag_node_code,
)
from backend.app.services.notebook_dataset_codegen import (  # noqa: F401 — re-exported; tests import these from this module
    _TONIC_DATASET_CLASS,
    _TONIC_EXTRA_CTOR_KWARGS,
    _dataset_loading_code,
    _pt_loading_code,
    _pt_named_loading_code,
    _spike_generator_code,
)
from backend.app.services.notebook_graph_analysis import (  # noqa: F401 — one-release compatibility aliases; tests import these from this module; noqa: F401
    CNL_FLATTEN_TARGETS as _CNL_FLATTEN_TARGETS,
)
from backend.app.services.notebook_graph_analysis import (  # noqa: F401
    WIDTH_PRESERVING_NIR_NODES as _WIDTH_PRESERVING_NIR_NODES,
)
from backend.app.services.notebook_graph_analysis import (  # noqa: F401
    GraphWidthMismatchError,
)
from backend.app.services.notebook_graph_analysis import (  # noqa: F401
    check_input_width_against_datasets as _check_input_width_against_datasets,
)
from backend.app.services.notebook_graph_analysis import (  # noqa: F401
    declared_endpoint_width as _declared_endpoint_width,
)
from backend.app.services.notebook_graph_analysis import (  # noqa: F401
    endpoint_shape_literal as _endpoint_shape_literal,
)
from backend.app.services.notebook_graph_analysis import (  # noqa: F401
    flatten_and_classify as _flatten_and_classify,
)
from backend.app.services.notebook_graph_analysis import (  # noqa: F401
    graph_needs_cnl_flatten as _graph_needs_cnl_flatten,
)
from backend.app.services.notebook_graph_analysis import (  # noqa: F401
    graph_weighted_node_names as _graph_weighted_node_names,
)
from backend.app.services.notebook_graph_analysis import (  # noqa: F401
    implausible_lif_thresholds as _implausible_lif_thresholds,
)
from backend.app.services.notebook_graph_analysis import (  # noqa: F401
    nir_first_process_slug as _nir_first_process_slug,
)
from backend.app.services.notebook_graph_analysis import (  # noqa: F401
    nir_node_slugs as _nir_node_slugs,
)
from backend.app.services.notebook_graph_analysis import (  # noqa: F401
    nir_pop_slugs as _nir_pop_slugs,
)
from backend.app.services.notebook_graph_analysis import (  # noqa: F401
    nir_syn_slugs as _nir_syn_slugs,
)
from backend.app.services.notebook_graph_analysis import (  # noqa: F401
    node_order_key as _node_order_key,
)
from backend.app.services.notebook_graph_analysis import (  # noqa: F401
    ordered_graph_node_names as _ordered_graph_node_names,
)
from backend.app.services.notebook_graph_analysis import (  # noqa: F401
    propagate_graph_widths as _propagate_graph_widths,
)
from backend.app.services.notebook_graph_analysis import (  # noqa: F401
    pt_dataset_widths as _pt_dataset_widths,
)
from backend.app.services.notebook_graph_analysis import (  # noqa: F401
    python_identifier as _python_identifier,
)
from backend.app.services.notebook_graph_analysis import scalar as _scalar  # noqa: F401
from backend.app.services.notebook_graph_analysis import (  # noqa: F401
    slugify as _slugify,
)
from backend.app.services.notebook_graph_analysis import (  # noqa: F401
    weighted_node_in_out as _weighted_node_in_out,
)
from backend.app.services.notebook_publishing import (
    fetch_notebook_last_modified,
    jupyter_tree_url,
    mirror_generated_files,
    publish_via_contents_api,
)
from backend.app.services.notebook_target_codegen import (  # noqa: F401 — compatibility re-exports; tests (and notebook_dag_node_emitters' local imports) import these from this module
    _akida_bundle_code,
    _akida_exporter_code,
    _attribution_visualizer_code,
    _generate_arch_code,
    _generate_sc_neurocore_code,
    _generate_snntorch_code,
    _weight_visualizer_code,
)
from neurocnl.compile import CompileError, compile_pipeline_config, compile_to_nir
from neurocnl.nir_cnl import NIR_Renderer, RenderError
from neurocnl.nir_cnl.pipeline_config import PipelineConfig as NirCnlPipelineConfig
from neurocnl.training.dag_topology import (  # noqa: F401 — re-exported; tests import _topo_sort from this module
    topo_sort_nodes as _topo_sort,
)
from neurocnl.training.dataset_loader import DatasetLoadError, pt_dense_tensors

router = APIRouter()

_logger = _logging.getLogger(__name__)

# Local-filesystem fallback (standalone dev): must match the Jupyter server's
# --notebook-dir. In the Docker setup this is $JUPYTER_NOTEBOOK_DIR (default /root).
NOTEBOOK_DIR = Path(os.environ.get("JUPYTER_NOTEBOOK_DIR", "/root"))

# Internal URL the backend uses to talk to the Jupyter Server (Contents API).
# Set in docker-compose (http://jupyter-server:8008). When present, notebooks are
# written through Jupyter's Contents API so they land in the volume Jupyter serves —
# this avoids cross-container filesystem/permission mismatches (the suite_api
# container runs as a non-root user and does not mount the Jupyter volume).
JUPYTER_WORKER_URL = os.environ.get("JUPYTER_WORKER_URL", "").rstrip("/")

# Public URL the Flutter WebView uses to open JupyterLab (e.g. http://host:8008/lab).
# Set in docker-compose; returned to the frontend so it never hard-codes ports/hosts.
JUPYTER_PUBLIC_URL = os.environ.get("JUPYTER_PUBLIC_URL", "").rstrip("/")


def _mirror_generated_notebook_files(
    workspace_folder: str,
    notebooks: list[tuple[str, dict[str, Any]]],
    artifacts: dict[str, bytes],
) -> None:
    """Compatibility facade for the extracted publishing service."""
    mirror_generated_files(
        NOTEBOOK_DIR,
        workspace_folder,
        notebooks,
        artifacts,
        logger=_logger,
    )


# ── Platform-specific notebook cells ─────────────────────────────────────────

_TARGET_CELLS: dict[str, list[dict[str, Any]]] = {
    "lava_sim": [
        _md_cell(
            "## Lava (Simulation)\n\nRun the compiled network with the Lava software simulator."
        ),
        _code_cell(
            "from lava.magma.core.run_configs import Loihi1SimCfg\n"
            "from lava.magma.core.run_conditions import RunSteps\n\n"
            "# TODO: map NIR graph to Lava processes\n"
            "# process = ...\n"
            "# process.run(condition=RunSteps(num_steps=100), run_cfg=Loihi1SimCfg())\n"
            "# process.stop()\n"
            "print('Lava simulation scaffold ready.')"
        ),
    ],
    "snntorch_sim": [
        _md_cell(
            "## snnTorch (Simulation)\n\nTrain / evaluate the network with snnTorch and PyTorch."
        ),
        _code_cell(
            "import torch\n"
            "import snntorch as snn\n"
            "from snntorch import surrogate\n\n"
            "# TODO: map NIR graph to snnTorch layers\n"
            "# net = ...\n"
            "# optimizer = torch.optim.Adam(net.parameters(), lr=1e-3)\n"
            "print('snnTorch scaffold ready.')"
        ),
    ],
    "sc_neurocore_sim": [
        _md_cell(
            "## SC-NeuroCore (Simulation)\n\nSimulate the network on SC-NeuroCore."
        ),
        _code_cell(
            "# import sc_neurocore  # adjust to actual package name\n\n"
            "# TODO: load NIR graph into SC-NeuroCore simulation environment\n"
            "print('SC-NeuroCore simulation scaffold ready.')"
        ),
    ],
    "akida": [
        _md_cell(
            "## Akida (BrainChip)\n\nConvert and run the network on an Akida device or simulator."
        ),
        _code_cell(
            "import akida\n"
            "from cnn2snn import convert  # MetaTF conversion\n\n"
            "# TODO: convert NIR graph → Akida model\n"
            "# model_akida = akida.Model(...)\n"
            "# model_akida.summary()\n"
            "print('Akida scaffold ready.')"
        ),
    ],
    "lava": [
        _md_cell(
            "## Lava / Loihi 2 (Hardware)\n\nDeploy the network to a Loihi 2 chip via Lava."
        ),
        _code_cell(
            "from lava.magma.core.run_configs import Loihi2HwCfg\n"
            "from lava.magma.core.run_conditions import RunSteps\n\n"
            "# TODO: configure Loihi 2 board connection and map processes\n"
            "# process.run(condition=RunSteps(num_steps=100), run_cfg=Loihi2HwCfg())\n"
            "# process.stop()\n"
            "print('Loihi 2 hardware scaffold ready.')"
        ),
    ],
    "sc_neurocore_fpga": [
        _md_cell(
            "## SC-NeuroCore FPGA (RTL Synthesis)\n\nSynthesize the network for the SC-NeuroCore FPGA target."
        ),
        _code_cell(
            "# import sc_neurocore_fpga  # adjust to actual package name\n\n"
            "# TODO: run RTL synthesis flow\n"
            "print('SC-NeuroCore FPGA synthesis scaffold ready.')"
        ),
    ],
    "generic": [
        _md_cell(
            "## NIR — Generic Execution\n\nWork with the compiled NIR graph directly."
        ),
        _code_cell(
            "import nir\n\n"
            "# The graph object from compile_to_nir is already available above.\n"
            "# Inspect nodes and edges:\n"
            "for node_id, node in graph.nodes.items():\n"
            "    print(f'  {node_id}: {type(node).__name__}')\n"
            "print(f'Edges: {list(graph.edges.keys())}')"
        ),
    ],
}

# Mirrors AKIDA_MODEL_BUNDLE_MAX_BYTES in
# Neurochip/neurochip/contracts/akida_model_bundle_contract.py -- the host
# rejects anything larger, so serving it would only move the failure later.
_AKIDA_BUNDLE_MAX_BYTES = 32 * 1024 * 1024

# A trained NIR graph for a PYNQ-Z2 network is tiny: overlay-v1 caps a network at
# 15360 int8 synapses, so even at float64 the weight payload is well under a
# megabyte. The cap exists to refuse an unrelated large `.nir` (an imported CNN,
# say) before it is base64'd through the API, not to bound legitimate use.
_TRAINED_NIR_MAX_BYTES = 8 * 1024 * 1024

# An evaluation set, unlike a model, scales with sample count: the MNIST test
# split at 784 float32 features is ~6 MB for 2000 samples. 64 MB leaves room for
# a realistic eval split while still refusing a full training corpus, which has
# no business being pulled through this endpoint one sample at a time.
_EVAL_DATASET_MAX_BYTES = 64 * 1024 * 1024

# How long a decoded eval set is reused before the workspace is listed again.
# Stepping through sample indices must not refetch and re-decode megabytes per
# click; a dataset only changes when the pipeline is re-run, so a short window
# costs nothing and bounds the staleness.
_EVAL_DATASET_CACHE_TTL_SECONDS = 60.0

# workspace folder -> (expires_at, filename, modified_at, data (N, T, F), labels (N,))
_eval_dataset_cache: dict[
    str, tuple[float, str, float, np.ndarray[Any, Any], np.ndarray[Any, Any]]
] = {}


def _jupyter_tree_url(workspace_folder: str) -> str:
    """Compatibility facade for the extracted publishing service."""
    return jupyter_tree_url(JUPYTER_PUBLIC_URL, workspace_folder)


def _publish_via_contents_api(
    workspace_folder: str,
    files: list[tuple[str, dict[str, Any]]],
    artifacts: dict[str, bytes] | None = None,
) -> None:
    """Compatibility facade for the extracted publishing service."""
    publish_via_contents_api(
        JUPYTER_WORKER_URL,
        workspace_folder,
        files,
        artifacts,
    )


def _fetch_notebook_last_modified(relative_path: str) -> float | None:
    """Compatibility facade for the extracted publishing service."""
    return fetch_notebook_last_modified(JUPYTER_WORKER_URL, relative_path)


# ── juv delta-dep helpers ─────────────────────────────────────────────────────


# ── Endpoint ──────────────────────────────────────────────────────────────────


@router.post("/notebook/ensure-workspace", response_model=EnsureWorkspaceResponse)
def ensure_workspace(request: EnsureWorkspaceRequest) -> EnsureWorkspaceResponse:
    workspace_folder = _slugify(request.workspace_path)
    if JUPYTER_WORKER_URL:
        _publish_via_contents_api(workspace_folder, [])
    else:
        (NOTEBOOK_DIR / workspace_folder / "notebooks").mkdir(
            parents=True, exist_ok=True
        )
    return EnsureWorkspaceResponse(workspace_folder=f"{workspace_folder}/notebooks")


# ── Pipeline-aware notebook generation (generate-v2) ─────────────────────────

NMTK_EMIT_CELL_SOURCE = """\
import json as _json


def _nmtk_emit(
    epoch: int, total: int, loss: float, accuracy: float, layer_rates: dict,
    phase: str = "train",
) -> None:
    print(
        _json.dumps(
            {
                "__nmtk_progress__": True,
                "epoch": epoch,
                "total_epochs": total,
                "loss": loss,
                "accuracy": accuracy,
                "layer_spike_rates": layer_rates,
                "phase": phase,
            }
        ),
        flush=True,
    )


def _nmtk_emit_activity(epoch: int, activity_npy_b64: str) -> None:
    # Deliberately a separate marker line from _nmtk_emit above: the payload
    # is a full per-neuron activity zip (could be sizeable), so it must never
    # be mixed into the small, frequent per-epoch progress line. `epoch`
    # tags which epoch this capture belongs to, so the runner can keep one
    # capture per epoch instead of overwriting a single last-value slot.
    print(
        _json.dumps(
            {
                "__nmtk_activity__": True,
                "epoch": epoch,
                "activity_npy_b64": activity_npy_b64,
            }
        ),
        flush=True,
    )
"""


def _payload_to_pipeline_config(cfg: PipelineConfigPayload) -> NirCnlPipelineConfig:
    """Convert a full `PipelineConfigPayload` into the CNL renderer's
    `PipelineConfig` shape for `/notebook/generate-pipeline-cnl`.

    Every `PipelineConfigPayload` field always has a concrete value (no
    `None`s), so this is a direct field mapping — the renderer simply
    skips falsy/absent fields when deciding which sentences to emit.
    """
    return NirCnlPipelineConfig(
        epochs=cfg.epochs,
        learning_rate=cfg.learning_rate,
        batch_size=cfg.batch_size,
        optimizer=cfg.optimizer,
        training_strategy=cfg.training_strategy,
        loss_function=cfg.loss_function,
        run_evaluation=cfg.run_evaluation,
        eval_metrics=tuple(cfg.eval_metrics) if cfg.eval_metrics else None,
        export_nir=cfg.export_nir,
        generate_py_download=cfg.generate_py_download,
    )


def _merge_cnl_pipeline_config(
    cnl_cfg: NirCnlPipelineConfig | None, base_cfg: PipelineConfigPayload
) -> PipelineConfigPayload:
    """Merge a CNL-derived `PipelineConfig` onto `base_cfg`.

    Used by `/notebook/parse-pipeline-cnl`. Only the fields the CNL text
    actually specifies (non-`None` on `cnl_cfg`) override `base_cfg`;
    every other field — `dataset`, `framework`, `surrogate_*`,
    `nengo_*`, and any of the ten addressed fields the CNL text simply
    omits — keeps its `base_cfg` value unchanged. This is Phase 3 of
    the rollout: CNL is additive, `base_cfg` (JSON) stays authoritative
    for anything CNL doesn't mention.
    """
    if cnl_cfg is None:
        return base_cfg
    overrides: dict[str, object] = {
        field: value
        for field, value in {
            "epochs": cnl_cfg.epochs,
            "learning_rate": cnl_cfg.learning_rate,
            "batch_size": cnl_cfg.batch_size,
            "optimizer": cnl_cfg.optimizer,
            "training_strategy": cnl_cfg.training_strategy,
            "loss_function": cnl_cfg.loss_function,
            "run_evaluation": cnl_cfg.run_evaluation,
            "eval_metrics": (
                list(cnl_cfg.eval_metrics) if cnl_cfg.eval_metrics is not None else None
            ),
            "export_nir": cnl_cfg.export_nir,
            "generate_py_download": cnl_cfg.generate_py_download,
        }.items()
        if value is not None
    }
    return base_cfg.model_copy(update=overrides) if overrides else base_cfg


def _dag_node_code(
    node: DagNodePayload, cfg: PipelineConfigPayload, dataset: str
) -> str | None:
    return dag_node_code(
        node, cfg, dataset, custom_code_resolver=_custom_pipeline_node_code
    )


@router.post("/notebook/templates/akida-mnist", response_model=GenerateV2Response)
def generate_akida_mnist_notebook(
    request: AkidaMnistNotebookRequest,
) -> GenerateV2Response:
    """Publish the full-MNIST PyTorch→ONNX Akida companion into Studio."""
    workspace_folder = (
        _slugify(request.workspace_path) if request.workspace_path else "akida-mnist"
    )
    generated_at = datetime.now(UTC)
    timestamp = generated_at.strftime("%Y-%m-%d %H:%M UTC")
    filename = "akida_mnist_companion.ipynb"
    notebook = _build_akida_mnist_notebook(timestamp)
    built = [(filename, notebook)]
    if JUPYTER_WORKER_URL:
        _publish_via_contents_api(workspace_folder, built, {})
        _mirror_generated_notebook_files(workspace_folder, built, {})
    else:
        output_dir = NOTEBOOK_DIR / workspace_folder / "notebooks"
        output_dir.mkdir(parents=True, exist_ok=True)
        (output_dir / filename).write_text(
            json.dumps(notebook, indent=2), encoding="utf-8"
        )
    relative_dir = f"{workspace_folder}/notebooks"
    return GenerateV2Response(
        workspace_folder=relative_dir,
        notebooks=[
            NotebookEntry(
                filename=filename,
                target="akida2",
                support_level="hardware-conversion",
                diagnostics=[
                    "Physical hardware verification occurs in the Akida panel."
                ],
            )
        ],
        jupyter_url=_jupyter_tree_url(relative_dir),
        generated_at=generated_at.timestamp(),
        # The companion is a self-contained, runnable demo: it trains its own CNN
        # in-notebook rather than going through Studio's optimiser loop, so Play
        # executing it is correct even though `akida` is not a trainable target.
        trainable=True,
    )


def _discover_workspace_artifact(
    workspace_folder: str,
    *,
    suffix: str,
    max_bytes: int,
    oversize_hint: str,
    missing_hint: str,
    name_prefix: str = "",
) -> _WorkspaceArtifact:
    """Compatibility facade for the extracted artifact-discovery service."""
    return discover_workspace_artifact(
        workspace_folder,
        suffix=suffix,
        max_bytes=max_bytes,
        oversize_hint=oversize_hint,
        missing_hint=missing_hint,
        notebook_dir=NOTEBOOK_DIR,
        jupyter_worker_url=JUPYTER_WORKER_URL,
        slugify=_slugify,
        name_prefix=name_prefix,
    )


@router.get(
    "/notebook/artifacts/latest-akida-bundle",
    response_model=AkidaBundleArtifactResponse,
)
def latest_akida_bundle(workspace_folder: str) -> AkidaBundleArtifactResponse:
    """Find and return the newest Akida bundle without asking for a path."""
    import base64

    artifact = _discover_workspace_artifact(
        workspace_folder,
        suffix=".akida-bundle.zip",
        max_bytes=_AKIDA_BUNDLE_MAX_BYTES,
        oversize_hint="lower the exporter's Eval samples",
        missing_hint=(
            "Either run the MNIST companion notebook, or add an Akida Exporter "
            "node to your Training canvas and run the pipeline."
        ),
    )
    return AkidaBundleArtifactResponse(
        filename=artifact.filename,
        bundle_base64=base64.b64encode(artifact.content).decode("ascii"),
        sha256=hashlib.sha256(artifact.content).hexdigest(),
        modified_at=artifact.modified_at,
        schema_version=_bundle_schema_version(artifact.content),
    )


@router.get(
    "/notebook/artifacts/latest-trained-nir",
    response_model=TrainedNirArtifactResponse,
)
def latest_trained_nir(workspace_folder: str) -> TrainedNirArtifactResponse:
    """Find and return the newest trained NIR graph without asking for a path.

    The NIR Exporter canvas node writes this after loading `best_model.pt` and
    overlaying the learned weights onto the graph, so unlike the CNL spec — which
    carries tensor *shape* only — this file holds real values. It is the only
    artifact a target without its own bundle format can get trained weights from.
    """
    import base64

    artifact = _discover_workspace_artifact(
        workspace_folder,
        suffix=".nir",
        max_bytes=_TRAINED_NIR_MAX_BYTES,
        oversize_hint=(
            "a network this large cannot fit a fixed hardware overlay anyway"
        ),
        missing_hint=(
            "Add a NIR Exporter node to your Training canvas and run the "
            "pipeline; it writes the trained graph after training finishes."
        ),
    )
    return TrainedNirArtifactResponse(
        filename=artifact.filename,
        nir_base64=base64.b64encode(artifact.content).decode("ascii"),
        sha256=hashlib.sha256(artifact.content).hexdigest(),
        modified_at=artifact.modified_at,
    )


def _load_eval_dataset(
    workspace_folder: str,
) -> tuple[str, float, np.ndarray[Any, Any], np.ndarray[Any, Any]]:
    """Return the workspace's evaluation set as ``(filename, mtime, data, labels)``.

    Cached for [_EVAL_DATASET_CACHE_TTL_SECONDS] because the caller steps
    through sample indices one click at a time and the file is megabytes.
    """
    import time

    cached = _eval_dataset_cache.get(workspace_folder)
    now = time.monotonic()
    if cached is not None and cached[0] > now:
        _, filename, modified_at, data, labels = cached
        return filename, modified_at, data, labels

    artifact = _discover_workspace_artifact(
        workspace_folder,
        suffix=".pt",
        name_prefix="eval_",
        max_bytes=_EVAL_DATASET_MAX_BYTES,
        oversize_hint="evaluate on fewer samples",
        missing_hint=(
            "Run the pipeline's Evaluate step; it writes the evaluation set "
            "next to the trained model, and that file is what a board sample "
            "is taken from."
        ),
    )
    try:
        data, labels = pt_dense_tensors(
            io.BytesIO(artifact.content), label=artifact.filename
        )
    except DatasetLoadError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc

    _eval_dataset_cache[workspace_folder] = (
        now + _EVAL_DATASET_CACHE_TTL_SECONDS,
        artifact.filename,
        artifact.modified_at,
        data,
        labels,
    )
    return artifact.filename, artifact.modified_at, data, labels


@router.get(
    "/notebook/artifacts/dataset-sample",
    response_model=DatasetSampleResponse,
)
def dataset_sample(workspace_folder: str, index: int = 0) -> DatasetSampleResponse:
    """Return one evaluation sample as an input frame a spiking target can run.

    The frame is binarised because that is the only input the PYNQ-Z2 overlay
    accepts — a pixel either spikes or it does not. That is coarser than the
    greyscale the model was trained on, so board accuracy sits below the
    simulation figure; the caller says so next to the sample rather than
    letting the difference look like a fault.
    """
    filename, modified_at, data, labels = _load_eval_dataset(workspace_folder)

    sample_count = int(data.shape[0])
    if sample_count == 0:
        raise HTTPException(
            status_code=422,
            detail=f"{filename!r} holds no samples, so there is nothing to run on the board.",
        )
    if index < 0 or index >= sample_count:
        raise HTTPException(
            status_code=404,
            detail=(
                f"Sample {index} does not exist — {filename!r} holds {sample_count} "
                f"samples, numbered 0 to {sample_count - 1}."
            ),
        )

    # (T, F) for this sample. A static image has T == 1; an event recording is
    # collapsed to "did this input ever spike during the presentation", which is
    # what a repeated static frame means to the overlay anyway.
    frame = np.asarray(data[index]) > 0
    if frame.ndim > 1:
        frame = frame.any(axis=0)
    spikes = [int(value) for value in frame.reshape(-1)]

    label: int | None = None
    if labels.size > index:
        label = int(labels[index])

    return DatasetSampleResponse(
        filename=filename,
        sample_index=index,
        sample_count=sample_count,
        input_width=len(spikes),
        label=label,
        input_spikes=spikes,
        spike_count=sum(spikes),
        modified_at=modified_at,
    )


def _bundle_schema_version(bundle: bytes) -> int:
    """Read `schemaVersion` out of a bundle's manifest, or 0 if unreadable.

    Discovery picks by mtime alone, and a workspace can legitimately hold both
    the V1 MNIST companion bundle and a V2 canvas one, so the caller has to be
    able to report which it received. Never raises: an unreadable archive is
    still worth returning, and the host validates it properly anyway.
    """
    try:
        with zipfile.ZipFile(io.BytesIO(bundle)) as archive:
            manifest = json.loads(archive.read("manifest.json"))
        return int(manifest.get("schemaVersion", 0))
    except Exception:  # noqa: BLE001 - a malformed bundle is the host's to reject
        return 0


@router.post("/notebook/generate-v2", response_model=GenerateV2Response)
def generate_notebook_v2(request: GenerateV2Request) -> GenerateV2Response:
    """Pipeline-aware notebook generation endpoint.

    Accepts both a CNL spec (from the Architecture canvas tab) and a
    PipelineConfigPayload (from the Pipeline canvas tab) and generates
    a structured 4-section Jupyter notebook:

        1. Config cell (always editable — no regeneration needed to tune LR/epochs)
        2. Architecture (compiled from CNL via NIR)
        3. Train (framework-specific, reads from config cell)
        4. Evaluate (conditional)
        5. Infer / Export (conditional)

    The separation between spec and pipeline_config enforces the tab-discriminator
    rule: architecture/biological intent stays in CNL; execution parameters stay
    in the config JSON and are surfaced directly in the notebook.
    """
    try:
        return _generate_notebook_v2_inner(request)
    except HTTPException:
        raise
    except Exception as exc:  # noqa: BLE001 - boundary logs unexpected failures
        _logger.exception("notebook_generation_failed")
        raise HTTPException(
            status_code=422,
            detail={
                "code": "notebook_generation_failed",
                "message": "Notebook generation failed. Check the pipeline diagnostics and try again.",
                "retryable": False,
            },
        ) from exc


def _generate_notebook_v2_inner(request: GenerateV2Request) -> GenerateV2Response:
    if not request.spec.strip():
        raise HTTPException(status_code=422, detail="spec must not be empty")

    try:
        graph = compile_to_nir(request.spec)
    except CompileError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    except Exception as exc:
        raise HTTPException(
            status_code=422, detail=f"Unexpected error compiling spec: {exc}"
        ) from exc

    # Before anything is generated: the data's feature width has to be able to
    # reach the first weighted layer. Runs here, ahead of
    # _collect_uploaded_dataset_artifacts, because that rewrites dataset_path to
    # a bare artifact name and the file would no longer be findable on disk.
    try:
        _check_input_width_against_datasets(graph, request.pipeline_phases)
    except GraphWidthMismatchError as exc:
        raise HTTPException(status_code=422, detail=exc.detail) from exc

    placeholder_weight_nodes: list[str] = []
    if request.import_id:
        raw_bytes = load_nir_import(request.import_id)
        original_graph: nir.NIRGraph | None = None
        if raw_bytes is not None:
            try:
                original_graph = nir.read(io.BytesIO(raw_bytes))
            except Exception:
                original_graph = None
        if original_graph is not None:
            placeholder_weight_nodes = _transplant_real_weights(graph, original_graph)
        else:
            # import_id was supplied but the sidecar is gone/invalid — every
            # weighted node in this graph is a placeholder, not just some.
            placeholder_weight_nodes = _graph_weighted_node_names(graph)
    elif _phase_has_eval_loop(
        request.pipeline_phases.eval
    ) and not _phase_has_training_loop(request.pipeline_phases.train):
        placeholder_weight_nodes = _graph_weighted_node_names(graph)

    block_placeholder_eval = bool(
        placeholder_weight_nodes and _phase_has_eval_loop(request.pipeline_phases.eval)
    )

    dataset_artifacts: dict[str, bytes] = {}
    if JUPYTER_WORKER_URL:
        dataset_artifacts = _collect_uploaded_dataset_artifacts(request.pipeline_phases)

    try:
        cfg = request.pipeline_config
        workspace_folder = (
            _slugify(request.workspace_path) if request.workspace_path else "pipeline"
        )
        generated_at = datetime.now(UTC)
        timestamp = generated_at.strftime("%Y-%m-%d %H:%M UTC")

        filename = f"pipeline_{cfg.framework}.ipynb"
        nb, artifacts = _build_v2_notebook(
            request.spec,
            graph,
            cfg,
            timestamp,
            pipeline_phases=request.pipeline_phases,
            pipeline_cnl=request.pipeline_cnl,
            placeholder_weight_nodes=placeholder_weight_nodes,
            block_placeholder_eval=block_placeholder_eval,
        )
        artifacts.update(dataset_artifacts)
        built = [(filename, nb)]
    except (NotImplementedError, ValueError) as exc:
        raise HTTPException(
            status_code=422,
            detail={
                "code": "notebook_codegen_unsupported",
                "message": str(exc),
                "retryable": False,
            },
        ) from exc
    except Exception as exc:  # noqa: BLE001 - boundary logs unexpected failures
        _logger.exception("notebook_assembly_failed")
        raise HTTPException(
            status_code=422,
            detail={
                "code": "notebook_generation_failed",
                "message": "The notebook could not be assembled.",
                "retryable": False,
            },
        ) from exc

    if JUPYTER_WORKER_URL:
        _publish_via_contents_api(workspace_folder, built, artifacts)
        _mirror_generated_notebook_files(workspace_folder, built, artifacts)
    else:
        output_dir = NOTEBOOK_DIR / workspace_folder / "notebooks"
        output_dir.mkdir(parents=True, exist_ok=True)
        (output_dir / filename).write_text(json.dumps(nb, indent=2), encoding="utf-8")
        for art_name, art_bytes in artifacts.items():
            (output_dir / art_name).write_bytes(art_bytes)

    _, classification, _ = _flatten_and_classify(graph, cfg.framework)

    rel_dir = f"{workspace_folder}/notebooks"
    return GenerateV2Response(
        workspace_folder=rel_dir,
        notebooks=[
            NotebookEntry(
                filename=filename,
                target=cfg.framework,
                support_level=classification.level if classification else None,
                diagnostics=classification.diagnostics if classification else [],
            )
        ],
        jupyter_url=_jupyter_tree_url(rel_dir),
        generated_at=generated_at.timestamp(),
        trainable=cfg.framework in _TRAINABLE_NOTEBOOK_TARGETS,
        not_trainable_reason=_not_trainable_reason(cfg.framework),
    )


@router.get("/notebook/last-modified", response_model=NotebookLastModifiedResponse)
def get_notebook_last_modified(
    workspace_folder: str, filename: str
) -> NotebookLastModifiedResponse:
    """Current last-modified time of a generated notebook, for edit detection.

    Checked by the Run step before regenerating: if the notebook was touched
    since its `generated_at` timestamp (e.g. edited live in the embedded
    JupyterLab view in the Notebook step), the caller should ask before
    overwriting it.
    """
    relative_path = f"{workspace_folder}/{filename}"
    if JUPYTER_WORKER_URL:
        last_modified = _fetch_notebook_last_modified(relative_path)
        if last_modified is not None:
            return NotebookLastModifiedResponse(last_modified=last_modified)
    local_path = NOTEBOOK_DIR / relative_path
    if local_path.exists():
        return NotebookLastModifiedResponse(last_modified=local_path.stat().st_mtime)
    return NotebookLastModifiedResponse(last_modified=None)


@router.post("/notebook/generate-pipeline-cnl", response_model=PipelineCnlResponse)
def generate_pipeline_cnl(request: PipelineCnlRequest) -> PipelineCnlResponse:
    """Render the current Pipeline-tab config as CNL text (for preview)."""
    cnl_cfg = _payload_to_pipeline_config(request.pipeline_config)
    try:
        text = NIR_Renderer().render_pipeline_config(cnl_cfg)
    except (ValueError, RenderError) as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    return PipelineCnlResponse(cnl_text=text)


@router.post("/notebook/parse-pipeline-cnl", response_model=ParsePipelineCnlResponse)
def parse_pipeline_cnl(request: ParsePipelineCnlRequest) -> ParsePipelineCnlResponse:
    """Parse Train/Evaluate/Export CNL text and merge it onto `pipeline_config`.

    Fail-closed: a malformed sentence (e.g. an unknown optimizer phrase)
    raises HTTP 422 rather than silently dropping it, matching
    `compile_to_nir`'s existing contract. Only fields the CNL text
    actually specifies override `pipeline_config`.
    """
    if not request.cnl_text.strip():
        return ParsePipelineCnlResponse(pipeline_config=request.pipeline_config)
    try:
        cnl_cfg = compile_pipeline_config(request.cnl_text)
    except CompileError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    merged = _merge_cnl_pipeline_config(cnl_cfg, request.pipeline_config)
    return ParsePipelineCnlResponse(pipeline_config=merged)


@router.post("/notebook/preview", response_model=DeployPreviewResponse)
def preview_notebook_codegen(request: DeployPreviewRequest) -> DeployPreviewResponse:
    """Side-effect-free codegen preview for the Studio Hardware Deployment
    panel. Mirrors /simulators/preflight's contract — never touches disk or
    Jupyter, reuses the exact same classification + codegen dispatch as
    /notebook/generate-v2 via _flatten_and_classify/_generate_arch_code.
    """
    if not request.spec.strip():
        raise HTTPException(status_code=422, detail="spec must not be empty")

    try:
        graph = compile_to_nir(request.spec)
    except CompileError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    except Exception as exc:
        raise HTTPException(
            status_code=422, detail=f"Unexpected error compiling spec: {exc}"
        ) from exc

    graph, classification, cnl_flattened = _flatten_and_classify(graph, request.target)
    try:
        arch_code, _, io_error = _generate_arch_code(
            request.target,
            graph,
            PipelineConfigPayload(framework=request.target),
            cnl_flattened,
            request.spec,
        )
    except Exception as exc:
        raise HTTPException(
            status_code=422, detail=f"Preview generation failed: {exc}"
        ) from exc

    return DeployPreviewResponse(
        target=request.target,
        support_level=classification.level if classification else None,
        diagnostics=classification.diagnostics if classification else [],
        io_error=io_error,
        code=arch_code,
    )


def _parse_juv_deps(nb_content: dict[str, Any]) -> list[str]:
    """Extract the dependency list from a notebook's hidden PEP 723 juv cell.

    Returns an empty list if the notebook has no juv cell or the cell is malformed.
    """
    cells = nb_content.get("cells", [])
    if not cells:
        return []
    first = cells[0]
    if first.get("cell_type") != "code":
        return []
    if not first.get("metadata", {}).get("jupyter", {}).get("source_hidden"):
        return []
    source = "".join(first.get("source", []))
    if "# /// script" not in source:
        return []
    deps: list[str] = []
    in_deps = False
    for line in source.splitlines():
        stripped = line.lstrip("#").strip()
        if stripped.startswith("dependencies"):
            in_deps = True
            continue
        if in_deps:
            if stripped.startswith("]"):
                break
            # Each line looks like: "norse>=0.0.7",
            import re as _re

            m = _re.match(r'"([^"]+)"', stripped.rstrip(",").strip())
            if m:
                deps.append(m.group(1))
    return deps


@router.post(
    "/notebook/provision-from-notebook", response_model=ProvisionFromNotebookResponse
)
def provision_from_notebook(
    request: ProvisionFromNotebookRequest,
) -> ProvisionFromNotebookResponse:
    """Read a notebook's juv cell and provision a matching kernel env via the Jupyter worker.

    Called by the NMTK client immediately after a hub download.  If the notebook
    carries delta deps (custom/extended kernel), the Jupyter env manager creates a
    matching environment so the kernel is ready before the user opens the notebook.
    Returns ``provisioned: false`` (not an error) when no deps are found or the
    Jupyter worker is unreachable — the user can still open the notebook and pick a kernel.
    """
    if not JUPYTER_WORKER_URL:
        return ProvisionFromNotebookResponse(
            provisioned=False,
            reason="Jupyter worker URL not configured (standalone dev mode).",
        )

    deps = _parse_juv_deps(request.notebook_content)
    if not deps:
        return ProvisionFromNotebookResponse(
            provisioned=False,
            reason="Notebook has no juv dependency metadata.",
        )

    import httpx  # noqa: PLC0415

    requirements_text = "\n".join(deps) + "\n"
    try:
        resp = httpx.post(
            f"{JUPYTER_WORKER_URL}/nmtk-envs/api/environments",
            json={
                "displayName": request.display_name,
                "requirements": requirements_text,
            },
            timeout=15.0,
        )
    except httpx.HTTPError as exc:
        raise HTTPException(
            status_code=503,
            detail=(
                "Could not reach the Jupyter worker to provision the environment. "
                "Make sure the jupyter-server service is running, then retry."
            ),
        ) from exc

    if resp.status_code not in (200, 201, 202):
        raise HTTPException(
            status_code=502,
            detail=(
                f"Jupyter env manager rejected provisioning request "
                f"(HTTP {resp.status_code}). Check the jupyter-server logs."
            ),
        )

    data = resp.json()
    job_id = data.get("jobId", "")
    job_url = f"{JUPYTER_WORKER_URL}/nmtk-envs/api/jobs/{job_id}" if job_id else ""
    return ProvisionFromNotebookResponse(provisioned=True, job_url=job_url)


@router.get("/notebook/target-availability", response_model=dict[str, bool])
def get_target_availability() -> dict[str, bool]:
    """Return which notebook targets have their backing framework installed."""
    from neurocnl.target_sdk import probe_target_availability

    return probe_target_availability()
