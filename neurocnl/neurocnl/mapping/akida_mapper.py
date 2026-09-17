"""Shared NeuroCNL → Akida semantic mapper.

Builds the canonical Akida deployment representation used by scaffold
generation today and future SDK/device handoff layers later.
"""

from __future__ import annotations

from collections import defaultdict
from typing import Any, NoReturn

import numpy as np

from neurocnl.contracts.akida_deployment_contract import (
    AkidaExportResult,
    AkidaSupportState,
    normalize_akida_version,
)
from neurocnl.contracts.akida_mapping_contract import (
    AkidaMappedConnection,
    AkidaMappedNetwork,
    AkidaMappedPopulation,
    AkidaMappedProvenance,
)
from neurocnl.ir.types import (
    AkidaConnectionPropertyIR,
    ConnectionIR,
    NetworkIR,
    PopulationIR,
    SourceProvenance,
)
from neurocnl.planner import (
    _DEFAULT_POPULATION_SIZE,
    plan_akida_exportability,
    plan_backend_support,
)


class AkidaMappingRejectedError(RuntimeError):
    """Raised when IR cannot be lowered into the shared Akida representation."""

    def __init__(
        self,
        export_result: AkidaExportResult,
        message: str,
    ) -> None:
        self.export_result = export_result
        super().__init__(message)


def _provenance_to_model(provenance: SourceProvenance) -> AkidaMappedProvenance:
    return AkidaMappedProvenance(
        line=provenance.line,
        raw=provenance.raw,
        concept=provenance.concept,
    )


def _population_size(population: PopulationIR) -> int:
    return population.size if population.size is not None else _DEFAULT_POPULATION_SIZE


def _population_attributes(population: PopulationIR) -> dict[str, Any]:
    """Copy a population's attributes and derive the Akida LIF parameter keys.

    ``PopulationIR.threshold`` / ``.membrane_time_constant`` are typed IR fields,
    but the Akida host only ever sees ``attributes`` (both the real SDK backend
    and the pure-Python simulator read ``attributes["lif_threshold"]``). Without
    this derivation every spec-exported layer was built on the SDK's default
    on-chip activation, silently discarding the modelled threshold.

    ``lif_tau_mem`` is carried for the same reason of not losing the IR value in
    the exported spec; no Akida host component consumes it today.

    An explicit same-named entry already in ``attributes`` wins — an author who
    hand-set ``lif_threshold`` is overriding the IR field on purpose.
    """
    attributes = dict(population.attributes)
    if population.threshold is not None:
        attributes.setdefault("lif_threshold", float(population.threshold))
    if population.membrane_time_constant is not None:
        attributes.setdefault("lif_tau_mem", float(population.membrane_time_constant))
    return attributes


def _scalar_weight(
    weight: float | list[Any] | np.ndarray[Any, Any] | None
) -> float | None:
    # ConnectionIR.weight carries the full weight matrix for a linear
    # transformation (e.g. reflex_arc.cnl's 1x1 "w_sensor_actuator"), but
    # AkidaMappedConnection.weight is a scalar summary field — passing the
    # matrix through unconverted raised a pydantic ValidationError for every
    # network whose weight came from a matrix rather than a bare scalar.
    if weight is None:
        return None
    if isinstance(weight, int | float):
        return float(weight)
    return float(np.mean(np.asarray(weight, dtype=float)))


def _resolve_requested_version(ir: NetworkIR, akida_version: str | None) -> str:
    if akida_version is not None:
        return normalize_akida_version(akida_version)
    if ir.akida_hardware is not None:
        return normalize_akida_version(ir.akida_hardware.version)
    return normalize_akida_version(None)


def _raise_mapping_error(
    export_result: AkidaExportResult,
    message: str,
) -> NoReturn:
    raise AkidaMappingRejectedError(export_result, message)


def _ordered_population_ids(
    ir: NetworkIR, export_result: AkidaExportResult
) -> list[str]:
    population_ids = sorted(ir.populations)
    if not population_ids:
        return []

    if not ir.connections:
        if len(population_ids) > 1:
            _raise_mapping_error(
                export_result,
                "Akida mapping rejected: multiple disconnected populations cannot be "
                "lowered into one ordered Akida model.",
            )
        return population_ids

    outgoing: dict[str, list[str]] = defaultdict(list)
    incoming_count: dict[str, int] = dict.fromkeys(population_ids, 0)

    for connection in ir.connections:
        if (
            connection.source not in ir.populations
            or connection.target not in ir.populations
        ):
            _raise_mapping_error(
                export_result,
                "Akida mapping rejected: every connection endpoint must reference a "
                "declared population.",
            )
        outgoing[connection.source].append(connection.target)
        incoming_count[connection.target] += 1

    connected_population_ids = {connection.source for connection in ir.connections} | {
        connection.target for connection in ir.connections
    }
    if connected_population_ids != set(population_ids):
        _raise_mapping_error(
            export_result,
            "Akida mapping rejected: all populations must participate in a single "
            "faithful Akida path.",
        )

    roots = sorted(
        population_id
        for population_id in population_ids
        if incoming_count[population_id] == 0
    )
    if len(roots) != 1:
        _raise_mapping_error(
            export_result,
            "Akida mapping rejected: expected exactly one Akida input population.",
        )

    order: list[str] = []
    seen: set[str] = set()
    current = roots[0]

    while True:
        if current in seen:
            _raise_mapping_error(
                export_result,
                "Akida mapping rejected: cycle encountered while constructing the "
                "Akida layer order.",
            )
        order.append(current)
        seen.add(current)

        next_nodes = sorted(set(outgoing.get(current, [])))
        if not next_nodes:
            break
        if len(next_nodes) != 1:
            _raise_mapping_error(
                export_result,
                "Akida mapping rejected: branching or ambiguous fan-out cannot be "
                "lowered into the shared Akida layer chain.",
            )
        current = next_nodes[0]

    if len(order) != len(population_ids):
        _raise_mapping_error(
            export_result,
            "Akida mapping rejected: not all populations were reachable from the "
            "Akida input population.",
        )

    return order


