"""Helpers for CNL documents with embedded NIR round-trip metadata."""

from __future__ import annotations

import json
import re
from dataclasses import asdict, is_dataclass
from typing import Any

import nir
import numpy as np

from neurocnl.ir.types import (
    ConnectionIR,
    LearningRuleIR,
    NetworkIR,
    PopulationIR,
    SourceProvenance,
    TimingDeclarationIR,
)

NIR_METADATA_BEGIN = "# neurocnl:nir-metadata:v1 begin"
NIR_METADATA_END = "# neurocnl:nir-metadata:v1 end"

_ITEM_KEY_RE = re.compile(r"^item_(\d+)$")


def split_cnl_document(spec_text: str) -> tuple[str, dict[str, Any] | None]:
    """Split a CNL document into plain grammar text and an embedded metadata block."""
    lines = spec_text.splitlines()
    grammar_lines: list[str] = []
    metadata_lines: list[str] = []
    in_metadata = False

    for line in lines:
        stripped = line.strip()
        if stripped == NIR_METADATA_BEGIN:
            in_metadata = True
            continue
        if stripped == NIR_METADATA_END:
            in_metadata = False
            continue
        if in_metadata:
            content = stripped[1:].lstrip() if stripped.startswith("#") else stripped
            metadata_lines.append(content)
            continue
        grammar_lines.append(line)

    metadata = None
    if metadata_lines:
        payload = "\n".join(metadata_lines).strip()
        if payload:
            metadata = json.loads(payload)

    return "\n".join(grammar_lines), metadata


def extract_embedded_ir(spec_text: str) -> NetworkIR | None:
    """Return embedded IR metadata when present in a CNL document."""
    _, metadata = split_cnl_document(spec_text)
    if not metadata:
        return None
    if metadata.get("format") != "neurocnl.nir-metadata.v1":
        return None
    ir_payload = metadata.get("ir")
    if not isinstance(ir_payload, dict):
        return None
    return deserialize_ir(ir_payload)


def render_cnl_document(ir: NetworkIR) -> str:
    """Render a canonical CNL document plus a machine-readable metadata block."""
    grammar_lines = emit_canonical_cnl(ir)
    metadata_json = json.dumps(
        {
            "format": "neurocnl.nir-metadata.v1",
            "ir": serialize_ir(ir),
        },
        indent=2,
        sort_keys=True,
    ).splitlines()

    comment_lines = [NIR_METADATA_BEGIN]
    comment_lines.extend(f"# {line}" if line else "#" for line in metadata_json)
    comment_lines.append(NIR_METADATA_END)

    parts = ["\n".join(grammar_lines).strip(), "\n".join(comment_lines)]
    return "\n\n".join(part for part in parts if part).strip() + "\n"


