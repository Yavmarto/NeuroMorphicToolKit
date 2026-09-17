"""Canonical editor projection service.

All transformations between CNL text, canonical NetworkIR state, and the
canvas view go through this module. No regex repair; no silent semantic loss.
"""

from __future__ import annotations

import dataclasses
import logging
from collections import defaultdict
from typing import TYPE_CHECKING, Any

import nir
import numpy as np

from backend.app.services.nir_graph_serializer import serialize_nir_to_canvas_graph
from neurocnl.cnl.document import deserialize_ir, import_ir_from_nir, serialize_ir
from neurocnl.compile import compile_to_nir
from neurocnl.export.nir_exporter import materialize_to_nir, summarize_nir_lowering
from neurocnl.ir import LoweringError
from neurocnl.nir_cnl import NIR_Renderer
from neurocnl.nir_cnl.ir_types import NIREdgeRecord, NIRNodeRecord
from neurocnl.nir_cnl.parser import NIR_CNL_Parser
from neurocnl.nir_cnl.size_propagation import propagate_nir_sizes

if TYPE_CHECKING:
    from neurocnl.ir.types import NetworkIR, PopulationIR

from neurosim.contracts.canonical_editor_contracts import (
    CanonicalEditorDocument,
    CanvasNodeMutation,
    CanvasProjection,
    FidelityAnnotation,
)

logger = logging.getLogger(__name__)


def canonical_from_cnl(spec_text: str) -> CanonicalEditorDocument:
    """Parse NIR-native CNL text into the canonical editor document.

    Uses the NIR-native compile path exclusively. Raises on any input
    that is not valid NIR-native CNL — legacy biological grammar is not
    accepted.
    """
    nir_graph = compile_to_nir(spec_text)
    ir = import_ir_from_nir(nir_graph)
    _apply_propagated_population_sizes(ir, spec_text)
    return canonical_from_ir(ir, nir_graph=nir_graph)


def _population_for(ir: NetworkIR, name: str) -> PopulationIR | None:
    """Look up a population by NIR node name, tolerating case differences.

    ``import_ir_from_nir`` keys populations by a lower-cased name
    (``nir.lif_1``) while both the NIR graph and ``propagate_nir_sizes`` use the
    name as the CNL spelled it (``nir.LIF_1``). A plain ``.get()`` therefore
    missed every node whose name contains a capital letter — which is every
    canvas-authored node. Two separate consequences, both silent: propagated
    sizes were never applied, and the canvas fell back to reading a LIF's size
    off its scalar ``tau``, showing 1 neuron for a 784-neuron layer.
    """
    population = ir.populations.get(name)
    if population is not None:
        return population
    lowered = name.lower()
    for candidate_name, candidate in ir.populations.items():
        if candidate_name.lower() == lowered:
            return candidate
    return None


def _apply_propagated_population_sizes(ir: NetworkIR, spec_text: str) -> None:
    """Fix up population sizes for the canvas preview.

    `import_ir_from_nir` reads each LIF population's size off its own
    `tau` array, which is a bare scalar (size 1) whenever the CNL doesn't
    declare an explicit neuron count for that population — the size is only
    implied by network topology (e.g. a directly-wired `Linear` layer's
    declared weight-matrix shape). The deploy/training IR builder
    (`backend/app/services/neurocnl_bridge.py`) already infers this
    correctly via `propagate_nir_sizes`; re-running that same inference here
    on the identically-parsed records keeps the canvas preview consistent
    with what deploy actually sees, instead of silently showing `1`.

    Best-effort: a topology `propagate_nir_sizes` can't resolve (unsupported
    primitives, genuinely ambiguous wiring) just leaves populations at
    whatever size `import_ir_from_nir` already gave them — this is a canvas
    preview, not a validation gate, so it shouldn't block the editor over
    something the user may still be mid-authoring.
    """
    records = NIR_CNL_Parser().parse(spec_text)
    node_records = {
        record.name: record for record in records if isinstance(record, NIRNodeRecord)
    }
    edge_records = [record for record in records if isinstance(record, NIREdgeRecord)]

    outgoing: dict[str, list[str]] = defaultdict(list)
    incoming: dict[str, list[str]] = defaultdict(list)
    for edge in edge_records:
        if edge.src not in node_records or edge.target not in node_records:
            continue
        outgoing[edge.src].append(edge.target)
        incoming[edge.target].append(edge.src)

    try:
        sizes = propagate_nir_sizes(node_records, outgoing, incoming)
    except LoweringError:
        return

    for name, size in sizes.items():
        population = _population_for(ir, name)
        if population is not None:
            population.size = size


