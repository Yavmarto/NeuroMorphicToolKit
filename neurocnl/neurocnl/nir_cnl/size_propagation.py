"""Shared NIR-native population-size inference.

A `LIF`/`Input`/`Output` node with no explicit neuron count declared in CNL
has no size of its own — it has to be inferred from network topology (a
directly-wired `Linear` layer's declared weight-matrix shape, or a
same-size passthrough neighbor). This lives in one place so every consumer
of NIR-native records (the deploy/training IR builder and the canvas
projection builder) infers the same size for the same network, instead of
one of them silently defaulting to 1.
"""

from __future__ import annotations

from typing import Any

import numpy as np

from neurocnl.ir import LoweringError
from neurocnl.nir_cnl.ir_types import ArraySpec, ArrayValues, NIRNodeRecord

POPULATION_PRIMITIVES: frozenset[str] = frozenset({"Input", "Output", "LIF"})


def shape_product(shape: tuple[int, ...]) -> int:
    size = 1
    for axis in shape:
        size *= int(axis)
    return size


def require_int_tuple_param(record: NIRNodeRecord, param_name: str) -> tuple[int, ...]:
    raw = record.params.get(param_name)
    if not isinstance(raw, tuple):
        raise LoweringError(
            f"NIR-native size inference expected {record.primitive}.{param_name} "
            f"to be an integer tuple for node {record.name!r}."
        )
    return tuple(int(value) for value in raw)


def vector_values(raw: object) -> np.ndarray[Any, Any]:
    if isinstance(raw, ArraySpec):
        return np.zeros(raw.shape, dtype=float)
    if isinstance(raw, ArrayValues):
        return np.asarray(raw.values, dtype=float).reshape(raw.shape)
    if isinstance(raw, int | float):
        return np.asarray([float(raw)], dtype=float)
    raise LoweringError(
        "NIR-native size inference expected a scalar or vector-valued parameter."
    )


def linear_weight_matrix(record: NIRNodeRecord) -> np.ndarray[Any, Any]:
    raw = record.params.get("weight")
    if isinstance(raw, ArraySpec):
        return np.zeros(raw.shape, dtype=float)
    if isinstance(raw, ArrayValues):
        return np.asarray(raw.values, dtype=float).reshape(raw.shape)
    raise LoweringError(
        f"NIR-native size inference requires an explicit weight matrix shape for "
        f"linear node {record.name!r}."
    )


def population_size_hint(record: NIRNodeRecord) -> int | None:
    if record.primitive == "Input":
        return shape_product(require_int_tuple_param(record, "input_type"))
    if record.primitive == "Output":
        return shape_product(require_int_tuple_param(record, "output_type"))
    if record.primitive == "LIF":
        for param_name in ("tau", "r", "v_leak", "v_threshold"):
            raw = record.params.get(param_name)
            if raw is None:
                continue
            values = vector_values(raw)
            if values.ndim == 1 and values.size > 1:
                return int(values.size)
    return None


def propagate_nir_sizes(
    node_records: dict[str, NIRNodeRecord],
    outgoing: dict[str, list[str]],
    incoming: dict[str, list[str]],
) -> dict[str, int]:
    """Fixed-point size propagation across a NIR-native node/edge graph.

    Reads each `Linear` node's declared weight-matrix shape and every
    population's own size hint (an explicit shape or a multi-valued
    parameter), then propagates outward — a `Linear` layer fixes the sizes
    of its immediate neighbors, and any two directly-connected non-`Linear`
    nodes must share the same size — until nothing changes. Raises
    `LoweringError` on a genuinely unresolvable or inconsistent topology.
    """
    sizes: dict[str, int | None] = {
        name: population_size_hint(record) for name, record in node_records.items()
    }

    changed = True
    while changed:
        changed = False
        for name, record in node_records.items():
            if record.primitive == "Linear":
                weights = linear_weight_matrix(record)
                if weights.ndim != 2:
                    raise LoweringError(
                        f"NIR-native size inference expects a 2D weight matrix for "
                        f"linear node {name!r}."
                    )
                in_size = int(weights.shape[1])
                out_size = int(weights.shape[0])
                if sizes[name] is None:
                    sizes[name] = out_size
                    changed = True
                for parent in incoming.get(name, []):
                    if sizes[parent] is None:
                        sizes[parent] = in_size
                        changed = True
                    elif sizes[parent] != in_size:
                        raise LoweringError(
                            f"NIR-native size inference found incompatible input size for "
                            f"node {parent!r}: inferred {sizes[parent]} but linear node {name!r} "
                            f"requires {in_size}."
                        )
                for child in outgoing.get(name, []):
                    if sizes[child] is None:
                        sizes[child] = out_size
                        changed = True
                    elif sizes[child] != out_size:
                        raise LoweringError(
                            f"NIR-native size inference found incompatible output size for "
                            f"node {child!r}: inferred {sizes[child]} but linear node {name!r} "
                            f"produces {out_size}."
                        )
                continue

            current_size = sizes[name]
            if current_size is None:
                continue
            for parent in incoming.get(name, []):
                parent_record = node_records[parent]
                if parent_record.primitive != "Linear":
                    if sizes[parent] is None:
                        sizes[parent] = current_size
                        changed = True
                    elif sizes[parent] != current_size:
                        raise LoweringError(
                            f"NIR-native size inference found incompatible adjacent node sizes "
                            f"between {parent!r} and {name!r}."
                        )
            for child in outgoing.get(name, []):
                child_record = node_records[child]
                if child_record.primitive != "Linear":
                    if sizes[child] is None:
                        sizes[child] = current_size
                        changed = True
                    elif sizes[child] != current_size:
                        raise LoweringError(
                            f"NIR-native size inference found incompatible adjacent node sizes "
                            f"between {name!r} and {child!r}."
                        )

    unresolved = sorted(
        name
        for name, record in node_records.items()
        if record.primitive in POPULATION_PRIMITIVES and sizes[name] is None
    )
    if unresolved:
        raise LoweringError(
            "NIR-native size inference could not infer population sizes for "
            f"{', '.join(repr(name) for name in unresolved)}."
        )

    return {name: int(size) for name, size in sizes.items() if size is not None}