def emit_canonical_cnl(ir: NetworkIR) -> list[str]:
    """Emit a grammar-visible summary of a NetworkIR document."""
    lines: list[str] = []

    for population in sorted(ir.populations.values(), key=lambda item: item.name):
        pop_type = population.population_type or "excitatory"
        size = population.size or _shape_size(population.shape) or 1
        line = f"The network MUST contain an {pop_type} {population.name} population of {size} neurons"
        if population.shape is not None:
            line += f" with shape ({', '.join(str(axis) for axis in population.shape)})"
        lines.append(line)

        if population.threshold is not None and abs(population.threshold - 1.0) > 1e-9:
            lines.append(
                f"The {population.name} neuron MUST fire WITH threshold of {population.threshold:g}"
            )

        if (
            population.membrane_time_constant is not None
            and abs(population.membrane_time_constant - 0.02) > 1e-9
        ):
            lines.append(
                f"The {population.name} neuron MUST have membrane decay WITH tau of "
                f"{population.membrane_time_constant * 1000:g} ms"
            )

    for declaration in ir.timing_declarations:
        if declaration.kind == "timestep" and declaration.value is not None:
            lines.append(
                f"The network MUST operate WITH timestep of "
                f"{_format_seconds_or_ms(declaration.value)}"
            )
        elif declaration.kind == "delay_quantization" and declaration.value is not None:
            lines.append(
                f"The network MUST use discrete delays quantized to "
                f"{_format_seconds_or_ms(declaration.value)}"
            )
        elif (
            declaration.kind == "biological_speed_multiplier"
            and declaration.value is not None
        ):
            lines.append(
                f"The network MUST run AT {declaration.value:g}x biological speed"
            )

    for connection in ir.connections:
        source = connection.source
        target = connection.target
        pattern = connection.connectivity_pattern
        if pattern == "one_to_one":
            lines.append(
                f"The {source} MUST connect to {target} WITH one-to-one mapping"
            )
        elif pattern == "binary_mask" and connection.connectivity_mask is not None:
            lines.append(
                f"The {source} MUST connect to {target} WITH explicit binary mask "
                f"{_mask_literal(connection.connectivity_mask)}"
            )
        elif pattern == "local_radius" and connection.locality_radius is not None:
            lines.append(
                f"The {source} MUST connect to {target} WITH local connectivity radius "
                f"of {connection.locality_radius:g}"
            )
        elif pattern == "random_sparsity" and connection.connection_density is not None:
            lines.append(
                f"The {source} MUST connect to {target} WITH "
                f"{connection.connection_density * 100:g}% random sparsity"
            )
        elif connection.polarity == "inhibitory":
            # Emit the weight inline to avoid a conflict between the inhibitory
            # polarity sentence (which defaults to weight=-1.0) and a separate
            # synaptic-weight sentence during round-trip lowering.
            scalar_weight = _scalar_weight_literal(connection.weight)
            if scalar_weight is not None:
                lines.append(
                    f"The connection from {source} to {target} MUST be inhibitory "
                    f"with weight of {scalar_weight:g}"
                )
            else:
                lines.append(
                    f"The connection from {source} to {target} MUST be inhibitory"
                )
        else:
            lines.append(f"The {source} MUST project to {target}")

        if connection.polarity != "inhibitory":
            scalar_weight = _scalar_weight_literal(connection.weight)
            if scalar_weight is not None:
                lines.append(
                    f"The connection from {source} to {target} MUST have WITH synaptic weight of "
                    f"{scalar_weight:g}"
                )

        if connection.delay is not None:
            lines.append(
                f"The connection from {source} to {target} MUST have WITH axonal delay of "
                f"{_format_seconds_or_ms(connection.delay)}"
            )

    for rule in ir.learning_rules:
        if rule.kind == "stdp" and rule.source and rule.target:
            rate = f"{rule.rate:g}" if rule.rate is not None else "0"
            # Emit the parser-accepted form ("adapt WITH STDP learning rate of ...").
            # The window value is preserved losslessly in the embedded IR metadata block.
            lines.append(
                f"The connection from {rule.source} to {rule.target} MUST adapt WITH STDP "
                f"learning rate of {rate}"
            )

    return lines


def nir_import_diagnostics(graph: nir.NIRGraph) -> list[dict[str, Any]]:
    """Return structured diagnostics for NIR primitives we cannot translate honestly."""
    supported_types = (nir.Input, nir.Output, nir.LIF, nir.Linear, nir.Delay)
    diagnostics: list[dict[str, Any]] = []

    for node_name, node in graph.nodes.items():
        if isinstance(node, supported_types):
            continue
        primitive = type(node).__name__
        diagnostics.append(
            {
                "code": "unsupported_nir_primitive",
                "node_id": node_name,
                "primitive": primitive,
                "message": (
                    f"NIR primitive {primitive!r} at node {node_name!r} cannot be translated "
                    "to canonical CNL."
                ),
                "hint": (
                    "Use NeuroCNL-supported NIR nodes (Input, Output, LIF, Linear, Delay) "
                    "or supply a graph exported by NeuroCNL so advisory metadata is available."
                ),
            }
        )

    return diagnostics


def serialize_ir(ir: NetworkIR) -> dict[str, Any]:
    """Serialize NetworkIR into JSON-safe data."""
    return {
        "populations": {
            name: _normalize_json(asdict(population))
            for name, population in sorted(ir.populations.items())
        },
        "connections": [
            _normalize_json(asdict(connection)) for connection in ir.connections
        ],
        "learning_rules": [_normalize_json(asdict(rule)) for rule in ir.learning_rules],
        "timing_declarations": [
            _normalize_json(asdict(declaration))
            for declaration in ir.timing_declarations
        ],
        "metadata": _normalize_json(ir.metadata),
    }