def canonical_from_ir(
    ir: NetworkIR,
    *,
    nir_graph: nir.NIRGraph | None = None,
) -> CanonicalEditorDocument:
    """Build canonical editor document from a NetworkIR."""
    if nir_graph is None:
        nir_graph = materialize_to_nir(ir)
    cnl_text = NIR_Renderer().render(nir_graph)
    fidelity = _compute_fidelity_annotations(ir)
    canvas = _project_to_canvas(ir, fidelity, nir_graph=nir_graph)
    return CanonicalEditorDocument(
        ir_json=serialize_ir(ir),
        cnl_text=cnl_text,
        fidelity_annotations=fidelity,
        canvas=canvas,
    )


def canonical_to_cnl(document: CanonicalEditorDocument) -> str:
    """Render the canonical document back to NIR-native CNL text."""
    ir = deserialize_ir(document.ir_json)
    nir_graph = materialize_to_nir(ir)
    return NIR_Renderer().render(nir_graph)


def canvas_from_canonical(document: CanonicalEditorDocument) -> CanvasProjection:
    """Project the canonical document into a canvas view."""
    ir = deserialize_ir(document.ir_json)
    nir_graph = materialize_to_nir(ir)
    fidelity = _compute_fidelity_annotations(ir)
    return _project_to_canvas(ir, fidelity, nir_graph=nir_graph)


def apply_canvas_mutation(
    document: CanonicalEditorDocument,
    mutation: CanvasNodeMutation,
) -> CanonicalEditorDocument:
    """Apply a typed canvas edit to the canonical document."""
    ir = deserialize_ir(document.ir_json)
    if mutation.node_id not in ir.populations:
        raise ValueError(
            f"Unknown node {mutation.node_id!r} — cannot apply canvas mutation."
        )
    pop = ir.populations[mutation.node_id]
    changes: dict[str, Any] = {}
    if mutation.threshold is not None:
        changes["threshold"] = mutation.threshold
    if mutation.membrane_time_constant is not None:
        changes["membrane_time_constant"] = mutation.membrane_time_constant
    if changes:
        pop = dataclasses.replace(pop, **changes)

    new_populations = {**ir.populations, mutation.node_id: pop}
    new_connections = list(ir.connections)
    if mutation.weight_to:
        new_connections = []
        for conn in ir.connections:
            if conn.source == mutation.node_id and conn.target in mutation.weight_to:
                conn = dataclasses.replace(conn, weight=mutation.weight_to[conn.target])
            new_connections.append(conn)

    new_ir = dataclasses.replace(
        ir,
        populations=new_populations,
        connections=new_connections,
    )
    return canonical_from_ir(new_ir)


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------


def _compute_fidelity_annotations(ir: NetworkIR) -> list[FidelityAnnotation]:
    """Derive fidelity annotations from the NIR lowering summary."""
    try:
        summary = summarize_nir_lowering(ir)
    except Exception:  # noqa: BLE001
        logger.warning("nir_lowering_summary_failed", exc_info=True)
        return []

    annotations: list[FidelityAnnotation] = []
    for concept, verdict in summary.concept_verdicts.items():
        if verdict == "lowered_faithfully":
            annotations.append(
                FidelityAnnotation(
                    kind="executable",
                    concept=concept,
                    message=f"{concept} lowers faithfully to NIR.",
                )
            )
        elif verdict in ("lowered_approximately",):
            annotations.append(
                FidelityAnnotation(
                    kind="advisory",
                    concept=concept,
                    message=f"{concept} lowers approximately; canvas editing may not preserve all semantics.",
                )
            )
        elif verdict == "lowered_as_metadata":
            annotations.append(
                FidelityAnnotation(
                    kind="advisory",
                    concept=concept,
                    message=f"{concept} is preserved as advisory metadata only.",
                )
            )
        elif verdict == "not_lowered":
            annotations.append(
                FidelityAnnotation(
                    kind="unsupported",
                    concept=concept,
                    message=f"{concept} is not supported in the current NIR bridge; "
                    "canvas editing is blocked for this concept.",
                )
            )
    return annotations