def _connection_lookup(
    ir: NetworkIR,
    export_result: AkidaExportResult,
) -> dict[tuple[str, str], ConnectionIR]:
    lookup: dict[tuple[str, str], ConnectionIR] = {}
    for connection in ir.connections:
        key = (connection.source, connection.target)
        if key in lookup:
            _raise_mapping_error(
                export_result,
                "Akida mapping rejected: duplicate connections between the same "
                "populations are not supported by the shared mapping layer.",
            )
        lookup[key] = connection
    return lookup


def _connection_properties_by_edge(
    ir: NetworkIR,
    export_result: AkidaExportResult,
) -> dict[tuple[str, str], AkidaConnectionPropertyIR]:
    resolved: dict[tuple[str, str], AkidaConnectionPropertyIR] = {}
    connection_keys = sorted(
        (connection.source, connection.target) for connection in ir.connections
    )

    for prop in ir.akida_connection_properties:
        if prop.source is not None or prop.target is not None:
            if prop.source is None or prop.target is None:
                _raise_mapping_error(
                    export_result,
                    "Akida mapping rejected: connection properties must specify both "
                    "source and target or neither.",
                )
            key = (prop.source, prop.target)
            if key not in connection_keys:
                _raise_mapping_error(
                    export_result,
                    "Akida mapping rejected: Akida connection property references an "
                    "unknown connection.",
                )
        else:
            if len(connection_keys) != 1:
                _raise_mapping_error(
                    export_result,
                    "Akida mapping rejected: unscoped Akida connection properties are "
                    "ambiguous when more than one connection exists.",
                )
            key = connection_keys[0]

        if key in resolved:
            _raise_mapping_error(
                export_result,
                "Akida mapping rejected: multiple Akida connection properties for the "
                "same mapped connection are not supported.",
            )
        resolved[key] = prop

    return resolved


def map_network_ir_to_akida_representation(
    ir: NetworkIR,
    akida_version: str | None = None,
) -> AkidaMappedNetwork:
    """Map validated ``NetworkIR`` into the shared Akida representation."""

    requested_version = _resolve_requested_version(ir, akida_version)
    backend_plan = plan_backend_support(ir, requested_version)
    export_result = plan_akida_exportability(ir, akida_version=requested_version)

    if export_result.support_state == AkidaSupportState.UNSUPPORTED:
        reasons = (
            ", ".join(reason.value for reason in export_result.rejections)
            or "unsupported"
        )
        _raise_mapping_error(
            export_result,
            f"Akida mapping rejected ({export_result.akida_version}): {reasons}.",
        )

    if backend_plan.unsupported_concepts:
        unsupported = ", ".join(backend_plan.unsupported_concepts)
        _raise_mapping_error(
            export_result,
            "Network topology contains features unsupported by the Akida native backend. "
            f"Unsupported concepts: {unsupported}.",
        )

    if export_result.topology_verdict != "faithful":
        _raise_mapping_error(
            export_result,
            "Akida mapping rejected: the shared Akida mapping layer currently requires "
            "a faithful feed-forward topology.",
        )

    ordered_population_ids = _ordered_population_ids(ir, export_result)
    connection_lookup = _connection_lookup(ir, export_result)
    property_lookup = _connection_properties_by_edge(ir, export_result)

    mapped_populations = [
        AkidaMappedPopulation(
            id=population_id,
            size=_population_size(ir.populations[population_id]),
            role=ir.populations[population_id].role,
            population_type=ir.populations[population_id].population_type,
            provenance=[
                _provenance_to_model(provenance)
                for provenance in ir.populations[population_id].provenance
            ],
            attributes=_population_attributes(ir.populations[population_id]),
        )
        for population_id in ordered_population_ids
    ]

    mapped_connections: list[AkidaMappedConnection] = []
    for index in range(len(ordered_population_ids) - 1):
        source = ordered_population_ids[index]
        target = ordered_population_ids[index + 1]
        connection = connection_lookup.get((source, target))
        if connection is None:
            _raise_mapping_error(
                export_result,
                "Akida mapping rejected: expected a connection between adjacent mapped "
                "populations but none was found.",
            )

        property_ir = property_lookup.get((source, target))
        mapped_connections.append(
            AkidaMappedConnection(
                source=source,
                target=target,
                units=_population_size(ir.populations[target]),
                weight=_scalar_weight(connection.weight),
                block_type=(
                    property_ir.block_type.value if property_ir is not None else None
                ),
                provenance=[
                    _provenance_to_model(provenance)
                    for provenance in connection.provenance
                ],
                property_provenance=[
                    _provenance_to_model(provenance)
                    for provenance in (
                        property_ir.provenance if property_ir is not None else []
                    )
                ],
                attributes=dict(connection.attributes),
            )
        )

    warnings = list(dict.fromkeys([*backend_plan.warnings, *export_result.warnings]))
    metadata_provenance = [
        _provenance_to_model(provenance)
        for provenance in ir.metadata.get("provenance", [])
        if isinstance(provenance, SourceProvenance)
    ]

    return AkidaMappedNetwork(
        akida_version=requested_version,
        input_population=ordered_population_ids[0] if ordered_population_ids else None,
        populations=mapped_populations,
        connections=mapped_connections,
        topology_verdict=export_result.topology_verdict,
        warnings=warnings,
        network_summary=dict(export_result.network_summary),
        metadata_provenance=metadata_provenance,
    )
