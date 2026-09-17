"""Service for validating canvas graphs against Layer 1 invariants."""

from typing import Any

from pydantic import BaseModel

from backend.app.services.nir_graph_serializer import (
    NIR_CANVAS_TYPE_SPECS,
    NirCanvasConversionError,
    deserialize_canvas_graph,
)
from neurosim.contracts.design_contracts import (
    CanvasEdge,
    CanvasGraph,
    CanvasNode,
    ValidationError,
    ValidationResult,
)


class PortType(BaseModel):
    scalar_type: str
    rank: int | None = None
    dims: list[int | None] | None = None

    def is_compatible_with(self, other: "PortType") -> bool:
        if self.scalar_type != other.scalar_type:
            return False
        if self.rank is not None and other.rank is not None and self.rank != other.rank:
            return False
        if self.dims is not None and other.dims is not None:
            for d1, d2 in zip(self.dims, other.dims, strict=False):
                if d1 is not None and d2 is not None and d1 != d2:
                    return False
        return True


from .components import load_components
from .nir_support import assess_validation_support, validate_semantics


def _build_component_port_maps(
    components: dict[str, Any]
) -> dict[str, dict[str, set[str]]]:
    """Build a map of component IDs to their input and output ports.

    Args:
        components (dict[str, Any]): The loaded component registry.

    Returns:
        dict[str, dict[str, set[str]]]: Mapping of component_id to port direction sets.
    """
    component_port_maps = {}
    for cid, cdef in components.items():
        in_ports = {p.id for p in getattr(cdef, "ports", []) if p.direction == "input"}
        out_ports = {
            p.id for p in getattr(cdef, "ports", []) if p.direction == "output"
        }
        component_port_maps[cid] = {"input": in_ports, "output": out_ports}
    return component_port_maps


