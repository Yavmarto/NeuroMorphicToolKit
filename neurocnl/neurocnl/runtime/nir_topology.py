"""Generic NIR graph-topology classification and linearization.

Both rockpool_io.py and sinabs_io.py need to walk a compiled nir.NIRGraph in
execution order and reject genuinely branching/merging topologies, while
tolerating the single self-loop shape cnl_flatten.flatten_cnl_ops produces for
cnl.RSynaptic/cnl.RLeaky (a same-name neuron node plus a "{name}__rec"
nir.Linear node wired as a 2-cycle: (name, rec) and (rec, name) edges, with
all pre-existing edges left untouched).

A self-loop is legitimate exactly when its recurrent partner node has NO
edges other than the two forming the loop (isolated in-degree == out-degree
== 1, both pointing at the same neighbor). Any 2-cycle where the partner node
also has other real connections is treated as genuine branching/merging, not
tolerated recurrence — this only ever matches Phase C's synthesized shape (or
a hand-authored graph with the identical shape), never a real fan-out/fan-in.
"""

from __future__ import annotations

from typing import Any, Literal

import nir
import numpy as np

from neurocnl._nir_compat import make_nir_graph
from neurocnl.runtime.cnl_nodes import RSynaptic, Synaptic
from neurocnl.lif_semantics import decay_from_tau, resolve_dt
from neurocnl.runtime.snntorch_simulator import _lif_threshold

Topology = Literal["linear", "linear_with_recurrence", "branching"]


def _adjacency(
    graph: nir.NIRGraph,
) -> tuple[dict[str, list[str]], dict[str, list[str]]]:
    out_edges: dict[str, list[str]] = {name: [] for name in graph.nodes}
    in_edges: dict[str, list[str]] = {name: [] for name in graph.nodes}
    for src, dst in graph.edges:
        out_edges.setdefault(src, []).append(dst)
        in_edges.setdefault(dst, []).append(src)
    return out_edges, in_edges


def _self_loop_partners(graph: nir.NIRGraph) -> dict[str, str]:
    """Return {forward_node_name: recurrent_partner_name} for every isolated
    2-cycle in the graph — an edge (a, b) whose mirror (b, a) is also
    present, where b has no other edges at all.
    """
    edge_set = set(graph.edges)
    out_edges, in_edges = _adjacency(graph)
    partners: dict[str, str] = {}
    claimed: set[str] = set()
    for a, b in graph.edges:
        if a == b or b in claimed:
            continue
        if (b, a) in edge_set and out_edges[b] == [a] and in_edges[b] == [a]:
            partners[a] = b
            claimed.add(b)
    return partners


def recurrent_partner(graph: nir.NIRGraph, name: str) -> str | None:
    """Return `name`'s self-loop recurrent-partner node name, or None.

    linearize()'s return type is fixed at list[str], so it cannot embed the
    recurrent partner inline — query it here instead.
    """
    return _self_loop_partners(graph).get(name)


def classify_topology(graph: nir.NIRGraph) -> Topology:
    """Classify a NIR graph's shape for converters that require a (possibly
    self-loop-recurrent) single execution path.

    Returns
    -------
    "linear"                 -- strictly feed-forward, no cycles.
    "linear_with_recurrence" -- feed-forward except for one or more isolated
                                 2-cycle self-loops matching cnl_flatten's
                                 synthesized shape.
    "branching"               -- any node has >1 real (non-self-loop)
                                 outgoing or incoming edge -- true
                                 fan-out/fan-in, including a 2-cycle whose
                                 partner node has other edges.
    """
    if not graph.nodes:
        return "linear"

    out_edges, in_edges = _adjacency(graph)
    partners = _self_loop_partners(graph)

    for name in graph.nodes:
        loop_partner = partners.get(name)
        effective_out = [d for d in out_edges[name] if d != loop_partner]
        effective_in = [s for s in in_edges[name] if s != loop_partner]
        if len(effective_out) > 1 or len(effective_in) > 1:
            return "branching"

    return "linear_with_recurrence" if partners else "linear"


