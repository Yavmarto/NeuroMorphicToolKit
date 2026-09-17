"""Pipeline-DAG payload models and node-type vocabulary.

These originated in ``backend/app/routers/notebook.py`` as the JSON shape
for the Training-tab's node-based DAG, consumed there to generate Jupyter
notebook code (``_dag_node_code``/``_phase_dag_to_code``). They live here
(inside the standalone-installable ``neurocnl`` package) so that
``neurocnl.training.dag_params.extract_training_params`` — the
``/training/run`` request path's DAG reader — doesn't need to reach across
the packaging boundary into ``backend`` (which isn't part of the ``neurocnl``
distribution and isn't importable once ``neurocnl`` is pip-installed in
isolation, e.g. in the ``suite_api``/``jupyter-server`` Docker images).

``backend/app/schemas/pipeline_dag.py`` re-imports these names unchanged;
this module must not change their shape without checking both consumers.
"""

from __future__ import annotations

from typing import Any

from pydantic import BaseModel, Field

# Keep synchronized with Flutter's ``PipelineDagNodeType`` enum. This full
# vocabulary is also the allowlist for reusable custom pipeline-node bases.
PIPELINE_NODE_TYPES = frozenset(
    {
        "dataLoader",
        "testLoader",
        "spikeEncoder",
        "spikeGenerator",
        "timeLoop",
        "validationLoop",
        "forwardPass",
        "spikeRecorder",
        "membraneRecorder",
        "stateReset",
        "spikeDomainFilter",
        "mseCountLoss",
        "ceCountLoss",
        "crossEntropyLoss",
        "membraneLoss",
        "l1SpikeReg",
        "l2SpikeReg",
        "surrogateBackward",
        "bpttBackward",
        "customGradientStep",
        "adamOptimiser",
        "sgdOptimiser",
        "adamwOptimiser",
        "rmspropOptimiser",
        "lbiOptimizer",
        "stepLR",
        "cosineAnnealingLR",
        "exponentialLR",
        "reduceLROnPlateau",
        "gradientClip",
        "weightClip",
        "earlyStopping",
        "accuracyMetric",
        "f1Score",
        "confusionMatrix",
        "lossLogger",
        "spikeRateLogger",
        "spikeCountMetric",
        "latencyMetric",
        "nirExporter",
        "akidaExporter",
        "pyExporter",
        "torchScriptExporter",
        "lavaProcessGraph",
        "lavaSim",
        "lavaHwConfig",
        "loihiExporter",
    }
)


class DagNodePayload(BaseModel):
    id: str
    type: str  # PipelineDagNodeType name (e.g. "dataLoader")
    parameters: dict[str, Any] = {}
    custom_component_id: str | None = None


class DagEdgePayload(BaseModel):
    id: str
    source_node_id: str
    source_port: str
    target_node_id: str
    target_port: str


class PhaseDAGPayload(BaseModel):
    nodes: list[DagNodePayload] = []
    edges: list[DagEdgePayload] = []


class PipelinePhasesPayload(BaseModel):
    train: PhaseDAGPayload = Field(default_factory=PhaseDAGPayload)
    eval: PhaseDAGPayload = Field(default_factory=PhaseDAGPayload)


# Node-type vocabulary shared by notebook codegen (``_training_phase_to_code``,
# ``_phase_has_eval_loop``) and the training-DAG parameter extractor
# (``neurocnl.training.dag_params.extract_training_params``).
_LOADER_TYPES = {"dataLoader", "spikeGenerator", "testLoader"}
_OPTIMISER_TYPES = {
    "adamOptimiser",
    "sgdOptimiser",
    "adamwOptimiser",
    "rmspropOptimiser",
    # `lbiOptimizer` (Linearized Bregman Iteration) — added for the Dynamic
    # Training Graph Executor's Step 7. Optimiser node types always run in
    # `StepRole.SETUP` (never per-batch) via `dag_topology.classify_phase`'s
    # `setup_types` union, which reads this set; without this entry
    # `lbiOptimizer` would fall into the per-batch body bucket instead, like
    # any unrecognised node type.
    "lbiOptimizer",
}
_SCHEDULER_TYPES = {"stepLR", "cosineAnnealingLR", "exponentialLR", "reduceLROnPlateau"}
_LOSS_TYPES = {"mseCountLoss", "ceCountLoss", "crossEntropyLoss", "membraneLoss"}