def _validate_nodes(
    nodes: list[CanvasNode],
    components: dict[str, Any],
    errors: list[ValidationError],
) -> None:
    """Validate nodes and their parameters.

    Args:
        nodes (list[CanvasNode]): The list of canvas nodes to validate.
        components (dict[str, Any]): The loaded component registry.
        errors (list[ValidationError]): Accumulator for validation errors.
    """
    for node in nodes:
        if node.nir_type is not None:
            if node.nir_type not in NIR_CANVAS_TYPE_SPECS:
                errors.append(
                    ValidationError(
                        element_id=node.id,
                        field="nir_type",
                        message=f"Unknown NIR node type '{node.nir_type}'.",
                    ),
                )
                continue

            if node.nir_type in {"nir.LIF", "nir.CubaLIF", "nir.LI"}:
                tau_value = node.parameters.get("tau") or node.parameters.get("tau_rc")
                if isinstance(tau_value, int | float) and tau_value <= 0:
                    errors.append(
                        ValidationError(
                            element_id=node.id,
                            field="parameters.tau",
                            message="Membrane time constant must be positive.",
                        ),
                    )
            if node.nir_type == "nir.CubaLIF":
                tau_syn = node.parameters.get("tau_syn")
                if isinstance(tau_syn, int | float) and tau_syn <= 0:
                    errors.append(
                        ValidationError(
                            element_id=node.id,
                            field="parameters.tau_syn",
                            message="Synaptic time constant must be positive.",
                        ),
                    )
            if node.nir_type in {"nir.LIF", "nir.CubaLIF", "nir.IF"}:
                threshold = node.parameters.get("threshold") or node.parameters.get(
                    "v_threshold"
                )
                if isinstance(threshold, int | float) and threshold <= 0:
                    errors.append(
                        ValidationError(
                            element_id=node.id,
                            field="parameters.threshold",
                            message="Threshold must be positive.",
                            severity="warning",
                        ),
                    )
            continue

        # Check component_id references a known component
        if node.component_id not in components:
            errors.append(
                ValidationError(
                    element_id=node.id,
                    field="component_id",
                    message=f"Unknown component type '{node.component_id}'.",
                ),
            )
            continue

        block = components[node.component_id]
        param_defs = {p.name: p for p in block.parameters}

        # Check parameter values against definitions
        for pname, pval in node.parameters.items():
            if pname == "name":
                continue
            if pname not in param_defs:
                errors.append(
                    ValidationError(
                        element_id=node.id,
                        field=f"parameters.{pname}",
                        message=f"Unknown parameter '{pname}' for component '{node.component_id}'.",
                        severity="warning",
                    ),
                )
                continue

            pdef = param_defs[pname]

            # Range checks for numeric types
            if pdef.type in ("float", "int") and isinstance(pval, int | float):
                if pdef.min is not None and pval < pdef.min:
                    errors.append(
                        ValidationError(
                            element_id=node.id,
                            field=f"parameters.{pname}",
                            message=f"'{pdef.label}' value {pval} is below minimum {pdef.min}.",
                        ),
                    )
                if pdef.max is not None and pval > pdef.max:
                    errors.append(
                        ValidationError(
                            element_id=node.id,
                            field=f"parameters.{pname}",
                            message=f"'{pdef.label}' value {pval} exceeds maximum {pdef.max}.",
                        ),
                    )

            # Enum checks
            if pdef.type == "enum" and pdef.enum_values:
                if pval not in pdef.enum_values:
                    errors.append(
                        ValidationError(
                            element_id=node.id,
                            field=f"parameters.{pname}",
                            message=(
                                f"'{pdef.label}' value '{pval}' is not one of {pdef.enum_values}."
                            ),
                        ),
                    )

        # Cross-parameter biological invariants via neurocnl
        if node.component_id in ("lif_population", "adaptive_lif"):
            semantic_errors = validate_semantics(node.parameters)
            for err_msg in semantic_errors:
                errors.append(
                    ValidationError(
                        element_id=node.id,
                        field="parameters",
                        message=err_msg,
                        severity="error",
                    ),
                )

            # neurocnl only checks tau > 0 and refractory_period > 0 independently;
            # the tau_ref < tau_rc biological invariant must be checked explicitly here.
            tau_rc = node.parameters.get("tau_rc")
            tau_ref = node.parameters.get("tau_ref")
            if isinstance(tau_rc, int | float) and isinstance(tau_ref, int | float):
                if tau_ref >= tau_rc:
                    errors.append(
                        ValidationError(
                            element_id=node.id,
                            field="parameters.tau_ref",
                            message=f"tau_ref ({tau_ref}) must be less than tau_rc ({tau_rc}).",
                            severity="error",
                        ),
                    )