def linearize(graph: nir.NIRGraph) -> list[str]:
    """Return node names in forward execution order.

    Excludes nir.Input/nir.Output boundary nodes (neither carries a
    dispatchable module in any current converter) and each self-loop's
    recurrent-partner node (e.g. an "<name>__rec" nir.Linear from
    flatten_cnl_ops) — callers that need a node's recurrent partner call
    recurrent_partner(graph, name) separately.

    Raises
    ------
    ValueError
        If classify_topology(graph) == "branching", or if the graph has
        zero or more than one nir.Input node.
    """
    if classify_topology(graph) == "branching":
        raise ValueError(
            "Cannot linearize a branching/merging NIR graph; "
            "nir_topology.linearize only supports linear topologies, "
            "optionally with self-loop recurrence."
        )

    if not graph.nodes:
        return []

    input_names = [n for n, node in graph.nodes.items() if isinstance(node, nir.Input)]
    if not input_names:
        raise ValueError("No nir.Input node found in NIR graph.")
    if len(input_names) > 1:
        raise ValueError(
            f"Multiple nir.Input nodes found ({input_names!r}); "
            "nir_topology.linearize only supports single-input graphs."
        )

    partners = _self_loop_partners(graph)
    out_edges, _ = _adjacency(graph)

    ordered: list[str] = []
    visited: set[str] = set()
    current: str | None = input_names[0]
    while current is not None and current not in visited:
        ordered.append(current)
        visited.add(current)
        loop_partner = partners.get(current)
        forward = [d for d in out_edges.get(current, []) if d != loop_partner]
        current = forward[0] if forward else None

    return [name for name in ordered if not isinstance(graph.nodes[name], nir.Input | nir.Output)]


def _next_neuron_node(
    graph: nir.NIRGraph,
    out_edges: dict[str, list[str]],
    partners: dict[str, str],
    start: str,
) -> str | None:
    """Walk forward from `start` past non-neuron transform nodes (e.g.
    `nir.Linear`/`nir.Affine`), returning the name of the first
    `nir.LIF`/`nir.CubaLIF` node encountered.

    Returns None if the chain branches (more than one effective outgoing
    edge — should not happen once `classify_topology(graph) != "branching"`
    has already been checked by the caller), dead-ends, revisits a node, or
    reaches `nir.Output` before any neuron node.
    """
    current = start
    visited = {start}
    while True:
        loop_partner = partners.get(current)
        forward = [d for d in out_edges.get(current, []) if d != loop_partner]
        if len(forward) != 1:
            return None
        nxt = forward[0]
        if nxt in visited:
            return None
        node = graph.nodes[nxt]
        if isinstance(node, nir.LIF | nir.CubaLIF):
            return nxt
        if isinstance(node, nir.Output):
            return None
        visited.add(nxt)
        current = nxt


def _fused_decay(node: Any, attr: str, graph: nir.NIRGraph | None) -> float:
    """Per-step decay for a CubaLIF time constant at the graph's timestep.

    Falls back to a neutral 0.9 only when the time constant is missing or
    unusable — never as a silent substitute for a real value. The previous
    implementation ran every realistic tau through ``exp(-1/tau)`` and a
    ``[0.01, 0.99]`` clamp, which mapped *every* time constant below ~0.22 s to
    exactly 0.01: distinct taus in one graph collapsed to a single decay, and
    the result was persisted into saved workspaces.
    """
    tau = getattr(node, attr, None)
    if tau is None:
        return 0.9
    try:
        tau_mean = float(np.mean(np.asarray(tau, dtype=float)))
    except (TypeError, ValueError):
        return 0.9
    if not np.isfinite(tau_mean) or tau_mean <= 0:
        return 0.9

    dt, _ = resolve_dt(node, graph)
    try:
        return decay_from_tau(tau_mean, dt)
    except ValueError:
        # dt >= tau: the node cannot be represented as a decaying membrane at
        # this timestep. Keep the import working and let the simulators raise
        # the actionable error, rather than failing the canvas load.
        return 0.9


def _metadata_with_dt(node: Any, graph: nir.NIRGraph | None) -> dict[str, Any]:
    """Copy a node's metadata, stamping the dt its alpha/beta were taken at.

    ``cnl.*`` alpha/beta are dimensionless per-step decays; without the dt they
    were computed at there is no way to recover the original seconds-valued
    tau. Recording it here is what makes ``cnl_flatten``'s inverse exact.
    """
    metadata = dict(getattr(node, "metadata", None) or {})
    dt, _ = resolve_dt(node, graph)
    metadata.setdefault("dt", dt)
    return metadata


