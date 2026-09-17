"""Infer LIF population widths from adjacent Linear weight matrices.

The NIR CNL compiler often materialises ``nir.LIF`` nodes with scalar ``tau``
(``tau.size == 1``) regardless of the true population width. The width is
encoded in neighbouring ``nir.Linear`` / ``nir.Affine`` weight shapes instead.
Every simulator that builds one process per LIF must reconcile sizes the same
way or it will simulate a single neuron, truncate synaptic currents, and return
an empty spike raster while snnTorch (which reads weight shapes directly) fires.
"""

from __future__ import annotations

import logging
from typing import Any

import nir
import numpy as np

logger = logging.getLogger(__name__)


def reconcile_population_sizes_from_linear_weights(
    graph: nir.NIRGraph,
    population_sizes: dict[str, int],
) -> dict[str, int]:
    """Return *population_sizes* with scalar-tau populations widened from Linear weights.

    Only overrides entries currently at size ``1`` (the CNL scalar-tau pattern).
    Populations whose ``tau`` array already carries the true width are left
    untouched.
    """
    dense_nodes: dict[str, np.ndarray[Any, Any]] = {}
    for name, node in graph.nodes.items():
        if isinstance(node, nir.Linear | nir.Affine):
            dense_nodes[name] = np.asarray(node.weight, dtype=float)

    lin_pre: dict[str, list[str]] = {}
    lin_post: dict[str, list[str]] = {}
    for pre, post in graph.edges:
        if post in dense_nodes:
            lin_pre.setdefault(post, []).append(pre)
        if pre in dense_nodes:
            lin_post.setdefault(pre, []).append(post)

    inferred_sizes: dict[str, int] = {}
    for lin_name, weight in dense_nodes.items():
        if weight.ndim != 2:
            continue
        target_dim, source_dim = weight.shape
        for pre_pop in lin_pre.get(lin_name, []):
            if pre_pop in population_sizes and source_dim > 1:
                prev = inferred_sizes.get(pre_pop)
                if prev is not None and prev != source_dim:
                    logger.warning(
                        "Population %r size inferred as %d by one Linear but %d by %r;"
                        " keeping %d.",
                        pre_pop,
                        prev,
                        source_dim,
                        lin_name,
                        prev,
                    )
                else:
                    inferred_sizes[pre_pop] = source_dim
        for post_pop in lin_post.get(lin_name, []):
            if post_pop in population_sizes and target_dim > 1:
                prev = inferred_sizes.get(post_pop)
                if prev is not None and prev != target_dim:
                    logger.warning(
                        "Population %r size inferred as %d by one Linear but %d by %r;"
                        " keeping %d.",
                        post_pop,
                        prev,
                        target_dim,
                        lin_name,
                        prev,
                    )
                else:
                    inferred_sizes[post_pop] = target_dim

    reconciled = dict(population_sizes)
    for name, inferred in inferred_sizes.items():
        if reconciled.get(name) == 1:
            reconciled[name] = inferred
    return reconciled


def lif_population_size(node: nir.LIF | nir.CubaLIF) -> int:
    """Initial LIF width from membrane time-constant array size (often 1 for CNL)."""
    tau_arr = getattr(node, "tau", None)
    if tau_arr is None:
        tau_arr = getattr(node, "tau_mem", None)
    return int(tau_arr.size) if tau_arr is not None else 1