def _infer_port_type(node: CanvasNode, port_id: str) -> PortType | None:
    """Return the inferred PortType for a port based on node parameters.

    Returns None for unknown node types (no type constraint imposed).
    """
    nir = node.nir_type
    p = node.parameters

    float1d_any = PortType(scalar_type="float32", rank=1, dims=[None])
    float3d_any = PortType(scalar_type="float32", rank=3, dims=[None, None, None])

    def parse_shape(s: Any) -> list[int | None]:
        if not isinstance(s, str):
            return []
        parts: list[int | None] = []
        for part in s.split(","):
            try:
                parts.append(int(part.strip()))
            except ValueError:
                parts.append(None)
        return parts

    type_map: dict[str, dict[str, PortType]] = {
        "nir.Input": {
            "out": PortType(scalar_type="float32", rank=1, dims=[p.get("size")]),
        },
        "nir.Output": {
            "in": PortType(scalar_type="float32", rank=1, dims=[p.get("size")]),
        },
        "nir.Linear": {
            "in": PortType(scalar_type="float32", rank=1, dims=[p.get("cols")]),
            "out": PortType(scalar_type="float32", rank=1, dims=[p.get("rows")]),
        },
        "nir.Affine": {
            "in": PortType(scalar_type="float32", rank=1, dims=[p.get("cols")]),
            "out": PortType(scalar_type="float32", rank=1, dims=[p.get("rows")]),
        },
        "nir.Flatten": {
            "in": PortType(scalar_type="float32"),  # any rank
            "out": float1d_any,
        },
        "nir.AvgPool2d": {"in": float3d_any, "out": float3d_any},
        "nir.SumPool2d": {"in": float3d_any, "out": float3d_any},
        "nir.Scale": {"in": float1d_any, "out": float1d_any},
        "nir.Delay": {"in": float1d_any, "out": float1d_any},
        "cnl.Dropout": {"in": float1d_any, "out": float1d_any},
    }

    # Conv types: derive channels from weight_shape
    shape = parse_shape(p.get("weight_shape"))
    out_ch = shape[0] if len(shape) > 0 else None
    in_ch = shape[1] if len(shape) > 1 else None
    type_map["nir.Conv1d"] = {
        "in": PortType(scalar_type="float32", rank=2, dims=[in_ch, None]),
        "out": PortType(scalar_type="float32", rank=2, dims=[out_ch, None]),
    }
    type_map["nir.Conv2d"] = {
        "in": PortType(scalar_type="float32", rank=3, dims=[in_ch, None, None]),
        "out": PortType(scalar_type="float32", rank=3, dims=[out_ch, None, None]),
    }

    # Neuron types: typed by n_neurons
    n = p.get("n_neurons")
    neuron_type = PortType(scalar_type="float32", rank=1, dims=[n])
    for ntype in (
        "nir.LIF",
        "nir.CubaLIF",
        "nir.IF",
        "nir.LI",
        "cnl.Synaptic",
        "cnl.RSynaptic",
        "cnl.RLeaky",
        "cnl.Leaky",
    ):
        type_map[ntype] = {"in": neuron_type, "out": neuron_type}

    # BatchNorm1d: typed by num_features
    nf = p.get("num_features")
    bn_type = PortType(scalar_type="float32", rank=1, dims=[nf])
    type_map["cnl.BatchNorm1d"] = {"in": bn_type, "out": bn_type}

    return type_map.get(nir or "", {}).get(port_id)


