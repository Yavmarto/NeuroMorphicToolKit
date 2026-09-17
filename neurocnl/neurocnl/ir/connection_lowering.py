"""Connection-weight synthesis and shape/representation classification.

Extracted from :mod:`neurocnl.ir.materializer` (Stage 6 refactor). This
module owns the pure, state-free logic that turns a semantic
:class:`~neurocnl.ir.types.ConnectionIR` into a concrete NIR weight
matrix: classifying which representation a connection lowers to (dense
scalar broadcast, dense matrix, structured one-to-one, structured binary
mask, resized heuristic, or metadata-only structured intent), validating
connection shapes, computing the effective axonal delay, and deriving
population-dimension counts. Behaviour and error messages are unchanged
by this move; :class:`~neurocnl.ir.materializer.Materializer` and
:mod:`~neurocnl.ir.lowering_summary` both call through here.
"""

from __future__ import annotations

from typing import Any

import numpy as np

from neurocnl.ir.types import ConnectionIR, NetworkIR, PopulationIR

__all__ = [
    "MaterializerError",
    "apply_connection_polarity",
    "apply_stp_weight_scale",
    "classify_connection_representation",
    "connection_shape_intent",
    "connectivity_mask_array",
    "default_scalar_weight",
    "effective_connection_delay",
    "infer_population_dimension",
    "is_lateral_inhibition_connection",
    "is_scalar_weight_connection",
    "is_structured_intent_connection",
    "local_radius_mask",
    "synthesise_binary_mask_weight",
    "synthesise_lateral_inhibition_weight",
    "synthesise_one_to_one_weight",
    "synthesise_weight",
    "validate_connection_shapes",
]


class MaterializerError(Exception):
    """Raised when a semantic IR graph cannot be materialized to NIR."""


def infer_population_dimension(
    population: PopulationIR, *, default_population_size: int
) -> int:
    if population.shape is not None:
        flattened_size = 1
        for axis in population.shape:
            flattened_size *= axis
        if population.size is not None and population.size != flattened_size:
            raise MaterializerError(
                f"Population {population.name!r} size {population.size} does not match "
                f"shape product {flattened_size}."
            )
        return flattened_size
    if population.size is not None and population.size > 0:
        return population.size
    if population.dimensions is not None and population.dimensions > 0:
        return population.dimensions
    return default_population_size


def is_scalar_weight_connection(connection: ConnectionIR) -> bool:
    return connection.weight is None or np.asarray(connection.weight).ndim == 0


def is_structured_intent_connection(connection: ConnectionIR) -> bool:
    if connection.connectivity_pattern is not None:
        return True
    return any(
        provenance.concept in {"spatial_connectivity", "lateral_inhibition"}
        for provenance in connection.provenance
    )


def is_lateral_inhibition_connection(connection: ConnectionIR) -> bool:
    return any(
        provenance.concept == "lateral_inhibition"
        for provenance in connection.provenance
    )


def classify_connection_representation(
    connection: ConnectionIR,
    *,
    source_size: int,
    target_size: int,
) -> str:
    if connection.connectivity_pattern == "one_to_one":
        return "structured_one_to_one"
    if connection.connectivity_pattern == "binary_mask":
        return "structured_binary_mask"
    if is_structured_intent_connection(connection):
        return "structured_intent_metadata_only"
    if is_scalar_weight_connection(connection):
        return "dense_scalar_broadcast"

    weight_array = np.asarray(connection.weight)
    if weight_array.ndim == 2 and weight_array.shape == (target_size, source_size):
        return "dense_matrix"
    return "resized_heuristic_matrix"


def apply_connection_polarity(
    weight: np.ndarray[Any, Any], connection: ConnectionIR
) -> np.ndarray[Any, Any]:
    weight = np.array(weight, dtype=float, copy=True)
    if connection.polarity == "inhibitory":
        return np.asarray(-np.abs(weight))
    return weight


def default_scalar_weight(connection: ConnectionIR) -> float:
    return -1.0 if connection.polarity == "inhibitory" else 1.0