def fuse_recurrent_pairs(graph: nir.NIRGraph) -> nir.NIRGraph:
    """Fuse an imported `nir.CubaLIF` + self-loop `nir.Linear` pair into a
    single `cnl_nodes.RSynaptic` node — the import-side inverse of what
    `cnl_flatten.flatten_cnl_ops` does on export.

    Detection reuses `_self_loop_partners` but is narrower than "any
    self-loop": a self-loop is only fused when its forward node is
    `nir.CubaLIF` and its recurrent partner is `nir.Linear` — the exact
    shape `flatten_cnl_ops` produces for `cnl.RSynaptic`, and the shape a
    real trained CubaLIF-with-recurrence checkpoint takes once loaded via
    `nir.read()`. Any other self-loop shape (e.g. a plain `nir.LIF`
    self-loop, which would correspond to `cnl.RLeaky`) is left untouched;
    fusing that shape is out of scope here — Task 1 only targets
    CubaLIF+self-loop-Linear -> RSynaptic/Synaptic.

    `alpha`/`beta` on the fused `RSynaptic` are derived from the CubaLIF's
    `tau_syn`/`tau_mem` via `lif_semantics.decay_from_tau` at the graph's
    resolved timestep — the same conversion every backend uses, not re-derived
    here. The resolved `dt` is stamped onto the fused node's metadata so
    `cnl_flatten` can invert it exactly; `alpha`/`beta` are dimensionless
    per-step decays and are meaningless without the `dt` they were taken at.

    After fusing, the immediately-following neuron on the now-single
    execution path is found by walking forward from the fused node through
    any intervening non-neuron transform nodes (`nir.Linear`/`nir.Affine`/
    etc. — see `_next_neuron_node`). If — and only if — that next neuron is
    itself a `nir.CubaLIF`, it is retyped to `cnl_nodes.Synaptic` (never a
    global CubaLIF -> Synaptic promotion: a plain `nir.LIF` downstream
    neuron, or no neuron at all before `nir.Output`, is left untouched).
    This preserves the `"exact"` snntorch_sim fidelity `nir_support.py`
    grants `Synaptic`/`RSynaptic`, instead of the lossier
    `nir.CubaLIF` -> `snntorch.Leaky` approximation
    (`SnnTorchSimulatorAdapter` still maps bare `nir.CubaLIF` to
    `snntorch.Leaky`).

    Returns the input graph unchanged (never mutated) when
    `classify_topology(graph) == "branching"`, or when no self-loop matches
    the exact CubaLIF+Linear shape.
    """
    if classify_topology(graph) == "branching":
        return graph

    partners = _self_loop_partners(graph)
    if not partners:
        return graph

    fusable = {
        forward: partner
        for forward, partner in partners.items()
        if isinstance(graph.nodes[forward], nir.CubaLIF)
        and isinstance(graph.nodes[partner], nir.Linear)
    }
    if not fusable:
        return graph

    out_edges, _ = _adjacency(graph)
    nodes: dict[str, Any] = dict(graph.nodes)
    edges: list[tuple[str, str]] = list(graph.edges)

    for forward_name, partner_name in fusable.items():
        forward_node = graph.nodes[forward_name]
        partner_node = graph.nodes[partner_name]

        recurrent_weight = np.asarray(partner_node.weight, dtype=float).tolist()
        nodes[forward_name] = RSynaptic(
            n_neurons=int(np.asarray(forward_node.tau_mem, dtype=float).size),
            alpha=_fused_decay(forward_node, "tau_syn", graph),
            beta=_fused_decay(forward_node, "tau_mem", graph),
            threshold=_lif_threshold(forward_node),
            reset_mechanism="subtract",
            use_bias=False,
            metadata=_metadata_with_dt(forward_node, graph),
            recurrent_weight=recurrent_weight,
        )
        del nodes[partner_name]
        edges = [edge for edge in edges if partner_name not in edge]

        successor_name = _next_neuron_node(graph, out_edges, partners, forward_name)
        if (
            successor_name is not None
            and successor_name not in fusable
            and isinstance(graph.nodes[successor_name], nir.CubaLIF)
        ):
            # `successor_name not in fusable` guards against retyping a node
            # that is itself one of the fusable forward nodes (i.e. is
            # becoming/has become an RSynaptic via this same fusion pass).
            # `fusable` is computed once from the pristine graph, so this
            # check -- unlike reading `graph.nodes[...]` -- is independent
            # of `fusable.items()` iteration order: whichever forward node
            # is processed first or last, a sibling recurrent block's
            # output must never be clobbered back to plain Synaptic.
            successor_node = graph.nodes[successor_name]
            nodes[successor_name] = Synaptic(
                n_neurons=int(np.asarray(successor_node.tau_mem, dtype=float).size),
                alpha=_fused_decay(successor_node, "tau_syn", graph),
                beta=_fused_decay(successor_node, "tau_mem", graph),
                threshold=_lif_threshold(successor_node),
                reset_mechanism="subtract",
                metadata=_metadata_with_dt(successor_node, graph),
            )

    return make_nir_graph(nodes=nodes, edges=edges)