def deserialize_ir(payload: dict[str, Any]) -> NetworkIR:
    """Deserialize JSON-safe data into NetworkIR."""
    populations = {
        name: PopulationIR(
            name=item["name"],
            size=item.get("size"),
            dimensions=item.get("dimensions"),
            shape=tuple(item["shape"]) if item.get("shape") is not None else None,
            role=item.get("role"),
            population_type=item.get("population_type"),
            threshold=item.get("threshold"),
            refractory_period=item.get("refractory_period"),
            membrane_time_constant=item.get("membrane_time_constant"),
            provenance=_decode_provenance_list(item.get("provenance", [])),
            attributes=dict(item.get("attributes", {})),
        )
        for name, item in payload.get("populations", {}).items()
    }
    connections = [
        ConnectionIR(
            source=item["source"],
            target=item["target"],
            weight=_decode_weight(item.get("weight")),
            delay=item.get("delay"),
            polarity=item.get("polarity"),
            connectivity_pattern=item.get("connectivity_pattern"),
            connectivity_mask=(
                tuple(
                    tuple(int(value) for value in row)
                    for row in item["connectivity_mask"]
                )
                if item.get("connectivity_mask") is not None
                else None
            ),
            locality_radius=item.get("locality_radius"),
            connection_density=item.get("connection_density"),
            provenance=_decode_provenance_list(item.get("provenance", [])),
            attributes=dict(item.get("attributes", {})),
        )
        for item in payload.get("connections", [])
    ]
    learning_rules = [
        LearningRuleIR(
            kind=item["kind"],
            source=item.get("source"),
            target=item.get("target"),
            rate=item.get("rate"),
            window=item.get("window"),
            weight_min=item.get("weight_min"),
            weight_max=item.get("weight_max"),
            provenance=_decode_provenance_list(item.get("provenance", [])),
            attributes=dict(item.get("attributes", {})),
        )
        for item in payload.get("learning_rules", [])
    ]
    timing_declarations = [
        TimingDeclarationIR(
            kind=item["kind"],
            value=item.get("value"),
            unit=item.get("unit"),
            provenance=_decode_provenance_list(item.get("provenance", [])),
            attributes=dict(item.get("attributes", {})),
        )
        for item in payload.get("timing_declarations", [])
    ]
    metadata = dict(payload.get("metadata", {}))
    return NetworkIR(
        populations=populations,
        connections=connections,
        learning_rules=learning_rules,
        timing_declarations=timing_declarations,
        metadata=metadata,
    )