def apply_stp_weight_scale(
    weight: np.ndarray[Any, Any], connection: ConnectionIR
) -> np.ndarray[Any, Any]:
    stp_type = connection.attributes.get("short_term_plasticity_type")
    utilization_rate = connection.attributes.get("utilization_rate")
    if stp_type == "depression" and isinstance(utilization_rate, int | float):
        return weight * (1.0 - float(utilization_rate))
    return weight


def local_radius_mask(shape: tuple[int, ...], *, radius: float) -> np.ndarray[Any, Any]:
    coordinates = list(np.ndindex(shape))
    size = len(coordinates)
    mask = np.zeros((size, size), dtype=float)
    for target_index, target_coord in enumerate(coordinates):
        for source_index, source_coord in enumerate(coordinates):
            if target_index == source_index:
                continue
            distance = float(
                np.linalg.norm(
                    np.asarray(target_coord, dtype=float)
                    - np.asarray(source_coord, dtype=float)
                )
            )
            if distance <= radius:
                mask[target_index, source_index] = 1.0
    return mask


def connectivity_mask_array(connection: ConnectionIR) -> np.ndarray[Any, Any]:
    if connection.connectivity_mask is None:
        raise MaterializerError("Structured binary-mask connection is missing a mask.")
    return np.asarray(connection.connectivity_mask, dtype=float)


def effective_connection_delay(
    network: NetworkIR, connection: ConnectionIR
) -> float | None:
    if connection.delay is not None:
        return float(connection.delay)
    default_delay = network.metadata.get("default_axonal_delay")
    if default_delay is None:
        return None
    return float(default_delay)


def connection_shape_intent(
    network: NetworkIR,
    connection: ConnectionIR,
) -> dict[str, list[int]] | None:
    source_shape = network.populations[connection.source].shape
    target_shape = network.populations[connection.target].shape
    if source_shape is None and target_shape is None:
        return None
    return {
        key: value
        for key, value in {
            "source_shape": (list(source_shape) if source_shape is not None else None),
            "target_shape": (list(target_shape) if target_shape is not None else None),
        }.items()
        if value is not None
    }


def validate_connection_shapes(
    *,
    network: NetworkIR,
    connection: ConnectionIR,
    source_size: int,
    target_size: int,
) -> None:
    source_shape = network.populations[connection.source].shape
    target_shape = network.populations[connection.target].shape
    if connection.connectivity_pattern == "one_to_one":
        if source_size != target_size:
            raise MaterializerError(
                f"One-to-one connectivity requires equal flattened sizes, got "
                f"{source_size} -> {target_size} for {connection.source!r} -> "
                f"{connection.target!r}."
            )
        if (
            source_shape is not None
            and target_shape is not None
            and source_shape != target_shape
        ):
            raise MaterializerError(
                f"One-to-one connectivity requires matching source/target shapes, got "
                f"{source_shape} -> {target_shape} for {connection.source!r} -> "
                f"{connection.target!r}."
            )
    if connection.connectivity_pattern == "binary_mask":
        mask = connectivity_mask_array(connection)
        if mask.shape != (target_size, source_size):
            raise MaterializerError(
                f"Binary connectivity mask shape {mask.shape} does not match expected "
                f"connection shape {(target_size, source_size)} for "
                f"{connection.source!r} -> {connection.target!r}."
            )


def synthesise_one_to_one_weight(
    connection: ConnectionIR,
    source_size: int,
    target_size: int,
) -> np.ndarray[Any, Any]:
    if source_size != target_size:
        raise MaterializerError(
            f"One-to-one connectivity requires equal flattened sizes, got "
            f"{source_size} -> {target_size} for {connection.source!r} -> "
            f"{connection.target!r}."
        )
    if connection.weight is None:
        diagonal = np.full(source_size, default_scalar_weight(connection), dtype=float)
    else:
        weight_array = np.asarray(connection.weight, dtype=float)
        if weight_array.ndim == 0:
            diagonal = np.full(source_size, float(weight_array.item()), dtype=float)
        elif weight_array.ndim == 1 and weight_array.shape == (source_size,):
            diagonal = weight_array.astype(float, copy=False)
        else:
            raise MaterializerError(
                "One-to-one connectivity currently supports only scalar or "
                "per-neuron diagonal weights."
            )
    return apply_connection_polarity(np.diag(diagonal), connection)


