"""Metadata serialisation for materialized NIR graphs.

Extracted from :mod:`neurocnl.ir.materializer` (Stage 6 refactor). This
module owns turning semantic IR records (populations, connections,
delays, learning rules, timing declarations, neuromodulation/STP rule
dicts) into the compacted ``dict`` metadata attached to each ``nir.*``
node and the overall graph. Behaviour is unchanged by this move;
:class:`~neurocnl.ir.materializer.Materializer` calls through here.
"""

from __future__ import annotations

from dataclasses import asdict
from typing import Any, cast

from neurocnl.ir.connection_lowering import (
    MaterializerError,
    classify_connection_representation,
    connection_shape_intent,
    effective_connection_delay,
)
from neurocnl.ir.metadata_schema import (
    advisory_connection_semantics,
    advisory_delay_semantics,
    advisory_population_semantics,
    validate_neuromodulation_rule,
)
from neurocnl.ir.types import (
    ConnectionIR,
    LearningRuleIR,
    NetworkIR,
    PopulationIR,
    TimingDeclarationIR,
)

__all__ = [
    "compact_metadata",
    "connection_learning_rules",
    "connection_metadata",
    "delay_metadata",
    "population_metadata",
    "serialise_learning_rule",
    "serialise_metadata_rule_list",
    "serialise_neuromodulation_rules",
    "serialise_timing_declaration",
]


def compact_metadata(value: Any) -> Any:
    if isinstance(value, dict):
        return {
            key: compact_metadata(item)
            for key, item in value.items()
            if item is not None
        }
    if isinstance(value, list):
        compacted_items = [compact_metadata(item) for item in value if item is not None]
        if all(not isinstance(item, dict | list | tuple) for item in compacted_items):
            return compacted_items
        return {f"item_{index}": item for index, item in enumerate(compacted_items)}
    return value


def population_metadata(population: PopulationIR) -> dict[str, Any]:
    metadata: dict[str, Any] = {
        "ir_name": population.name,
        "role": population.role,
        "population_type": population.population_type,
        "shape": list(population.shape) if population.shape is not None else None,
        "shape_intent": (
            list(population.shape) if population.shape is not None else None
        ),
        "advisory_semantics": advisory_population_semantics(
            shape_intent=(
                list(population.shape) if population.shape is not None else None
            )
        ),
        "attributes": dict(population.attributes),
    }
    if population.provenance:
        metadata["provenance"] = [asdict(item) for item in population.provenance]
    return cast(dict[str, Any], compact_metadata(metadata))


def connection_learning_rules(
    network: NetworkIR,
    connection: ConnectionIR,
) -> list[dict[str, Any]]:
    return [
        serialise_learning_rule(rule)
        for rule in network.learning_rules
        if rule.source == connection.source and rule.target == connection.target
    ]


def connection_metadata(
    network: NetworkIR,
    connection: ConnectionIR,
    *,
    source_size: int,
    target_size: int,
) -> dict[str, Any]:
    metadata: dict[str, Any] = {
        "source": connection.source,
        "target": connection.target,
        "weight": connection.weight,
        "delay": effective_connection_delay(network, connection),
        "polarity": connection.polarity,
        "connectivity_pattern": connection.connectivity_pattern,
        "connectivity_mask": (
            [list(row) for row in connection.connectivity_mask]
            if connection.connectivity_mask is not None
            else None
        ),
        "locality_radius": connection.locality_radius,
        "connection_density": connection.connection_density,
        "shape_intent": connection_shape_intent(network, connection),
        "connection_representation": classify_connection_representation(
            connection,
            source_size=source_size,
            target_size=target_size,
        ),
        "advisory_semantics": advisory_connection_semantics(
            delay=effective_connection_delay(network, connection),
            learning_rules=connection_learning_rules(network, connection),
            connectivity_pattern=connection.connectivity_pattern,
            shape_intent=connection_shape_intent(network, connection),
            locality_radius=connection.locality_radius,
            connection_density=connection.connection_density,
        ),
        "attributes": dict(connection.attributes),
    }
    if connection.provenance:
        metadata["provenance"] = [asdict(item) for item in connection.provenance]

    scoped_rules = connection_learning_rules(network, connection)
    if scoped_rules:
        metadata["learning_rules"] = scoped_rules
    return cast(dict[str, Any], compact_metadata(metadata))


def delay_metadata(
    network: NetworkIR,
    connection: ConnectionIR,
    delay_seconds: float,
) -> dict[str, Any]:
    metadata = {
        "source": connection.source,
        "target": connection.target,
        "delay": delay_seconds,
        "advisory_semantics": advisory_delay_semantics(
            delay=delay_seconds,
            shape_intent=connection_shape_intent(network, connection),
        ),
    }
    if connection.provenance:
        metadata["provenance"] = [asdict(item) for item in connection.provenance]
    return cast(dict[str, Any], compact_metadata(metadata))


def serialise_learning_rule(rule: LearningRuleIR) -> dict[str, Any]:
    data: dict[str, Any] = {
        "kind": rule.kind,
        "source": rule.source,
        "target": rule.target,
        "rate": rule.rate,
        "window": rule.window,
        "weight_min": rule.weight_min,
        "weight_max": rule.weight_max,
        "attributes": dict(rule.attributes),
    }
    if rule.provenance:
        data["provenance"] = [asdict(item) for item in rule.provenance]
    return cast(dict[str, Any], compact_metadata(data))


def serialise_timing_declaration(declaration: TimingDeclarationIR) -> dict[str, Any]:
    data: dict[str, Any] = {
        "kind": declaration.kind,
        "value": declaration.value,
        "unit": declaration.unit,
        "attributes": dict(declaration.attributes),
    }
    if declaration.provenance:
        data["provenance"] = [asdict(item) for item in declaration.provenance]
    return cast(dict[str, Any], compact_metadata(data))


def serialise_metadata_rule_list(rules: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return [compact_metadata(dict(rule)) for rule in rules]


def serialise_neuromodulation_rules(
    rules: list[dict[str, Any]]
) -> list[dict[str, Any]]:
    for rule in rules:
        try:
            validate_neuromodulation_rule(rule)
        except (ValueError, TypeError) as exc:
            raise MaterializerError(str(exc)) from exc
    return serialise_metadata_rule_list(rules)
