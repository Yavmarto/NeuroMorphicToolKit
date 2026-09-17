"""Generic lowering of CNLStudio-internal cnl.* nodes to standard NIR primitives.

Converters in ``neurocnl/converter/*.py`` (brian2_io, pynn_io, lava_io,
rockpool_io, sinabs_io, nengo_io) only dispatch on standard ``nir.*`` node
types. None of them recognize the CNLStudio-internal types defined in
``cnl_nodes.py`` (``Synaptic``, ``RSynaptic``, ``RLeaky``, ``Leaky``,
``BatchNorm1d``, ``Dropout``). :func:`flatten_cnl_ops` rewrites a graph so
those converters can consume it without any converter-specific handling.

``Leaky``/``Synaptic`` map 1:1 onto ``nir.LIF``/``nir.CubaLIF`` (same node
name, no edge changes). ``RLeaky``/``RSynaptic`` additionally gain a
same-population recurrent ``nir.Linear`` self-loop — the exact flat shape
``nengo_io.py`` already assumes exists (see its ``from_nir`` docstring and
``paper/03_rnn/nir_to_nengo.py``). ``BatchNorm1d``/``Dropout`` carry no
executable-relevant state at inference time and are spliced out.
"""

from __future__ import annotations

import math
from typing import Any

import nir
import numpy as np

from neurocnl._nir_compat import make_nir_cubalif, make_nir_graph, make_nir_lif
from neurocnl.lif_semantics import DEFAULT_LIF_DT_SECONDS, tau_seconds_from_decay
from neurocnl.runtime.cnl_nodes import (
    BatchNorm1d,
    Dropout,
    Leaky,
    RLeaky,
    RSynaptic,
    Synaptic,
)


def _tau_from_decay(decay: float, node: object) -> float:
    """Convert a cnl.* per-step decay back into a seconds-valued time constant.

    Unit invariant this function exists to hold: ``cnl.*`` ``alpha``/``beta``
    are **dimensionless per-step decays** at the ``dt`` recorded in the node's
    ``metadata["dt"]``; ``nir.LIF.tau`` is **seconds**. The conversion is
    ``tau = dt / (1 - beta)``, the exact inverse of
    :func:`~neurocnl.lif_semantics.decay_from_tau`.

    The previous implementation returned ``-1/log(decay)``, which is a time
    constant in *timesteps* written into a seconds-typed field — the producer
    side of the mixed-unit graphs this module now avoids.
    """
    metadata = getattr(node, "metadata", None) or {}
    dt = DEFAULT_LIF_DT_SECONDS
    try:
        candidate = float(metadata.get("dt", DEFAULT_LIF_DT_SECONDS))
        if math.isfinite(candidate) and candidate > 0:
            dt = candidate
    except (TypeError, ValueError):
        pass

    try:
        return tau_seconds_from_decay(decay, dt)
    except ValueError:
        # A decay outside (0, 1) cannot describe a leaky membrane. Fall back to
        # the timestep itself rather than emitting a negative or infinite tau,
        # which would fail validation far from the real cause.
        return dt


def _reset_kwargs(
    reset_mechanism: str, n_neurons: int
) -> dict[str, np.ndarray[Any, np.dtype[np.float64]]]:
    if reset_mechanism == "zero":
        return {"v_reset": np.zeros(n_neurons)}
    return {}


def _unique_name(base: str, taken: set[str]) -> str:
    name = base
    while name in taken:
        name += "_"
    return name