def _topo_sort_nir_edges(
    nir_graph: nir.NIRGraph,
) -> list[tuple[str, str]]:
    """Return NIR graph edges in topological order (source → target).

    Nodes with no incoming edges (typically Input nodes) come first;
    nodes with no outgoing edges (typically Output nodes) come last.
    Uses Kahn's algorithm. Falls back to the original edge order on cycles.
    """
    # Build adjacency from the node set (not just edges) so isolated nodes work.
    all_nodes = list(nir_graph.nodes.keys())
    in_degree: dict[str, int] = dict.fromkeys(all_nodes, 0)
    adjacency: dict[str, list[str]] = {n: [] for n in all_nodes}

    for src, tgt in nir_graph.edges:
        if src in adjacency and tgt in in_degree:
            adjacency[src].append(tgt)
            in_degree[tgt] += 1

    # Seed the queue: Input nodes first, then other zero-in-degree nodes.
    import nir as _nir  # local import to avoid module-level dependency

    queue: list[str] = [
        n
        for n in all_nodes
        if in_degree[n] == 0 and isinstance(nir_graph.nodes[n], _nir.Input)
    ]
    queue += [
        n
        for n in all_nodes
        if in_degree[n] == 0 and not isinstance(nir_graph.nodes[n], _nir.Input)
    ]

    topo_order: list[str] = []
    while queue:
        node = queue.pop(0)
        topo_order.append(node)
        for neighbor in adjacency[node]:
            in_degree[neighbor] -= 1
            if in_degree[neighbor] == 0:
                # Output nodes go to the back of the queue.
                if isinstance(nir_graph.nodes[neighbor], _nir.Output):
                    queue.append(neighbor)
                else:
                    queue.insert(0, neighbor)

    # Build an index for ordering.
    order_index = {n: i for i, n in enumerate(topo_order)}

    # Sort edges by (source position, target position).
    sorted_edges = sorted(
        nir_graph.edges,
        key=lambda e: (order_index.get(e[0], 9999), order_index.get(e[1], 9999)),
    )
    return sorted_edges


def _project_to_canvas(
    ir: NetworkIR,
    fidelity: list[FidelityAnnotation],
    *,
    nir_graph: nir.NIRGraph | None = None,
) -> CanvasProjection:
    """Project NetworkIR into a position-agnostic CanvasProjection.

    When *nir_graph* is supplied the projection is built directly from the raw
    NIR graph so that ALL node types (not just nir.LIF / nir.Input / nir.Output)
    are represented on the canvas, and ALL edges are emitted in topological order
    (Input→…→Output).  Weights are taken from ir.connections where available.

    When *nir_graph* is absent (legacy path) we fall back to ir.populations and
    ir.connections, which only covers LIF-family graphs exported by NeuroCNL.
    """

    if nir_graph is not None:
        return _project_to_canvas_from_nir(ir, fidelity, nir_graph)

    # ── Legacy fallback: no NIR graph available ─────────────────────────────
    nodes = []
    for name, pop in ir.populations.items():
        nodes.append(
            {
                "id": name,
                "label": name,
                "type": pop.population_type or "excitatory",
                "size": pop.size or 1,
                "shape": list(pop.shape) if pop.shape else None,
                "threshold": pop.threshold,
                "tau": pop.membrane_time_constant,
                "nir_type": None,
            }
        )

    edges = []
    for conn in ir.connections:
        weight = conn.weight
        scalar_weight: float | None = None
        if isinstance(weight, int | float):
            scalar_weight = float(weight)
        elif isinstance(weight, np.ndarray) and weight.size == 1:
            scalar_weight = float(weight.flat[0])
        edges.append(
            {
                "source": conn.source,
                "target": conn.target,
                "polarity": conn.polarity or "excitatory",
                "weight": scalar_weight,
                "connectivity_pattern": conn.connectivity_pattern,
            }
        )

    unsupported = [a for a in fidelity if a.kind == "unsupported"]
    advisory = [a for a in fidelity if a.kind == "advisory"]

    return CanvasProjection(
        nodes=nodes,
        edges=edges,
        read_only_annotations=unsupported + advisory,
    )