def synthesise_binary_mask_weight(
    connection: ConnectionIR,
    source_size: int,
    target_size: int,
) -> np.ndarray[Any, Any]:
    mask = connectivity_mask_array(connection)
    if mask.shape != (target_size, source_size):
        raise MaterializerError(
            f"Binary connectivity mask shape {mask.shape} does not match expected "
            f"connection shape {(target_size, source_size)} for "
            f"{connection.source!r} -> {connection.target!r}."
        )
    if connection.weight is None:
        weight = mask * default_scalar_weight(connection)
        return weight.astype(float, copy=False)
    weight_array = np.asarray(connection.weight, dtype=float)
    if weight_array.ndim == 0:
        return apply_connection_polarity(mask * float(weight_array.item()), connection)
    if weight_array.ndim == 2 and weight_array.shape == (target_size, source_size):
        return apply_connection_polarity(weight_array * mask, connection)
    raise MaterializerError(
        "Binary-mask connectivity currently supports only scalar weights or an "
        "explicit dense matrix matching the connection shape."
    )


def synthesise_lateral_inhibition_weight(
    network: NetworkIR,
    connection: ConnectionIR,
    source_size: int,
    target_size: int,
) -> np.ndarray[Any, Any]:
    base_weight = (
        default_scalar_weight(connection)
        if connection.weight is None
        else abs(float(np.asarray(connection.weight, dtype=float).reshape(-1)[0]))
    )
    source_population = network.populations[connection.source]
    target_population = network.populations[connection.target]
    if (
        source_population.shape is not None
        and target_population.shape == source_population.shape
        and source_size == target_size
        and connection.locality_radius is not None
    ):
        mask = local_radius_mask(
            source_population.shape, radius=connection.locality_radius
        )
    else:
        mask = np.ones((target_size, source_size), dtype=float)
        if source_size == target_size:
            np.fill_diagonal(mask, 0.0)

    return apply_connection_polarity(mask * abs(base_weight), connection)


def synthesise_weight(
    network: NetworkIR,
    connection: ConnectionIR,
    source_size: int,
    target_size: int,
) -> np.ndarray[Any, Any]:
    representation = classify_connection_representation(
        connection,
        source_size=source_size,
        target_size=target_size,
    )
    if representation == "structured_one_to_one":
        return apply_stp_weight_scale(
            synthesise_one_to_one_weight(connection, source_size, target_size),
            connection,
        )
    if representation == "structured_binary_mask":
        return apply_stp_weight_scale(
            synthesise_binary_mask_weight(connection, source_size, target_size),
            connection,
        )
    if is_lateral_inhibition_connection(connection):
        return synthesise_lateral_inhibition_weight(
            network,
            connection,
            source_size,
            target_size,
        )
    if (
        representation == "structured_intent_metadata_only"
        and connection.connectivity_pattern is not None
    ):
        raise MaterializerError(
            f"Connection {connection.source!r} -> {connection.target!r} uses structured "
            f"connectivity pattern {connection.connectivity_pattern!r}, which the current "
            "NIR materializer can summarize but cannot lower as executable graph weights."
        )
    if connection.weight is None:
        scalar_weight = default_scalar_weight(connection)
        weight = np.full((target_size, source_size), scalar_weight, dtype=float)
        return apply_stp_weight_scale(weight, connection)

    weight_array = np.asarray(connection.weight, dtype=float)
    if weight_array.ndim == 0:
        scalar_weight = float(weight_array.item())
        sign = -1.0 if connection.polarity == "inhibitory" or scalar_weight < 0 else 1.0
        weight = np.full(
            (target_size, source_size), sign * abs(scalar_weight), dtype=float
        )
        return apply_stp_weight_scale(weight, connection)

    if weight_array.ndim == 2 and weight_array.shape == (target_size, source_size):
        weight = apply_connection_polarity(weight_array, connection)
        return apply_stp_weight_scale(weight, connection)

    resized = np.resize(weight_array, (target_size, source_size)).astype(
        float, copy=False
    )
    weight = apply_connection_polarity(resized, connection)
    return apply_stp_weight_scale(weight, connection)
