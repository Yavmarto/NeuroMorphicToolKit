"""Population/connection record merging for the semantic-IR lowering pass.

Extracted from :mod:`neurocnl.ir.lowering` (Stage 6 refactor). This
module owns the "node factory" side of lowering: creating or updating
:class:`~neurocnl.ir.types.PopulationIR` / :class:`~neurocnl.ir.types.ConnectionIR`
records in a :class:`~neurocnl.ir.types.NetworkIR`, merging repeated
declarations of the same population/connection while rejecting
conflicting field values. Behaviour and error messages are unchanged by
this move; :mod:`~neurocnl.ir.lowering` and
:mod:`~neurocnl.ir.condition_parsing` both call through here.
"""

from __future__ import annotations

from typing import Any

import numpy as np

from neurocnl.ir.types import ConnectionIR, NetworkIR, PopulationIR, SourceProvenance

__all__ = [
    "LoweringError",
    "merge_connection",
    "merge_inferred_population_size",
    "merge_population",
]


class LoweringError(Exception):
    """Raised when parsed CNL cannot be normalized into IR."""


def _values_equal(current: object, value: object) -> bool:
    if isinstance(current, np.ndarray) or isinstance(value, np.ndarray):
        return np.array_equal(np.asarray(current), np.asarray(value))
    return current == value


def merge_population(
    network: NetworkIR,
    *,
    name: str,
    provenance: SourceProvenance,
    size: int | None = None,
    dimensions: int | None = None,
    shape: tuple[int, ...] | None = None,
    role: str | None = None,
    population_type: str | None = None,
    threshold: float | None = None,
    refractory_period: float | None = None,
    membrane_time_constant: float | None = None,
    attributes: dict[str, Any] | None = None,
) -> PopulationIR:
    pop = network.populations.get(name)
    if pop is None:
        pop = PopulationIR(name=name)
        network.populations[pop.name] = pop

    updates = {
        "size": size,
        "dimensions": dimensions,
        "shape": shape,
        "role": role,
        "population_type": population_type,
        "threshold": threshold,
        "refractory_period": refractory_period,
        "membrane_time_constant": membrane_time_constant,
    }
    for field_name, value in updates.items():
        if value is None:
            continue
        current = getattr(pop, field_name)
        if current is not None and current != value:
            raise LoweringError(
                f"Conflicting population field {field_name!r} for {pop.name!r}: "
                f"{current!r} vs {value!r}."
            )
        setattr(pop, field_name, value)

    if attributes:
        for key, value in attributes.items():
            current = pop.attributes.get(key)
            if current is not None and current != value:
                raise LoweringError(
                    f"Conflicting population attribute {key!r} for {pop.name!r}: "
                    f"{current!r} vs {value!r}."
                )
            pop.attributes[key] = value

    pop.provenance.append(provenance)
    return pop


def _find_connection(
    network: NetworkIR, source: str, target: str
) -> ConnectionIR | None:
    for connection in network.connections:
        if connection.source == source and connection.target == target:
            return connection
    return None


def merge_connection(
    network: NetworkIR,
    *,
    source: str,
    target: str,
    provenance: SourceProvenance,
    weight: (
        float | list[float] | list[list[float]] | np.ndarray[Any, Any] | None
    ) = None,
    delay: float | None = None,
    polarity: str | None = None,
    connectivity_pattern: str | None = None,
    connectivity_mask: tuple[tuple[int, ...], ...] | None = None,
    locality_radius: float | None = None,
    connection_density: float | None = None,
    attributes: dict[str, Any] | None = None,
) -> ConnectionIR:
    connection = _find_connection(network, source, target)
    if connection is None:
        connection = ConnectionIR(source=source, target=target)
        network.connections.append(connection)

    updates = {
        "weight": weight,
        "delay": delay,
        "polarity": polarity,
        "connectivity_pattern": connectivity_pattern,
        "connectivity_mask": connectivity_mask,
        "locality_radius": locality_radius,
        "connection_density": connection_density,
    }
    for field_name, value in updates.items():
        if value is None:
            continue
        current = getattr(connection, field_name)
        if current is not None and not _values_equal(current, value):
            raise LoweringError(
                f"Conflicting connection field {field_name!r} for "
                f"{connection.source!r} -> {connection.target!r}: {current!r} vs {value!r}."
            )
        setattr(connection, field_name, value)

    if attributes:
        for key, value in attributes.items():
            current = connection.attributes.get(key)
            if current is not None and current != value:
                raise LoweringError(
                    f"Conflicting connection attribute {key!r} for "
                    f"{connection.source!r} -> {connection.target!r}: {current!r} vs {value!r}."
                )
            connection.attributes[key] = value

    connection.provenance.append(provenance)
    return connection


def merge_inferred_population_size(
    network: NetworkIR,
    *,
    name: str,
    provenance: SourceProvenance,
    size: int,
) -> None:
    merge_population(network, name=name, provenance=provenance, size=size)