def _project_to_canvas_from_nir(
    ir: NetworkIR,
    fidelity: list[FidelityAnnotation],
    nir_graph: nir.NIRGraph,
) -> CanvasProjection:
    """Build a CanvasProjection directly from the NIR graph.

    Includes every NIR node type on the canvas (not just those in
    ir.populations) and emits every edge in topological order so the
    canvas always shows Input → ... → Output.

    Weights are taken from ir.connections for Linear-mediated edges;
    other edges carry weight=None.
    """
    import nir as _nir

    # Build a weight lookup from ir.connections (keyed by population pair).
    weight_lookup: dict[tuple[str, str], dict[str, Any]] = {}
    for conn in ir.connections:
        weight = conn.weight
        scalar_weight: float | None = None
        if isinstance(weight, int | float):
            scalar_weight = float(weight)
        elif isinstance(weight, np.ndarray) and weight.size == 1:
            scalar_weight = float(weight.flat[0])
        weight_lookup[(conn.source, conn.target)] = {
            "polarity": conn.polarity or "excitatory",
            "weight": scalar_weight,
            "connectivity_pattern": conn.connectivity_pattern,
        }

    serialized_canvas = serialize_nir_to_canvas_graph(nir_graph)
    serialized_nodes = {node.id: node for node in serialized_canvas.nodes}

    # ── Topology-sorted node list ────────────────────────────────────────────
    sorted_edges = _topo_sort_nir_edges(nir_graph)

    # Build a topological node order from the sorted edges.
    seen_nodes: list[str] = []
    seen_set: set[str] = set()
    # Seed with Input nodes first.
    for name, node in nir_graph.nodes.items():
        if isinstance(node, _nir.Input) and name not in seen_set:
            seen_nodes.append(name)
            seen_set.add(name)
    for src, tgt in sorted_edges:
        for n in (src, tgt):
            if n not in seen_set:
                seen_nodes.append(n)
                seen_set.add(n)
    # Append any nodes not reachable from the edge list (isolated nodes).
    for name in nir_graph.nodes:
        if name not in seen_set:
            seen_nodes.append(name)
            seen_set.add(name)
    # Ensure Output nodes are at the end.
    output_nodes = [
        n for n in seen_nodes if isinstance(nir_graph.nodes[n], _nir.Output)
    ]
    non_output = [n for n in seen_nodes if n not in set(output_nodes)]
    seen_nodes = non_output + output_nodes

    # ── Build nodes ──────────────────────────────────────────────────────────
    # Prefer ir.populations metadata (threshold, tau, etc.) when available;
    # fall back to raw NIR node introspection for unsupported types.
    nodes = []
    for name in seen_nodes:
        nir_node = nir_graph.nodes[name]
        serialized_node = serialized_nodes.get(name)
        parameters = (
            dict(serialized_node.parameters) if serialized_node is not None else {}
        )
        metadata = dict(serialized_node.metadata) if serialized_node is not None else {}
        # serialize_nir_to_canvas_graph()/_nir_type_name() already computed the
        # correct type string for this node (e.g. "cnl.Synaptic" for Synaptic/
        # RSynaptic, which the naive f"nir.{ClassName}" guess below gets wrong)
        # and stashed it in parameters['nir_type'] — reuse it instead of
        # recomputing independently, so this top-level field stays consistent
        # with the nested parameters/metadata below (which already use the
        # correct value). Only fall back to the naive guess when there's no
        # serialized node for this name at all.
        nir_type = parameters.get("nir_type") or f"nir.{type(nir_node).__name__}"

        label = serialized_node.label if serialized_node is not None else name

        pop = _population_for(ir, name)
        if pop is not None:
            # `parameters` above came from serialize_nir_to_canvas_graph(),
            # which reads a raw NIR node's own `tau` array size — a bare
            # scalar (1) whenever the CNL leaves this population's neuron
            # count implicit (inferred from topology into `pop.size`
            # instead, see _apply_propagated_population_sizes). Keep the
            # nested parameters consistent with the corrected `pop.size`
            # rather than showing a stale n_neurons the deploy path would
            # never actually use.
            if pop.size is not None and "n_neurons" in parameters:
                parameters = {**parameters, "n_neurons": pop.size, "shape": [pop.size]}
            nodes.append(
                {
                    "id": name,
                    "label": label,
                    "type": pop.population_type or "excitatory",
                    "size": pop.size or 1,
                    "shape": list(pop.shape) if pop.shape else None,
                    "threshold": pop.threshold,
                    "tau": pop.membrane_time_constant,
                    "nir_type": nir_type,
                    "parameters": parameters,
                    "metadata": metadata,
                }
            )
        else:
            # Node not in ir.populations — infer basic metadata from NIR.
            size = 1
            if hasattr(nir_node, "tau"):
                try:
                    import numpy as _np

                    size = int(_np.asarray(nir_node.tau).size)
                except Exception:
                    pass
            elif hasattr(nir_node, "input_type"):
                try:
                    import numpy as _np

                    vals = (
                        list(nir_node.input_type.values())
                        if isinstance(nir_node.input_type, dict)
                        else [nir_node.input_type]
                    )
                    size = int(_np.asarray(vals[0]).flat[0]) if vals else 1
                except Exception:
                    pass
            elif hasattr(nir_node, "output_type"):
                try:
                    import numpy as _np

                    vals = (
                        list(nir_node.output_type.values())
                        if isinstance(nir_node.output_type, dict)
                        else [nir_node.output_type]
                    )
                    size = int(_np.asarray(vals[0]).flat[0]) if vals else 1
                except Exception:
                    pass

            threshold: float | None = None
            tau: float | None = None
            if hasattr(nir_node, "v_threshold"):
                try:
                    import numpy as _np

                    threshold = float(_np.asarray(nir_node.v_threshold).flat[0])
                except Exception:
                    pass
            if hasattr(nir_node, "tau"):
                try:
                    import numpy as _np

                    tau = float(_np.asarray(nir_node.tau).flat[0])
                except Exception:
                    pass

            nodes.append(
                {
                    "id": name,
                    "label": label,
                    "type": "excitatory",
                    "size": size,
                    "shape": None,
                    "threshold": threshold,
                    "tau": tau,
                    "nir_type": nir_type,
                    "parameters": parameters,
                    "metadata": metadata,
                }
            )

    # ── Build edges (topology-sorted, all NIR edges) ─────────────────────────
    # Collapse intermediary nodes (Linear, Delay, etc.) so the canvas edges
    # go directly from the semantic source to the semantic target, matching
    # what ir.connections contains.  For edges not in ir.connections (e.g.
    # Input→Population, Population→Output without a Linear) we emit them
    # as-is since both endpoints are visible canvas nodes.
    #
    # We emit ONE edge per unique (source, target) pair from the NIR edge list
    # AFTER resolving through intermediaries.  The order follows the topology
    # sort so the canvas always reads Input → … → Output.

    all_node_ids = {n["id"] for n in nodes}
    edges: list[dict[str, Any]] = []
    covered: set[tuple[str, str]] = set()

    # Helper: follow a chain of intermediary nodes (not in canvas) to find
    # the next canvas-visible node.
    def _resolve_endpoint(node_name: str, direction: str) -> str | None:
        """Walk through intermediary nodes to find the canvas-visible endpoint."""
        visited = {node_name}
        current = node_name
        outgoing_map: dict[str, list[str]] = {}
        incoming_map: dict[str, list[str]] = {}
        for s, t in nir_graph.edges:
            outgoing_map.setdefault(s, []).append(t)
            incoming_map.setdefault(t, []).append(s)

        while current not in all_node_ids:
            neighbors = (
                outgoing_map.get(current, [])
                if direction == "forward"
                else incoming_map.get(current, [])
            )
            next_nodes = [n for n in neighbors if n not in visited]
            if not next_nodes:
                return None
            current = next_nodes[0]
            visited.add(current)
        return current

    outgoing_nir: dict[str, list[str]] = {}
    incoming_nir: dict[str, list[str]] = {}
    for s, t in nir_graph.edges:
        outgoing_nir.setdefault(s, []).append(t)
        incoming_nir.setdefault(t, []).append(s)

    for src, tgt in sorted_edges:
        # Resolve canvas-visible endpoints (skip intermediary nodes).
        canvas_src = src if src in all_node_ids else _resolve_endpoint(src, "backward")
        canvas_tgt = tgt if tgt in all_node_ids else _resolve_endpoint(tgt, "forward")

        if canvas_src is None or canvas_tgt is None:
            continue
        if canvas_src == canvas_tgt:
            # Self-loop through intermediary — skip.
            continue
        if (canvas_src, canvas_tgt) in covered:
            continue

        extra = weight_lookup.get(
            (canvas_src, canvas_tgt),
            {
                "polarity": "excitatory",
                "weight": None,
                "connectivity_pattern": None,
            },
        )
        edges.append(
            {
                "source": canvas_src,
                "target": canvas_tgt,
                **extra,
            }
        )
        covered.add((canvas_src, canvas_tgt))

    # ── Annotations ──────────────────────────────────────────────────────────
    unsupported = [a for a in fidelity if a.kind == "unsupported"]
    advisory = [a for a in fidelity if a.kind == "advisory"]

    pop_count = len(ir.populations)
    if pop_count > 2:
        advisory.append(
            FidelityAnnotation(
                kind="advisory",
                concept="network_topology",
                message=f"Network has {pop_count} populations. "
                "Canvas editing supports parameter changes only; "
                "topology changes are blocked.",
            )
        )

    projection_metadata: dict[str, Any] = {}
    graph_dt = (getattr(nir_graph, "metadata", None) or {}).get("dt")
    if graph_dt is not None:
        projection_metadata["dt"] = graph_dt

    return CanvasProjection(
        nodes=nodes,
        edges=edges,
        read_only_annotations=unsupported + advisory,
        metadata=projection_metadata,
    )