def _validate_edges(
    edges: list[CanvasEdge],
    node_map: dict[str, CanvasNode],
    component_port_maps: dict[str, dict[str, set[str]]],
    errors: list[ValidationError],
) -> None:
    """Validate edges and their port connections.

    Args:
        edges (list[CanvasEdge]): The list of canvas edges to validate.
        node_map (dict[str, CanvasNode]): Lookup map of node id to node.
        component_port_maps (dict): Component port direction maps.
        errors (list[ValidationError]): Accumulator for validation errors.
    """
    for edge in edges:
        # Check source and target nodes exist
        if edge.source_node_id not in node_map:
            errors.append(
                ValidationError(
                    element_id=edge.id,
                    field="source_node_id",
                    message=f"Source node '{edge.source_node_id}' does not exist.",
                ),
            )
        else:
            # Check source port exists on the source node's component
            src_node = node_map[edge.source_node_id]
            if src_node.nir_type in NIR_CANVAS_TYPE_SPECS:
                src_ports = set(NIR_CANVAS_TYPE_SPECS[src_node.nir_type].output_ports)
                if edge.source_port not in src_ports:
                    errors.append(
                        ValidationError(
                            element_id=edge.id,
                            field="source_port",
                            message=(
                                f"Port '{edge.source_port}' is not an output port on "
                                f"'{src_node.nir_type}'."
                            ),
                        ),
                    )
            elif src_node.component_id in component_port_maps:
                src_ports = component_port_maps[src_node.component_id]["output"]
                if edge.source_port not in src_ports:
                    errors.append(
                        ValidationError(
                            element_id=edge.id,
                            field="source_port",
                            message=(
                                f"Port '{edge.source_port}' is not an output port on "
                                f"'{src_node.component_id}'."
                            ),
                        ),
                    )

        if edge.target_node_id not in node_map:
            errors.append(
                ValidationError(
                    element_id=edge.id,
                    field="target_node_id",
                    message=f"Target node '{edge.target_node_id}' does not exist.",
                ),
            )
        else:
            # Check target port exists on the target node's component
            tgt_node = node_map[edge.target_node_id]
            if tgt_node.nir_type in NIR_CANVAS_TYPE_SPECS:
                tgt_ports = set(NIR_CANVAS_TYPE_SPECS[tgt_node.nir_type].input_ports)
                if edge.target_port not in tgt_ports:
                    errors.append(
                        ValidationError(
                            element_id=edge.id,
                            field="target_port",
                            message=(
                                f"Port '{edge.target_port}' is not an input port on "
                                f"'{tgt_node.nir_type}'."
                            ),
                        ),
                    )
            elif tgt_node.component_id in component_port_maps:
                tgt_ports = component_port_maps[tgt_node.component_id]["input"]
                if edge.target_port not in tgt_ports:
                    errors.append(
                        ValidationError(
                            element_id=edge.id,
                            field="target_port",
                            message=(
                                f"Port '{edge.target_port}' is not an input port on "
                                f"'{tgt_node.component_id}'."
                            ),
                        ),
                    )

        # Self-connection check
        if edge.source_node_id == edge.target_node_id:
            errors.append(
                ValidationError(
                    element_id=edge.id,
                    field="target_node_id",
                    message="Self-connections are not allowed.",
                    severity="warning",
                ),
            )

        # Type compatibility check
        if edge.source_node_id in node_map and edge.target_node_id in node_map:
            src_type = _infer_port_type(node_map[edge.source_node_id], edge.source_port)
            tgt_type = _infer_port_type(node_map[edge.target_node_id], edge.target_port)
            if src_type is not None and tgt_type is not None:
                if not src_type.is_compatible_with(tgt_type):
                    errors.append(
                        ValidationError(
                            element_id=edge.id,
                            field="source_port",
                            message=(
                                f"Type mismatch: {edge.source_port}({src_type}) "
                                f"→ {edge.target_port}({tgt_type})"
                            ),
                        ),
                    )


def _check_duplicate_node_ids(
    nodes: list[CanvasNode], errors: list[ValidationError]
) -> None:
    """Check for duplicate node IDs in the graph.

    Args:
        nodes (list[CanvasNode]): The list of nodes to inspect.
        errors (list[ValidationError]): Accumulator for validation errors.
    """
    seen_ids: set[str] = set()
    for node in nodes:
        if node.id in seen_ids:
            errors.append(
                ValidationError(
                    element_id=node.id,
                    field="id",
                    message=f"Duplicate node ID '{node.id}'.",
                ),
            )
        seen_ids.add(node.id)


def validate_graph(graph: CanvasGraph) -> ValidationResult:
    """Validate a canvas graph against Layer 1 invariants.

    Args:
        graph (CanvasGraph): The graph to validate.

    Returns:
        ValidationResult: The result of the validation, including errors and backend support.
    """
    errors: list[ValidationError] = []
    components = load_components()
    node_map = {node.id: node for node in graph.nodes}
    component_port_maps = _build_component_port_maps(components)

    _validate_nodes(graph.nodes, components, errors)
    _validate_edges(graph.edges, node_map, component_port_maps, errors)
    _check_duplicate_node_ids(graph.nodes, errors)
    if any(node.nir_type for node in graph.nodes):
        try:
            deserialize_canvas_graph(graph)
        except NirCanvasConversionError as exc:
            errors.append(
                ValidationError(
                    element_id="graph",
                    field="nir_type",
                    message=str(exc),
                ),
            )

    backend_support, generator_fidelity = assess_validation_support(graph)

    return ValidationResult(
        valid=len([e for e in errors if e.severity == "error"]) == 0,
        errors=errors,
        backend_support=backend_support,
        generator_fidelity=generator_fidelity,
    )