def import_ir_from_nir(graph: nir.NIRGraph) -> NetworkIR:
    """Reconstruct NetworkIR from a NIR graph using NeuroCNL metadata."""
    graph_metadata = _decode_item_maps(dict(getattr(graph, "metadata", {}) or {}))
    populations: dict[str, PopulationIR] = {}

    for node_name, node in graph.nodes.items():
        metadata = _decode_item_maps(dict(getattr(node, "metadata", {}) or {}))
        if isinstance(node, nir.Input):
            size = _infer_input_size(node)
            populations[node_name] = PopulationIR(
                name=metadata.get("ir_name", node_name),
                size=size,
                role="input",
                population_type=metadata.get("population_type", "excitatory"),
                threshold=metadata.get("attributes", {}).get("threshold"),
                refractory_period=metadata.get("refractory_period"),
                provenance=_decode_provenance_list(metadata.get("provenance", [])),
                attributes=dict(metadata.get("attributes", {})),
                shape=_shape_tuple(metadata.get("shape")),
            )
        elif isinstance(node, nir.Output):
            size = _infer_output_size(node)
            populations[node_name] = PopulationIR(
                name=metadata.get("ir_name", node_name),
                size=size,
                role="output",
                population_type=metadata.get("population_type", "excitatory"),
                threshold=metadata.get("attributes", {}).get("threshold"),
                refractory_period=metadata.get("refractory_period"),
                provenance=_decode_provenance_list(metadata.get("provenance", [])),
                attributes=dict(metadata.get("attributes", {})),
                shape=_shape_tuple(metadata.get("shape")),
            )
        elif isinstance(node, nir.LIF):
            populations[node_name] = PopulationIR(
                name=metadata.get("ir_name", node_name),
                size=int(node.tau.size),
                threshold=float(np.asarray(node.v_threshold).flat[0]),
                refractory_period=metadata.get("refractory_period"),
                membrane_time_constant=float(np.asarray(node.tau).flat[0]),
                population_type=metadata.get("population_type", "excitatory"),
                role=metadata.get("role"),
                provenance=_decode_provenance_list(metadata.get("provenance", [])),
                attributes=dict(metadata.get("attributes", {})),
                shape=_shape_tuple(metadata.get("shape")),
            )

    incoming: dict[str, list[str]] = {}
    outgoing: dict[str, list[str]] = {}
    for source, target in graph.edges:
        incoming.setdefault(target, []).append(source)
        outgoing.setdefault(source, []).append(target)

    connections: list[ConnectionIR] = []
    for node_name, node in graph.nodes.items():
        if not isinstance(node, nir.Linear):
            continue
        metadata = _decode_item_maps(dict(getattr(node, "metadata", {}) or {}))
        source_candidates = incoming.get(node_name, [])
        target_candidates = outgoing.get(node_name, [])
        if len(source_candidates) != 1 or len(target_candidates) != 1:
            continue
        source_name = source_candidates[0]
        next_name = target_candidates[0]
        delay = metadata.get("delay")
        target_name = next_name
        if isinstance(graph.nodes.get(next_name), nir.Delay):
            delay_metadata = _decode_item_maps(
                dict(getattr(graph.nodes[next_name], "metadata", {}) or {})
            )
            delay = delay_metadata.get("delay", delay)
            delay_targets = outgoing.get(next_name, [])
            if len(delay_targets) == 1:
                target_name = delay_targets[0]

        connections.append(
            ConnectionIR(
                source=metadata.get("source", source_name),
                target=metadata.get("target", target_name),
                weight=np.asarray(node.weight, dtype=float),
                delay=delay,
                polarity=metadata.get("polarity"),
                connectivity_pattern=metadata.get("connectivity_pattern"),
                connectivity_mask=(
                    tuple(
                        tuple(int(value) for value in row)
                        for row in metadata.get("connectivity_mask", [])
                    )
                    if metadata.get("connectivity_mask") is not None
                    else None
                ),
                locality_radius=metadata.get("locality_radius"),
                connection_density=metadata.get("connection_density"),
                provenance=_decode_provenance_list(metadata.get("provenance", [])),
                attributes=dict(metadata.get("attributes", {})),
            )
        )

    # Reconstruct implicit connections (direct edges between populations without a Linear node)
    for source, target in graph.edges:
        source_node = graph.nodes.get(source)
        target_node = graph.nodes.get(target)
        if isinstance(source_node, nir.Linear | nir.Delay) or isinstance(
            target_node, nir.Linear | nir.Delay
        ):
            continue
        connections.append(
            ConnectionIR(
                source=source,
                target=target,
                weight=1.0,
            )
        )

    learning_rules: list[LearningRuleIR] = []
    for connection in connections:
        for rule in _decode_item_maps(
            connection.attributes.get("embedded_learning_rules", [])
        ):
            if not isinstance(rule, dict):
                continue
            learning_rules.append(
                LearningRuleIR(
                    kind=rule["kind"],
                    source=rule.get("source"),
                    target=rule.get("target"),
                    rate=rule.get("rate"),
                    window=rule.get("window"),
                    weight_min=rule.get("weight_min"),
                    weight_max=rule.get("weight_max"),
                    provenance=_decode_provenance_list(rule.get("provenance", [])),
                    attributes=dict(rule.get("attributes", {})),
                )
            )

    for node_name, node in graph.nodes.items():
        if isinstance(node, nir.Linear):
            metadata = _decode_item_maps(dict(getattr(node, "metadata", {}) or {}))
            for rule in _ensure_list(metadata.get("learning_rules", [])):
                if not isinstance(rule, dict):
                    continue
                learning_rules.append(
                    LearningRuleIR(
                        kind=rule["kind"],
                        source=rule.get("source"),
                        target=rule.get("target"),
                        rate=rule.get("rate"),
                        window=rule.get("window"),
                        weight_min=rule.get("weight_min"),
                        weight_max=rule.get("weight_max"),
                        provenance=_decode_provenance_list(rule.get("provenance", [])),
                        attributes=dict(rule.get("attributes", {})),
                    )
                )

    timing_declarations = [
        TimingDeclarationIR(
            kind=item["kind"],
            value=item.get("value"),
            unit=item.get("unit"),
            provenance=_decode_provenance_list(item.get("provenance", [])),
            attributes=dict(item.get("attributes", {})),
        )
        for item in _ensure_list(graph_metadata.get("timing_declarations", []))
        if isinstance(item, dict)
    ]

    result_metadata: dict[str, Any] = {}
    for key in (
        "global_receptor_dynamics",
        "neuromodulation_rules",
        "short_term_plasticity_rules",
        "population_shapes",
        "provenance",
        "dt",
    ):
        if key in graph_metadata:
            result_metadata[key] = graph_metadata[key]

    return NetworkIR(
        populations={
            population.name: population for population in populations.values()
        },
        connections=connections,
        learning_rules=learning_rules,
        timing_declarations=timing_declarations,
        metadata=result_metadata,
    )