def flatten_cnl_ops(graph: nir.NIRGraph) -> tuple[nir.NIRGraph, list[str]]:
    """Rewrite CNLStudio-internal cnl.* nodes into standard NIR primitives.

    Returns a new graph (the input is never mutated) plus a list of
    human-readable diagnostic strings describing every lossy or synthesized
    substitution made. Idempotent and a no-op (equivalent graph, empty
    diagnostics) when the input contains no cnl.* nodes.
    """
    nodes: dict[str, object] = dict(graph.nodes)
    edges: list[tuple[str, str]] = list(graph.edges)
    diagnostics: list[str] = []

    for name, node in list(graph.nodes.items()):
        if isinstance(node, Leaky):
            nodes[name] = make_nir_lif(
                tau=np.full(node.n_neurons, _tau_from_decay(node.beta, node)),
                r=np.ones(node.n_neurons),
                v_leak=np.zeros(node.n_neurons),
                v_threshold=np.full(node.n_neurons, node.threshold),
                **_reset_kwargs(node.reset_mechanism, node.n_neurons),
            )
            if node.reset_mechanism == "zero":
                diagnostics.append(
                    f"cnl.Leaky {name!r} flattened to nir.LIF with v_reset=0 for "
                    "reset_mechanism='zero' — most converters do not read v_reset "
                    "today and will apply subtract-style reset regardless."
                )

        elif isinstance(node, Synaptic):
            nodes[name] = make_nir_cubalif(
                tau_syn=np.full(node.n_neurons, _tau_from_decay(node.alpha, node)),
                tau_mem=np.full(node.n_neurons, _tau_from_decay(node.beta, node)),
                r=np.ones(node.n_neurons),
                v_leak=np.zeros(node.n_neurons),
                v_threshold=np.full(node.n_neurons, node.threshold),
                w_in=np.ones(node.n_neurons),
                **_reset_kwargs(node.reset_mechanism, node.n_neurons),
            )
            if node.reset_mechanism == "zero":
                diagnostics.append(
                    f"cnl.Synaptic {name!r} flattened to nir.CubaLIF with v_reset=0 "
                    "for reset_mechanism='zero' — most converters do not read "
                    "v_reset today and will apply subtract-style reset regardless."
                )

        elif isinstance(node, RLeaky | RSynaptic):
            if isinstance(node, RLeaky):
                nodes[name] = make_nir_lif(
                    tau=np.full(node.n_neurons, _tau_from_decay(node.beta, node)),
                    r=np.ones(node.n_neurons),
                    v_leak=np.zeros(node.n_neurons),
                    v_threshold=np.full(node.n_neurons, node.threshold),
                    **_reset_kwargs(node.reset_mechanism, node.n_neurons),
                )
                base_type = "cnl.RLeaky"
            else:
                nodes[name] = make_nir_cubalif(
                    tau_syn=np.full(node.n_neurons, _tau_from_decay(node.alpha, node)),
                    tau_mem=np.full(node.n_neurons, _tau_from_decay(node.beta, node)),
                    r=np.ones(node.n_neurons),
                    v_leak=np.zeros(node.n_neurons),
                    v_threshold=np.full(node.n_neurons, node.threshold),
                    w_in=np.ones(node.n_neurons),
                    **_reset_kwargs(node.reset_mechanism, node.n_neurons),
                )
                base_type = "cnl.RSynaptic"

            rec_name = _unique_name(f"{name}__rec", set(nodes))
            recurrent_weight = getattr(node, "recurrent_weight", None)
            if recurrent_weight is not None:
                rec_weight = np.asarray(recurrent_weight, dtype=float)
                diagnostics.append(
                    f"{base_type} {name!r} flattened to a neuron node plus recurrent "
                    f"nir.Linear {rec_name!r} — the recurrent weight was sourced from "
                    "a previously trained/imported checkpoint (RSynaptic.recurrent_weight)."
                )
            else:
                rec_weight = np.eye(node.n_neurons)
                diagnostics.append(
                    f"{base_type} {name!r} flattened to a neuron node plus recurrent "
                    f"nir.Linear {rec_name!r} — the recurrent weight is structural-only "
                    "(identity), not sourced from a trained checkpoint: this node has no "
                    "stored recurrent weight matrix."
                )
            nodes[rec_name] = nir.Linear(weight=rec_weight)
            edges.append((name, rec_name))
            edges.append((rec_name, name))
            if isinstance(node, RSynaptic) and node.use_bias:
                diagnostics.append(
                    f"cnl.RSynaptic {name!r} has use_bias=True but no stored bias "
                    f"values — the flattened recurrent Linear {rec_name!r} has no bias."
                )

        elif isinstance(node, BatchNorm1d | Dropout):
            preds = [src for src, dst in edges if dst == name]
            succs = [dst for src, dst in edges if src == name]
            edges = [e for e in edges if name not in e]
            edges.extend((p, s) for p in preds for s in succs)
            del nodes[name]
            if isinstance(node, BatchNorm1d):
                diagnostics.append(
                    f"cnl.BatchNorm1d {name!r} has no stored running stats — passed "
                    "through as identity, not applied."
                )

    return make_nir_graph(nodes=nodes, edges=edges), diagnostics
