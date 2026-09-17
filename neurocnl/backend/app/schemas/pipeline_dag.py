"""Pipeline-DAG payload models and node-type vocabulary.

Canonical definitions now live in ``neurocnl.training.dag_schema`` (moved
there so the standalone-installable ``neurocnl`` package doesn't need to
reach back into ``backend``, which broke ``pip install`` of ``neurocnl`` in
isolation, e.g. in the ``suite_api``/``jupyter-server`` Docker images).
Re-exported here unchanged for existing backend imports (``notebook.py``,
``schemas/training.py``).
"""

from __future__ import annotations

from neurocnl.training.dag_schema import (
    DagEdgePayload,
    DagNodePayload,
    PhaseDAGPayload,
    PipelinePhasesPayload,
    _LOADER_TYPES,
    _LOSS_TYPES,
    _OPTIMISER_TYPES,
    _SCHEDULER_TYPES,
)

__all__ = [
    # The node-type sets keep their leading underscore: `notebook.py` and
    # `schemas/training.py` import them by that name, and `dag_schema` is the
    # canonical definition site.
    "_LOADER_TYPES",
    "_LOSS_TYPES",
    "_OPTIMISER_TYPES",
    "_SCHEDULER_TYPES",
    "DagEdgePayload",
    "DagNodePayload",
    "PhaseDAGPayload",
    "PipelinePhasesPayload",
    "_LOADER_TYPES",
    "_LOSS_TYPES",
    "_OPTIMISER_TYPES",
    "_SCHEDULER_TYPES",
]