def _format_seconds_or_ms(value: float) -> str:
    milliseconds = value * 1000.0
    if abs(round(milliseconds) - milliseconds) < 1e-9:
        return f"{round(milliseconds):g} ms"
    return f"{value:g} seconds"


def _shape_size(shape: tuple[int, ...] | None) -> int | None:
    if shape is None:
        return None
    size = 1
    for axis in shape:
        size *= axis
    return size


def _normalize_json(value: Any) -> Any:
    if is_dataclass(value) and not isinstance(value, type):
        return _normalize_json(asdict(value))
    if isinstance(value, np.ndarray):
        return value.tolist()
    if isinstance(value, np.generic):
        return value.item()
    if isinstance(value, dict):
        return {key: _normalize_json(item) for key, item in value.items()}
    if isinstance(value, list):
        return [_normalize_json(item) for item in value]
    if isinstance(value, tuple):
        return [_normalize_json(item) for item in value]
    return value


def _decode_provenance_list(
    items: list[dict[str, Any]] | dict[str, Any]
) -> list[SourceProvenance]:
    decoded = _ensure_list(items)
    return [
        SourceProvenance(
            line=item.get("line"),
            raw=item.get("raw"),
            concept=item.get("concept"),
        )
        for item in decoded
        if isinstance(item, dict)
    ]


def _decode_weight(value: Any) -> Any:
    if isinstance(value, list):
        return np.asarray(value, dtype=float)
    return value


def _mask_literal(mask: tuple[tuple[int, ...], ...]) -> str:
    rows = [f"[{', '.join(str(value) for value in row)}]" for row in mask]
    return f"[{', '.join(rows)}]"


def _scalar_weight_literal(value: Any) -> float | None:
    if isinstance(value, int | float):
        return float(value)
    if isinstance(value, np.ndarray):
        if value.size == 1:
            return float(value.flat[0])
        first = float(value.flat[0])
        if np.allclose(value, first):
            return first
    return None


def _decode_item_maps(value: Any) -> Any:
    if isinstance(value, dict):
        item_keys = [_ITEM_KEY_RE.fullmatch(key) for key in value]
        if value and all(match is not None for match in item_keys):
            ordered = sorted(
                (
                    (int(match.group(1)), item)
                    for match, item in zip(item_keys, value.values(), strict=False)
                    if match is not None
                ),
                key=lambda pair: pair[0],
            )
            return [_decode_item_maps(item) for _, item in ordered]
        return {key: _decode_item_maps(item) for key, item in value.items()}
    if isinstance(value, list):
        return [_decode_item_maps(item) for item in value]
    return value


def _ensure_list(value: Any) -> list[Any]:
    decoded = _decode_item_maps(value)
    if isinstance(decoded, list):
        return decoded
    if decoded is None:
        return []
    return [decoded]


def _shape_tuple(value: Any) -> tuple[int, ...] | None:
    if value is None:
        return None
    if isinstance(value, list):
        return tuple(int(item) for item in value)
    return None


def _infer_input_size(node: nir.Input) -> int:
    input_type = _decode_item_maps(node.input_type)
    if isinstance(input_type, dict):
        first = next(iter(input_type.values()), [1])
        if first is None:
            return 1
        val = np.asarray(first).flat[0]
        return int(val) if val is not None else 1
    return 1


def _infer_output_size(node: nir.Output) -> int:
    output_type = _decode_item_maps(node.output_type)
    if isinstance(output_type, dict):
        first = next(iter(output_type.values()), [1])
        if first is None:
            return 1
        val = np.asarray(first).flat[0]
        return int(val) if val is not None else 1
    return 1
