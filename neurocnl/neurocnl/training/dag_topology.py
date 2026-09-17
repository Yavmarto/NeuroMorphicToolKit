"""Shared DAG-topology helpers for pipeline-DAG payloads.

Extracted out of ``backend/app/routers/notebook.py`` (Step 1 of the "Dynamic
Training Graph Executor" plan) so both the existing notebook-codegen path and
future live-execution code can share one topological-sort implementation and
one setup/body node classification, instead of each reimplementing Kahn's
algorithm and the node-type partition inline.

This module intentionally has zero FastAPI/backend dependencies — it only
depends on the payload models and node-type-set constants in
``neurocnl.training.dag_schema`` — so it stays importable from the
standalone-installable ``neurocnl`` package (see ``dag_schema.py``'s module
docstring for why that boundary matters).
"""

from __future__ import annotations

from dataclasses import dataclass, field

from neurocnl.training.dag_schema import (
    _LOADER_TYPES,
    _LOSS_TYPES,
    _OPTIMISER_TYPES,
    _SCHEDULER_TYPES,
    DagEdgePayload,
    DagNodePayload,
)

# Public names for the node-type-set constants that `dag_schema.py` defines
# as private (`_LOADER_TYPES` etc). `dag_schema.py` remains the canonical
# source of the values (existing importers — `backend/app/schemas/
# pipeline_dag.py` — import the private names directly from there); this
# module just re-exports them under public names for new code.
LOADER_TYPES = _LOADER_TYPES
OPTIMISER_TYPES = _OPTIMISER_TYPES
SCHEDULER_TYPES = _SCHEDULER_TYPES
LOSS_TYPES = _LOSS_TYPES


class CycleError(ValueError):
    """Raised by `topo_sort_nodes` when the DAG contains a real cycle."""


def topo_sort_nodes(
    nodes: list[DagNodePayload], edges: list[DagEdgePayload]
) -> list[DagNodePayload]:
    """Kahn's algorithm — returns nodes in execution order.

    Raises `CycleError` (a `ValueError`) if the graph contains a cycle (or any
    node otherwise unreachable via topological order), rather than silently
    appending the leftover nodes.
    """
    node_map = {n.id: n for n in nodes}
    in_degree: dict[str, int] = {n.id: 0 for n in nodes}
    adj: dict[str, list[str]] = {n.id: [] for n in nodes}
    for e in edges:
        if e.source_node_id in adj and e.target_node_id in in_degree:
            adj[e.source_node_id].append(e.target_node_id)
            in_degree[e.target_node_id] += 1
    queue = [n for n in nodes if in_degree[n.id] == 0]
    result: list[DagNodePayload] = []
    while queue:
        node = queue.pop(0)
        result.append(node)
        for nxt_id in adj[node.id]:
            in_degree[nxt_id] -= 1
            if in_degree[nxt_id] == 0:
                queue.append(node_map[nxt_id])
    seen = {n.id for n in result}
    leftover_ids = [n.id for n in nodes if n.id not in seen]
    if leftover_ids:
        raise CycleError(
            "Cycle detected in DAG topological sort; nodes not reachable in "
            f"dependency order: {leftover_ids}"
        )
    return result


@dataclass
class PhaseClassification:
    """Result of `classify_phase`: nodes split by execution lifecycle."""

    setup_nodes: list[DagNodePayload] = field(default_factory=list)
    body_nodes: list[DagNodePayload] = field(default_factory=list)
    post_training_nodes: list[DagNodePayload] = field(default_factory=list)


def classify_phase(nodes: list[DagNodePayload]) -> PhaseClassification:
    """Split training-phase nodes into setup-only vs. per-batch-body nodes.

    Reproduces the exact partition used by `notebook.py`'s
    `_training_phase_to_code`: loader/timeLoop/optimiser/scheduler/
    early-stopping/validationLoop nodes are setup-only (run once, outside the
    loop);
    `weightClip` nodes belong to neither bucket (the caller special-cases
    them for post-optimiser-step placement). Exporters run once after the
    final epoch; everything else is a body node that runs once per batch.
    """
    setup_types = (
        LOADER_TYPES
        | {"timeLoop"}
        | OPTIMISER_TYPES
        | SCHEDULER_TYPES
        | {"earlyStopping", "validationLoop"}
    )
    setup_nodes = [n for n in nodes if n.type in setup_types]
    post_training_types = {
        "nirExporter",
        "akidaExporter",
        "pyExporter",
        "torchScriptExporter",
    }
    body_nodes = [
        n
        for n in nodes
        if n.type not in setup_types
        and n.type != "weightClip"
        and n.type not in post_training_types
    ]
    post_training_nodes = [n for n in nodes if n.type in post_training_types]
    return PhaseClassification(
        setup_nodes=setup_nodes,
        body_nodes=body_nodes,
        post_training_nodes=post_training_nodes,
    )
