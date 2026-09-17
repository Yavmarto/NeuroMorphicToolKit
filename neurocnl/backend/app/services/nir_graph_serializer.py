"""NIR <-> canvas graph conversion helpers for Studio."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

import nir
import numpy as np

from neurocnl._nir_compat import (
    make_nir_cubalif,
    make_nir_flatten,
    make_nir_graph,
    make_nir_if,
    make_nir_input,
    make_nir_lif,
    make_nir_output,
)
from neurocnl.runtime.cnl_nodes import (
    BatchNorm1d,
    Dropout,
    Leaky,
    RLeaky,
    RSynaptic,
    Synaptic,
)
from neurocnl.runtime.nir_topology import fuse_recurrent_pairs
from neurosim.contracts.design_contracts import CanvasEdge, CanvasGraph, CanvasNode

DEFAULT_NODE_WIDTH = 176.0
DEFAULT_NODE_HEIGHT = 136.0
DEFAULT_NODE_Y = 200.0
DEFAULT_NODE_X_STEP = 240.0


@dataclass(frozen=True)
class NirCanvasTypeSpec:
    """Static canvas metadata for one NIR primitive."""

    nir_type: str
    category: str
    label: str
    input_ports: tuple[str, ...] = ("in",)
    output_ports: tuple[str, ...] = ("out",)
    component_id: str | None = None


NIR_CANVAS_TYPE_SPECS: dict[str, NirCanvasTypeSpec] = {
    "nir.Input": NirCanvasTypeSpec(
        nir_type="nir.Input",
        category="io",
        label="Input",
        input_ports=(),
        component_id="input_node",
    ),
    "nir.Output": NirCanvasTypeSpec(
        nir_type="nir.Output",
        category="io",
        label="Output",
        output_ports=(),
        component_id="output_node",
    ),
    "nir.LIF": NirCanvasTypeSpec(
        nir_type="nir.LIF",
        category="neuron",
        label="LIF",
        component_id="lif_population",
    ),
    "nir.CubaLIF": NirCanvasTypeSpec(
        nir_type="nir.CubaLIF",
        category="neuron",
        label="CubaLIF",
        component_id="lif_population",
    ),
    "nir.IF": NirCanvasTypeSpec(
        nir_type="nir.IF",
        category="neuron",
        label="IF",
        component_id="lif_population",
    ),
    "nir.LI": NirCanvasTypeSpec(
        nir_type="nir.LI",
        category="neuron",
        label="LI",
        component_id="lif_population",
    ),
    "nir.Linear": NirCanvasTypeSpec(
        nir_type="nir.Linear",
        category="transform",
        label="Linear",
        component_id="nir.Linear",
    ),
    "nir.Affine": NirCanvasTypeSpec(
        nir_type="nir.Affine",
        category="transform",
        label="Affine",
        component_id="nir.Affine",
    ),
    "nir.Conv1d": NirCanvasTypeSpec(
        nir_type="nir.Conv1d",
        category="transform",
        label="Conv1d",
        component_id="nir.Conv1d",
    ),
    "nir.Conv2d": NirCanvasTypeSpec(
        nir_type="nir.Conv2d",
        category="transform",
        label="Conv2d",
        component_id="nir.Conv2d",
    ),
    "nir.Flatten": NirCanvasTypeSpec(
        nir_type="nir.Flatten",
        category="utility",
        label="Flatten",
        component_id="nir.Flatten",
    ),
    "nir.AvgPool2d": NirCanvasTypeSpec(
        nir_type="nir.AvgPool2d",
        category="pooling",
        label="AvgPool2d",
        component_id="nir.AvgPool2d",
    ),
    "nir.SumPool2d": NirCanvasTypeSpec(
        nir_type="nir.SumPool2d",
        category="pooling",
        label="SumPool2d",
        component_id="nir.SumPool2d",
    ),
    "nir.Delay": NirCanvasTypeSpec(
        nir_type="nir.Delay",
        category="utility",
        label="Delay",
        component_id="nir.Delay",
    ),
    "nir.Scale": NirCanvasTypeSpec(
        nir_type="nir.Scale",
        category="transform",
        label="Scale",
        component_id="nir.Scale",
    ),
    # ── CNLStudio-internal node types (not standard NIR primitives) ──────────
    "cnl.Synaptic": NirCanvasTypeSpec(
        nir_type="cnl.Synaptic",
        category="neuron",
        label="Synaptic",
        component_id="cnl.Synaptic",
    ),
    "cnl.RSynaptic": NirCanvasTypeSpec(
        nir_type="cnl.RSynaptic",
        category="neuron",
        label="RSynaptic",
        component_id="cnl.RSynaptic",
    ),
    "cnl.RLeaky": NirCanvasTypeSpec(
        nir_type="cnl.RLeaky",
        category="neuron",
        label="RLeaky",
        component_id="cnl.RLeaky",
    ),
    "cnl.Leaky": NirCanvasTypeSpec(
        nir_type="cnl.Leaky",
        category="neuron",
        label="Leaky (β)",
        component_id="cnl.Leaky",
    ),
    "cnl.BatchNorm1d": NirCanvasTypeSpec(
        nir_type="cnl.BatchNorm1d",
        category="transform",
        label="BatchNorm1d",
        component_id="cnl.BatchNorm1d",
    ),
    "cnl.Dropout": NirCanvasTypeSpec(
        nir_type="cnl.Dropout",
        category="transform",
        label="Dropout",
        component_id="cnl.Dropout",
    ),
}


def _topo_sorted_edges(edges: list[CanvasEdge], node_ids: list[str]) -> list[CanvasEdge]:
    """Return edges in topological (Input-first, Output-last) order.

    Forward edges (source rank < target rank) come first; back-edges
    (recurrent connections) are appended afterwards preserving their relative order.
    """
    from collections import deque

    in_degree: dict[str, int] = dict.fromkeys(node_ids, 0)
    adjacency: dict[str, list[str]] = {n: [] for n in node_ids}
    for edge in edges:
        s, t = edge.source_node_id, edge.target_node_id
        if s in in_degree and t in in_degree and s != t:
            in_degree[t] += 1
            adjacency[s].append(t)

    queue: deque[str] = deque(sorted(n for n, d in in_degree.items() if d == 0))
    topo_order: list[str] = []
    visited: set[str] = set()
    while queue:
        node = queue.popleft()
        if node in visited:
            continue
        visited.add(node)
        topo_order.append(node)
        for t in sorted(adjacency[node]):
            in_degree[t] -= 1
            if in_degree[t] == 0:
                queue.append(t)

    rank: dict[str, int] = {n: i for i, n in enumerate(topo_order)}
    max_rank = len(topo_order)

    forward = sorted(
        [
            e
            for e in edges
            if rank.get(e.source_node_id, max_rank) < rank.get(e.target_node_id, max_rank)
        ],
        key=lambda e: (
            rank.get(e.source_node_id, max_rank),
            rank.get(e.target_node_id, max_rank),
        ),
    )
    back = [
        e
        for e in edges
        if rank.get(e.source_node_id, max_rank) >= rank.get(e.target_node_id, max_rank)
    ]
    return forward + back


class NirCanvasConversionError(ValueError):
    """Raised when a canvas graph cannot be represented as NIR."""

    def __init__(self, message: str, *, unsupported_types: list[str] | None = None) -> None:
        super().__init__(message)
        self.unsupported_types = unsupported_types or []


def serialize_nir_graph(graph: nir.NIRGraph) -> dict[str, list[dict[str, Any]]]:
    """Convert a NIR graph into the legacy JSON topology shape used by /generate."""
    canvas_graph = serialize_nir_to_canvas_graph(graph)
    nodes = [
        {
            "id": node.id,
            "type": node.component_id,
            "subtype": node.metadata.get("category", "generic"),
            "nir_type": node.nir_type,
            "label": node.label or node.parameters.get("name", node.id),
            "params": node.parameters,
            "position": {"x": node.position[0], "y": node.position[1]},
            "metadata": node.metadata,
        }
        for node in canvas_graph.nodes
    ]
    edges = [
        {
            "id": edge.id,
            "source": edge.source_node_id,
            "target": edge.target_node_id,
            "params": edge.parameters,
        }
        for edge in canvas_graph.edges
    ]
    return {"nodes": nodes, "edges": edges}


def serialize_nir_to_canvas_graph(graph: nir.NIRGraph) -> CanvasGraph:
    """Convert a NIR graph into the editable Studio canvas graph."""
    # Captured before fuse_recurrent_pairs, which can return a brand-new
    # graph (no metadata) when it actually fuses a CubaLIF+self-loop pair.
    original_dt = (getattr(graph, "metadata", None) or {}).get("dt")
    graph = fuse_recurrent_pairs(graph)
    nodes: list[CanvasNode] = []
    edges: list[CanvasEdge] = []
    positions = {name: index * DEFAULT_NODE_X_STEP for index, name in enumerate(graph.nodes)}

    for name, node in graph.nodes.items():
        nir_type = _nir_type_name(node)
        spec = NIR_CANVAS_TYPE_SPECS.get(nir_type)
        if spec is None:
            # Emit a placeholder node rather than aborting the whole import.
            # The canvas will show it as an unknown type; users can still see
            # the graph structure and the CNL will contain a # unsupported: comment.
            nodes.append(
                CanvasNode(
                    id=name,
                    component_id=nir_type,
                    nir_type=nir_type,
                    label=f"[unsupported] {name}",
                    parameters={"name": name, "nir_type": nir_type},
                    position=(float(positions[name]), DEFAULT_NODE_Y),
                    width=DEFAULT_NODE_WIDTH,
                    height=DEFAULT_NODE_HEIGHT,
                    metadata={"category": "unknown", "display_label": nir_type},
                )
            )
            continue
        metadata = _normalize(getattr(node, "metadata", {}) or {})
        params = _serialize_node_parameters(node)
        label = metadata.get("ir_name") or metadata.get("label") or name
        params.setdefault("name", label)
        params.setdefault("nir_type", nir_type)
        params.setdefault("shape", _shape_from_node(node))
        nodes.append(
            CanvasNode(
                id=name,
                component_id=spec.component_id or nir_type,
                nir_type=nir_type,
                label=str(label),
                parameters=params,
                position=(float(positions[name]), DEFAULT_NODE_Y),
                width=DEFAULT_NODE_WIDTH,
                height=DEFAULT_NODE_HEIGHT,
                metadata={
                    **metadata,
                    "category": spec.category,
                    "display_label": spec.label,
                },
            )
        )

    for index, (source, target) in enumerate(graph.edges):
        target_node = graph.nodes[target]
        edge_params = _serialize_edge_parameters(target_node)
        edges.append(
            CanvasEdge(
                id=f"edge_{index}_{source}_to_{target}",
                source_node_id=source,
                source_port=_default_output_port(source, graph),
                target_node_id=target,
                target_port=_default_input_port(target, graph),
                parameters=edge_params,
            )
        )

    node_ids = list(graph.nodes.keys())
    metadata: dict[str, Any] = {"graph_kind": "nir", "layout": "imported_linear"}
    if original_dt is not None:
        metadata["dt"] = original_dt
    return CanvasGraph(
        nodes=nodes,
        edges=_topo_sorted_edges(edges, node_ids),
        metadata=metadata,
    )


def deserialize_canvas_graph(graph: CanvasGraph) -> nir.NIRGraph:
    """Convert a Studio canvas graph into a NIR graph."""
    nodes: dict[str, Any] = {}
    unsupported_types: list[str] = []

    for node in graph.nodes:
        nir_type = node.nir_type or _legacy_component_to_nir_type(node.component_id)
        if nir_type not in NIR_CANVAS_TYPE_SPECS:
            unsupported_types.append(nir_type)
            continue
        try:
            nodes[node.id] = _deserialize_node(node, nir_type)
        except NirCanvasConversionError:
            raise
        except Exception as exc:  # noqa: BLE001
            raise NirCanvasConversionError(
                f"Failed to convert canvas node {node.id!r} ({nir_type}) into NIR: {exc}",
                unsupported_types=[nir_type],
            ) from exc

    if unsupported_types:
        unsupported_unique = sorted(set(unsupported_types))
        raise NirCanvasConversionError(
            f"Unsupported canvas node types for NIR export: {', '.join(unsupported_unique)}",
            unsupported_types=unsupported_unique,
        )

    edges = [(edge.source_node_id, edge.target_node_id) for edge in graph.edges]
    nir_graph = make_nir_graph(nodes, edges)

    graph_dt = graph.metadata.get("dt")
    if graph_dt is not None:
        graph_dt = float(graph_dt)
        nir_graph.metadata["dt"] = graph_dt
        for node in nodes.values():
            if isinstance(node, nir.LIF) and "dt" not in node.metadata:
                node.metadata["dt"] = graph_dt

    return nir_graph


def _serialize_node_parameters(node: Any) -> dict[str, Any]:
    if isinstance(node, nir.Input):
        return {
            "size": _infer_endpoint_size(node.input_type),
            "shape": _shape_from_endpoint(node.input_type),
        }
    if isinstance(node, nir.Output):
        return {
            "size": _infer_endpoint_size(node.output_type),
            "shape": _shape_from_endpoint(node.output_type),
        }
    if isinstance(node, nir.LIF):
        tau = np.asarray(node.tau, dtype=float)
        return {
            "n_neurons": int(tau.size),
            "tau": float(tau.flat[0]),
            "tau_rc": float(tau.flat[0]),
            "threshold": float(np.asarray(node.v_threshold, dtype=float).flat[0]),
            "v_threshold": float(np.asarray(node.v_threshold, dtype=float).flat[0]),
            "v_leak": float(np.asarray(node.v_leak, dtype=float).flat[0]),
            "r": float(np.asarray(node.r, dtype=float).flat[0]),
            "shape": _shape_from_node(node),
        }
    if isinstance(node, nir.CubaLIF):
        tau_syn = np.asarray(node.tau_syn, dtype=float)
        tau_mem = np.asarray(node.tau_mem, dtype=float)
        return {
            "n_neurons": int(tau_mem.size),
            "tau_syn": float(tau_syn.flat[0]),
            "tau_mem": float(tau_mem.flat[0]),
            "threshold": float(np.asarray(node.v_threshold, dtype=float).flat[0]),
            "v_threshold": float(np.asarray(node.v_threshold, dtype=float).flat[0]),
            "v_leak": float(np.asarray(node.v_leak, dtype=float).flat[0]),
            "r": float(np.asarray(node.r, dtype=float).flat[0]),
            "w_in": float(np.asarray(node.w_in, dtype=float).flat[0]),
            "shape": _shape_from_node(node),
        }
    if isinstance(node, nir.IF):
        threshold = np.asarray(node.v_threshold, dtype=float)
        return {
            "n_neurons": int(threshold.size),
            "threshold": float(threshold.flat[0]),
            "v_threshold": float(threshold.flat[0]),
            "r": float(np.asarray(node.r, dtype=float).flat[0]),
            "shape": _shape_from_node(node),
        }
    if isinstance(node, nir.LI):
        tau = np.asarray(node.tau, dtype=float)
        return {
            "n_neurons": int(tau.size),
            "tau": float(tau.flat[0]),
            "v_leak": float(np.asarray(node.v_leak, dtype=float).flat[0]),
            "r": float(np.asarray(node.r, dtype=float).flat[0]),
            "shape": _shape_from_node(node),
        }
    if isinstance(node, nir.Linear):
        weight = np.asarray(node.weight, dtype=float)
        return {
            "rows": int(weight.shape[0]) if weight.ndim > 0 else 1,
            "cols": int(weight.shape[1]) if weight.ndim > 1 else 1,
            "shape": list(weight.shape),
            "weight_matrix": weight.tolist(),
            "weight_fill": float(weight.flat[0]) if weight.size else 0.0,
        }
    if isinstance(node, nir.Affine):
        weight = np.asarray(node.weight, dtype=float)
        bias = np.asarray(node.bias, dtype=float)
        return {
            "rows": int(weight.shape[0]) if weight.ndim > 0 else 1,
            "cols": int(weight.shape[1]) if weight.ndim > 1 else 1,
            "shape": list(weight.shape),
            "weight_matrix": weight.tolist(),
            "bias": bias.tolist(),
            "weight_fill": float(weight.flat[0]) if weight.size else 0.0,
        }
    if isinstance(node, nir.Conv1d):
        weight = np.asarray(node.weight, dtype=float)
        return {
            "weight_shape": list(weight.shape),
            "weight_matrix": weight.tolist(),
            "weight_fill": float(weight.flat[0]) if weight.size else 0.0,
            "stride": int(node.stride),
            "padding": node.padding,
            "dilation": int(node.dilation),
            "groups": int(node.groups),
            "input_shape": node.input_shape,
            "bias": np.asarray(node.bias, dtype=float).tolist(),
        }
    if isinstance(node, nir.Conv2d):
        weight = np.asarray(node.weight, dtype=float)
        return {
            "weight_shape": list(weight.shape),
            "weight_matrix": weight.tolist(),
            "weight_fill": float(weight.flat[0]) if weight.size else 0.0,
            "stride": _normalize(node.stride),
            "padding": _normalize(node.padding),
            "dilation": _normalize(node.dilation),
            "groups": int(node.groups),
            "input_shape": _normalize(node.input_shape),
            "bias": np.asarray(node.bias, dtype=float).tolist(),
        }
    if isinstance(node, nir.Flatten):
        return {
            "start_dim": int(node.start_dim),
            "end_dim": int(node.end_dim),
        }
    if isinstance(node, nir.AvgPool2d):
        return {
            "kernel_size": np.asarray(node.kernel_size, dtype=int).tolist(),
            "stride": np.asarray(node.stride, dtype=int).tolist(),
            "padding": np.asarray(node.padding, dtype=int).tolist(),
        }
    if isinstance(node, nir.SumPool2d):
        return {
            "kernel_size": np.asarray(node.kernel_size, dtype=int).tolist(),
            "stride": np.asarray(node.stride, dtype=int).tolist(),
            "padding": np.asarray(node.padding, dtype=int).tolist(),
        }
    if isinstance(node, nir.Delay):
        delay = np.asarray(node.delay, dtype=float)
        return {"delay": float(delay.flat[0])}
    if isinstance(node, nir.Scale):
        scale = np.asarray(node.scale, dtype=float)
        return {
            "scale": scale.tolist(),
            "scale_fill": float(scale.flat[0]) if scale.size else 1.0,
        }
    if isinstance(node, Synaptic):
        return {
            "n_neurons": node.n_neurons,
            "alpha": node.alpha,
            "beta": node.beta,
            "threshold": node.threshold,
            "reset_mechanism": node.reset_mechanism,
        }
    if isinstance(node, RSynaptic):
        params: dict[str, Any] = {
            "n_neurons": node.n_neurons,
            "alpha": node.alpha,
            "beta": node.beta,
            "threshold": node.threshold,
            "reset_mechanism": node.reset_mechanism,
            "use_bias": node.use_bias,
        }
        if node.recurrent_weight is not None:
            params["recurrent_weight_matrix"] = node.recurrent_weight
        return params
    if isinstance(node, RLeaky):
        return {
            "n_neurons": node.n_neurons,
            "beta": node.beta,
            "threshold": node.threshold,
            "reset_mechanism": node.reset_mechanism,
        }
    if isinstance(node, Leaky):
        return {
            "n_neurons": node.n_neurons,
            "beta": node.beta,
            "threshold": node.threshold,
            "reset_mechanism": node.reset_mechanism,
        }
    if isinstance(node, BatchNorm1d):
        return {"num_features": node.num_features}
    if isinstance(node, Dropout):
        return {"p": node.p}
    raise NirCanvasConversionError(
        f"Unsupported NIR node {type(node).__name__!r} for canvas serialization.",
        unsupported_types=[_nir_type_name(node)],
    )


def _serialize_edge_parameters(target_node: Any) -> dict[str, Any]:
    if isinstance(target_node, nir.Linear):
        weight = np.asarray(target_node.weight, dtype=float)
        return {
            "weight_matrix": weight.tolist(),
            "weight": float(weight.flat[0]) if weight.size == 1 else None,
        }
    if isinstance(target_node, nir.Affine):
        weight = np.asarray(target_node.weight, dtype=float)
        return {
            "weight_matrix": weight.tolist(),
            "bias": np.asarray(target_node.bias, dtype=float).tolist(),
        }
    if isinstance(target_node, nir.Delay):
        return {"delay": float(np.asarray(target_node.delay, dtype=float).flat[0])}
    return {}


def _deserialize_node(node: CanvasNode, nir_type: str) -> Any:
    params = node.parameters
    metadata = {
        **_normalize(node.metadata),
        "canvas_label": node.label or params.get("name") or node.id,
        "canvas_component_id": node.component_id,
        "canvas_position": list(node.position),
    }
    if node.label:
        metadata["label"] = node.label
    if nir_type == "nir.Input":
        shape = _shape_from_canvas_params(params)
        return make_nir_input(input_type={"input": np.asarray(shape, dtype=int)}, metadata=metadata)
    if nir_type == "nir.Output":
        shape = _shape_from_canvas_params(params)
        return make_nir_output(
            output_type={"output": np.asarray(shape, dtype=int)}, metadata=metadata
        )
    if nir_type == "nir.LIF":
        size = _node_size(params)
        return make_nir_lif(
            tau=np.full(size, _param_float(params, "tau", "tau_rc", default=0.02)),
            r=np.full(size, _param_float(params, "r", default=1.0)),
            v_leak=np.full(size, _param_float(params, "v_leak", default=0.0)),
            v_threshold=np.full(
                size, _param_float(params, "threshold", "v_threshold", default=1.0)
            ),
            v_reset=_optional_full_array(size, params.get("v_reset")),
            metadata=metadata,
        )
    if nir_type == "nir.CubaLIF":
        size = _node_size(params)
        return make_nir_cubalif(
            tau_syn=np.full(size, _param_float(params, "tau_syn", default=0.01)),
            tau_mem=np.full(size, _param_float(params, "tau_mem", "tau", default=0.02)),
            r=np.full(size, _param_float(params, "r", default=1.0)),
            v_leak=np.full(size, _param_float(params, "v_leak", default=0.0)),
            v_threshold=np.full(
                size, _param_float(params, "threshold", "v_threshold", default=1.0)
            ),
            v_reset=_optional_full_array(size, params.get("v_reset")),
            w_in=np.asarray(params.get("w_in", 1.0), dtype=float),
            metadata=metadata,
        )
    if nir_type == "nir.IF":
        size = _node_size(params)
        return make_nir_if(
            r=np.full(size, _param_float(params, "r", default=1.0)),
            v_threshold=np.full(
                size, _param_float(params, "threshold", "v_threshold", default=1.0)
            ),
            v_reset=_optional_full_array(size, params.get("v_reset")),
            metadata=metadata,
        )
    if nir_type == "nir.LI":
        size = _node_size(params)
        return nir.LI(
            tau=np.full(size, _param_float(params, "tau", default=0.02)),
            r=np.full(size, _param_float(params, "r", default=1.0)),
            v_leak=np.full(size, _param_float(params, "v_leak", default=0.0)),
            metadata=metadata,
        )
    if nir_type == "nir.Linear":
        return nir.Linear(weight=_weight_matrix_from_params(params), metadata=metadata)
    if nir_type == "nir.Affine":
        weight = _weight_matrix_from_params(params)
        bias = np.asarray(
            params.get("bias", [0.0] * int(weight.shape[0] if weight.ndim > 0 else 1)),
            dtype=float,
        )
        return nir.Affine(weight=weight, bias=bias, metadata=metadata)
    if nir_type == "nir.Conv1d":
        weight = _tensor_from_params(
            params,
            shape_key="weight_shape",
            fill_key="weight_fill",
        )
        bias = np.asarray(params.get("bias", [0.0] * int(weight.shape[0])), dtype=float)
        input_shape = params.get("input_shape")
        return nir.Conv1d(
            input_shape=int(input_shape) if input_shape is not None else None,
            weight=weight,
            stride=int(params.get("stride", 1)),
            padding=params.get("padding", 0),
            dilation=int(params.get("dilation", 1)),
            groups=int(params.get("groups", 1)),
            bias=bias,
            metadata=metadata,
        )
    if nir_type == "nir.Conv2d":
        weight = _tensor_from_params(
            params,
            shape_key="weight_shape",
            fill_key="weight_fill",
        )
        bias = np.asarray(params.get("bias", [0.0] * int(weight.shape[0])), dtype=float)
        input_shape = params.get("input_shape")
        normalized_input_shape = None
        if isinstance(input_shape, list) and len(input_shape) >= 2:
            normalized_input_shape = (int(input_shape[0]), int(input_shape[1]))
        return nir.Conv2d(
            input_shape=normalized_input_shape,
            weight=weight,
            stride=_tuple_or_int(params.get("stride", [1, 1])),
            padding=_tuple_or_int(params.get("padding", [0, 0])),
            dilation=_tuple_or_int(params.get("dilation", [1, 1])),
            groups=int(params.get("groups", 1)),
            bias=bias,
            metadata=metadata,
        )
    if nir_type == "nir.Flatten":
        shape = _shape_from_canvas_params(params)
        return make_nir_flatten(
            input_type={"input": np.asarray(shape, dtype=int)},
            start_dim=int(params.get("start_dim", 1)),
            end_dim=int(params.get("end_dim", -1)),
            metadata=metadata,
        )
    if nir_type == "nir.AvgPool2d":
        return nir.AvgPool2d(
            kernel_size=np.asarray(params.get("kernel_size", [2, 2]), dtype=int),
            stride=np.asarray(params.get("stride", [2, 2]), dtype=int),
            padding=np.asarray(params.get("padding", [0, 0]), dtype=int),
            metadata=metadata,
        )
    if nir_type == "nir.SumPool2d":
        return nir.SumPool2d(
            kernel_size=np.asarray(params.get("kernel_size", [2, 2]), dtype=int),
            stride=np.asarray(params.get("stride", [2, 2]), dtype=int),
            padding=np.asarray(params.get("padding", [0, 0]), dtype=int),
            metadata=metadata,
        )
    if nir_type == "nir.Delay":
        return nir.Delay(
            delay=np.asarray([_param_float(params, "delay", default=0.001)]),
            metadata=metadata,
        )
    if nir_type == "nir.Scale":
        scale = np.asarray(params.get("scale", [params.get("scale_fill", 1.0)]), dtype=float)
        return nir.Scale(scale=scale, metadata=metadata)
    if nir_type == "cnl.Synaptic":
        return Synaptic(
            n_neurons=int(params.get("n_neurons", 1)),
            alpha=float(params.get("alpha", 0.9)),
            beta=float(params.get("beta", 0.8)),
            threshold=float(params.get("threshold", 1.0)),
            reset_mechanism=str(params.get("reset_mechanism", "subtract")),
            metadata=metadata,
        )
    if nir_type == "cnl.RSynaptic":
        recurrent_weight_matrix = params.get("recurrent_weight_matrix")
        return RSynaptic(
            n_neurons=int(params.get("n_neurons", 1)),
            alpha=float(params.get("alpha", 0.9)),
            beta=float(params.get("beta", 0.8)),
            threshold=float(params.get("threshold", 1.0)),
            reset_mechanism=str(params.get("reset_mechanism", "subtract")),
            use_bias=bool(params.get("use_bias", False)),
            metadata=metadata,
            recurrent_weight=(
                [[float(v) for v in row] for row in recurrent_weight_matrix]
                if recurrent_weight_matrix is not None
                else None
            ),
        )
    if nir_type == "cnl.RLeaky":
        return RLeaky(
            n_neurons=int(params.get("n_neurons", 1)),
            beta=float(params.get("beta", 0.9)),
            threshold=float(params.get("threshold", 1.0)),
            reset_mechanism=str(params.get("reset_mechanism", "subtract")),
            metadata=metadata,
        )
    if nir_type == "cnl.Leaky":
        return Leaky(
            n_neurons=int(params.get("n_neurons", 1)),
            beta=float(params.get("beta", 0.9)),
            threshold=float(params.get("threshold", 1.0)),
            reset_mechanism=str(params.get("reset_mechanism", "subtract")),
            metadata=metadata,
        )
    if nir_type == "cnl.BatchNorm1d":
        return BatchNorm1d(
            num_features=int(params.get("num_features", 1)),
            metadata=metadata,
        )
    if nir_type == "cnl.Dropout":
        return Dropout(
            p=float(params.get("p", 0.5)),
            metadata=metadata,
        )
    raise NirCanvasConversionError(
        f"Unsupported NIR type {nir_type!r} for canvas export.",
        unsupported_types=[nir_type],
    )


def _weight_matrix_from_params(params: dict[str, Any]) -> np.ndarray:
    """Rebuild a Linear/Affine weight matrix from canvas parameters.

    `_serialize_node_parameters` emits `weight_matrix` (the trained tensor)
    *alongside* the user-editable `rows`/`cols`, and the canvas mirrors those
    parameters back over its own nodes after every round trip. So a stale
    `weight_matrix` outlives an edit to `rows`/`cols` -- and preferring it
    unconditionally is what silently reverted the edit and shipped the old
    layer width to codegen.

    `rows`/`cols` win when they disagree with the matrix: they are what the
    user typed. The matrix is still preferred when it agrees, so importing a
    trained NIR file and pushing it straight back does not flatten real
    weights into a constant fill.
    """
    raw_matrix = params.get("weight_matrix")
    # Both keys, not either: `_serialize_node_parameters` always emits the pair,
    # so a node carrying only one of them is not describing a shape the user
    # chose, and defaulting the missing half to 1 would destroy real weights.
    declared_shape = (
        (int(params["rows"]), int(params["cols"]))
        if "rows" in params and "cols" in params
        else None
    )
    if raw_matrix is not None:
        matrix = np.asarray(raw_matrix, dtype=float)
        if declared_shape is None or matrix.shape == declared_shape:
            return matrix
    rows, cols = declared_shape or (int(params.get("rows", 1)), int(params.get("cols", 1)))
    fill = float(params.get("weight_fill", params.get("weight", 1.0)))
    return np.full((rows, cols), fill, dtype=float)


def _tensor_from_shape_and_fill(raw_shape: Any, fill: Any) -> np.ndarray:
    if not isinstance(raw_shape, list) or not raw_shape:
        raw_shape = [1, 1, 1, 1]
    shape = tuple(int(item) for item in raw_shape)
    return np.full(shape, float(fill), dtype=float)


def _tensor_from_params(
    params: dict[str, Any],
    *,
    shape_key: str,
    fill_key: str,
) -> np.ndarray:
    if "weight_matrix" in params:
        return np.asarray(params["weight_matrix"], dtype=float)
    return _tensor_from_shape_and_fill(params.get(shape_key), params.get(fill_key, 0.0))


def _tuple_or_int(value: Any) -> int | tuple[int, int]:
    if isinstance(value, list):
        if len(value) == 1:
            return int(value[0])
        return (int(value[0]), int(value[1]))
    return int(value)


def _optional_full_array(size: int, raw_value: Any) -> np.ndarray | None:
    if raw_value is None:
        return None
    return np.full(size, float(raw_value), dtype=float)


def _node_size(params: dict[str, Any]) -> int:
    if "n_neurons" in params:
        return max(1, int(params["n_neurons"]))
    shape = _shape_from_canvas_params(params)
    return max(1, int(np.prod(shape, dtype=int)))


def _shape_from_canvas_params(params: dict[str, Any]) -> list[int]:
    """Resolve a node's shape from canvas parameters.

    `shape` is derived, not typed: `_serialize_node_parameters` emits it for
    every node and `serialize_nir_graph` back-fills it via
    `params.setdefault("shape", ...)`, so it survives on the canvas across
    every round trip. `size` is the field the Inspector actually edits.

    So when the two disagree, `size` wins -- otherwise a stale `shape` from
    before the edit outranks the number the user just typed, which is what
    silently reverted `Size` on Input/Output nodes. `shape` still wins when it
    agrees, or when no `size` was given, so multi-dimensional shapes (conv
    feature maps) are not flattened to a bare length.
    """
    raw_shape = params.get("shape")
    shape = [int(item) for item in raw_shape] if isinstance(raw_shape, list) and raw_shape else None
    raw_size = params.get("size", params.get("n_neurons"))
    size = max(1, int(raw_size)) if raw_size is not None else None
    if shape is not None and (size is None or int(np.prod(shape, dtype=int)) == size):
        return shape
    return [size if size is not None else 1]


def _shape_from_node(node: Any) -> list[int]:
    input_type = getattr(node, "input_type", None)
    output_type = getattr(node, "output_type", None)
    if input_type:
        return _shape_from_endpoint(input_type)
    if output_type:
        return _shape_from_endpoint(output_type)
    tau = getattr(node, "tau", None)
    if tau is not None:
        return [int(np.asarray(tau).size)]
    threshold = getattr(node, "v_threshold", None)
    if threshold is not None:
        return [int(np.asarray(threshold).size)]
    weight = getattr(node, "weight", None)
    if weight is not None:
        return list(np.asarray(weight).shape)
    return [1]


def _shape_from_endpoint(endpoint_type: object) -> list[int]:
    normalized = _normalize(endpoint_type)
    if isinstance(normalized, dict):
        first = next(iter(normalized.values()), [1])
        if first is None:
            return [1]
        if isinstance(first, list):
            return [int(item) for item in first]
        return [int(first)]
    if normalized is None:
        return [1]
    return [1]


def _infer_endpoint_size(endpoint_type: object) -> int:
    shape = _shape_from_endpoint(endpoint_type)
    return int(np.prod(shape, dtype=int))


def _default_input_port(node_id: str, graph: nir.NIRGraph) -> str:
    node = graph.nodes[node_id]
    spec = NIR_CANVAS_TYPE_SPECS.get(_nir_type_name(node))
    return spec.input_ports[0] if spec and spec.input_ports else "in"


def _default_output_port(node_id: str, graph: nir.NIRGraph) -> str:
    node = graph.nodes[node_id]
    spec = NIR_CANVAS_TYPE_SPECS.get(_nir_type_name(node))
    return spec.output_ports[0] if spec and spec.output_ports else "out"


def _nir_type_name(node: Any) -> str:
    # CNLStudio-internal node types use the "cnl." prefix rather than "nir."
    if isinstance(node, Synaptic | RSynaptic | Leaky | RLeaky | BatchNorm1d | Dropout):
        return f"cnl.{type(node).__name__}"
    return f"nir.{type(node).__name__}"


def _legacy_component_to_nir_type(component_id: str) -> str:
    legacy = {
        "lif_population": "nir.LIF",
        "adaptive_lif": "nir.LIF",
        "input_node": "nir.Input",
        "output_node": "nir.Output",
        "weight": "nir.Linear",
        "delay": "nir.Delay",
    }
    return legacy.get(component_id, component_id)


def _param_float(params: dict[str, Any], *names: str, default: float) -> float:
    for name in names:
        raw_value = params.get(name)
        if raw_value is not None:
            return float(raw_value)
    return default


def _normalize(value: Any) -> Any:
    if isinstance(value, np.ndarray):
        return value.tolist()
    if isinstance(value, np.generic):
        return value.item()
    if isinstance(value, dict):
        return {key: _normalize(item) for key, item in value.items()}
    if isinstance(value, list):
        return [_normalize(item) for item in value]
    if isinstance(value, tuple):
        return [_normalize(item) for item in value]
    return value
