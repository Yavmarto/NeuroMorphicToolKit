"""Concept-verdict and connection-representation summary for NIR lowering.

Extracted from :mod:`neurocnl.ir.materializer` (Stage 6 refactor). This
module owns :func:`summarize_network_lowering`, which classifies which
``NetworkIR`` semantics become executable, advisory, or approximate in
the current NIR export, plus the per-concept "verdict" helpers and the
:class:`NirLoweringSummary` result type. Behaviour and warning text are
unchanged by this move; :class:`~neurocnl.ir.materializer.Materializer`
calls through here.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from neurocnl.ir.connection_lowering import (
    classify_connection_representation,
    effective_connection_delay,
    infer_population_dimension,
    is_lateral_inhibition_connection,
)
from neurocnl.ir.graph_metadata import connection_learning_rules
from neurocnl.ir.types import ConnectionIR, NetworkIR

__all__ = ["NirLoweringSummary", "summarize_network_lowering"]

DEFAULT_MEMBRANE_TIME_CONSTANT = 0.02

_FAITHFUL_CONCEPTS = frozenset(
    {
        "threshold_firing",
        "membrane_potential_decay",
        "synaptic_weight",
        "axonal_delay",
        "inhibitory_connection",
    }
)
_METADATA_ONLY_CONCEPTS = frozenset(
    {
        "refractory_period",
        "stdp_learning",
        "timing_declaration",
        "population_coding_range",
        "adaptive_spiking",
        "receptor_dynamics",
        "background_noise",
        "neuromodulation",
    }
)
_APPROXIMATE_CONCEPTS = frozenset(
    {"population_coding", "network_topology", "short_term_plasticity"}
)


@dataclass(slots=True)
class NirLoweringSummary:
    """Compact summary of how NetworkIR semantics map into current NIR export."""

    concept_verdicts: dict[str, str]
    connection_summary: dict[str, int]
    metadata_only_summary: dict[str, int]
    warning_summary: dict[str, str]

    def to_metadata(self) -> dict[str, Any]:
        """Serialize the summary into graph metadata."""
        return {
            "version": 1,
            "concepts": dict(self.concept_verdicts),
            "connections": dict(self.connection_summary),
            "metadata_only": dict(self.metadata_only_summary),
            "warnings": dict(self.warning_summary),
        }


def _collect_ir_concepts(network: NetworkIR) -> list[str]:
    concepts: set[str] = set()
    for population in network.populations.values():
        concepts.update(
            provenance.concept for provenance in population.provenance if provenance.concept
        )
    for connection in network.connections:
        concepts.update(
            provenance.concept for provenance in connection.provenance if provenance.concept
        )
    for rule in network.learning_rules:
        concepts.update(provenance.concept for provenance in rule.provenance if provenance.concept)
    for declaration in network.timing_declarations:
        concepts.update(
            provenance.concept for provenance in declaration.provenance if provenance.concept
        )
    for provenance in network.metadata.get("provenance", []):
        concept = getattr(provenance, "concept", None)
        if concept:
            concepts.add(concept)
    return sorted(concepts)


def _spatial_connectivity_verdict(network: NetworkIR, *, default_population_size: int) -> str:
    representations = {
        classify_connection_representation(
            connection,
            source_size=infer_population_dimension(
                network.populations[connection.source],
                default_population_size=default_population_size,
            ),
            target_size=infer_population_dimension(
                network.populations[connection.target],
                default_population_size=default_population_size,
            ),
        )
        for connection in network.connections
        if any(provenance.concept == "spatial_connectivity" for provenance in connection.provenance)
    }
    if not representations:
        return "not_lowered"
    if representations <= {"structured_one_to_one", "structured_binary_mask"}:
        return "lowered_faithfully"
    return "not_lowered"


def _lateral_inhibition_verdict(network: NetworkIR) -> str:
    connections = [
        connection
        for connection in network.connections
        if is_lateral_inhibition_connection(connection)
    ]
    if not connections:
        return "not_lowered"
    return "lowered_approximately"


def _short_term_plasticity_verdict(network: NetworkIR) -> str:
    for connection in network.connections:
        stp_type = connection.attributes.get("short_term_plasticity_type")
        utilization_rate = connection.attributes.get("utilization_rate")
        if stp_type == "depression" and isinstance(utilization_rate, int | float):
            return "lowered_approximately"
    return "lowered_as_metadata"


def _homeostatic_verdict(network: NetworkIR) -> str:
    for population in network.populations.values():
        rate = population.attributes.get("homeostatic_target_rate_hz")
        if isinstance(rate, int | float):
            return "lowered_approximately"
    return "lowered_as_metadata"


def _axonal_delay_verdict(network: NetworkIR) -> str:
    if any(
        effective_connection_delay(network, connection) is not None
        for connection in network.connections
    ):
        return "lowered_faithfully"
    return "not_lowered"


def summarize_network_lowering(
    network: NetworkIR, *, default_population_size: int
) -> NirLoweringSummary:
    """Summarize which IR semantics become executable, advisory, or approximate in NIR."""
    concepts = _collect_ir_concepts(network)
    population_shapes = {
        name: list(population.shape)
        for name, population in network.populations.items()
        if population.shape is not None
    }
    concept_verdicts: dict[str, str] = {}
    warning_summary: dict[str, str] = {}
    metadata_only_connections = 0
    approximate_connections = 0
    structured_intent_connections = 0
    structured_one_to_one_connections = 0
    structured_binary_mask_connections = 0
    explicit_dense_connections = 0
    resized_heuristic_connections = 0

    def _dimension(connection: ConnectionIR, side: str) -> int:
        name = connection.source if side == "source" else connection.target
        return infer_population_dimension(
            network.populations[name], default_population_size=default_population_size
        )

    for concept in concepts:
        if concept == "axonal_delay":
            concept_verdicts[concept] = _axonal_delay_verdict(network)
        elif concept == "lateral_inhibition":
            concept_verdicts[concept] = _lateral_inhibition_verdict(network)
        elif concept == "spatial_connectivity":
            concept_verdicts[concept] = _spatial_connectivity_verdict(
                network, default_population_size=default_population_size
            )
        elif concept == "short_term_plasticity":
            concept_verdicts[concept] = _short_term_plasticity_verdict(network)
        elif concept == "homeostatic_plasticity":
            concept_verdicts[concept] = _homeostatic_verdict(network)
        elif concept in _FAITHFUL_CONCEPTS:
            concept_verdicts[concept] = "lowered_faithfully"
        elif concept in _METADATA_ONLY_CONCEPTS:
            concept_verdicts[concept] = "lowered_as_metadata"
        elif concept in _APPROXIMATE_CONCEPTS:
            concept_verdicts[concept] = "lowered_approximately"
        else:
            concept_verdicts[concept] = "not_lowered"

    if concept_verdicts.get("spatial_connectivity") == "not_lowered":
        warning_summary[f"warning_{len(warning_summary)}"] = (
            "Spatial connectivity is only partially exportable in the current NIR bridge: "
            "one-to-one and explicit binary masks lower executable weights, while locality- "
            "and probability-based forms remain unsupported."
        )

    for connection in network.connections:
        source_size = _dimension(connection, "source")
        target_size = _dimension(connection, "target")
        representation = classify_connection_representation(
            connection,
            source_size=source_size,
            target_size=target_size,
        )
        if connection_learning_rules(network, connection):
            metadata_only_connections += 1
        if representation == "structured_one_to_one":
            structured_one_to_one_connections += 1
        elif representation == "structured_binary_mask":
            structured_binary_mask_connections += 1
        elif representation == "structured_intent_metadata_only":
            structured_intent_connections += 1
            approximate_connections += 1
            warning_summary[f"warning_{len(warning_summary)}"] = (
                f"Connection {connection.source!r} -> {connection.target!r} preserves "
                "structured connectivity intent as metadata while lowering to dense Linear "
                "weights."
            )
        elif representation == "dense_matrix":
            explicit_dense_connections += 1
        elif representation == "resized_heuristic_matrix":
            resized_heuristic_connections += 1
            approximate_connections += 1
            warning_summary[f"warning_{len(warning_summary)}"] = (
                f"Connection {connection.source!r} -> {connection.target!r} uses a "
                "resized heuristic dense weight representation."
            )

        if (
            is_lateral_inhibition_connection(connection)
            and connection.source not in population_shapes
            and connection.target not in population_shapes
        ):
            warning_summary[f"warning_{len(warning_summary)}"] = (
                f"Connection {connection.source!r} -> {connection.target!r} lowers lateral "
                "inhibition without population shape info: synthesising dense all-ones weight "
                "with zero diagonal. Provide population shape for locality-aware synthesis."
            )

        if "receptor_type" in connection.attributes:
            warning_summary[f"warning_{len(warning_summary)}"] = (
                f"Connection {connection.source!r} -> {connection.target!r} stores receptor "
                "dynamics as metadata because the current materializer emits only dense "
                "Linear nodes without executable synapse operators."
            )

        if connection.attributes.get("short_term_plasticity_type") == "facilitation":
            warning_summary[f"warning_{len(warning_summary)}"] = (
                f"Connection {connection.source!r} -> {connection.target!r} has "
                "facilitation-type STP which cannot be approximated statically; preserved "
                "as metadata only."
            )

        if connection_learning_rules(network, connection):
            warning_summary[f"warning_{len(warning_summary)}"] = (
                f"Connection {connection.source!r} -> {connection.target!r} stores learning "
                "rules as metadata because the current materializer does not emit executable "
                "NIR learning-rule nodes."
            )

    if network.timing_declarations:
        warning_summary[f"warning_{len(warning_summary)}"] = (
            "Timing declarations are preserved as advisory metadata rather than executable "
            "NIR timing operators, although the current materializer does machine-check "
            "declaration consistency within its supported scope."
        )

    if any(rule.source is None or rule.target is None for rule in network.learning_rules):
        warning_summary[f"warning_{len(warning_summary)}"] = (
            "Unscoped learning rules are preserved in graph metadata only."
        )

    adaptive_spiking_populations = sum(
        1
        for population in network.populations.values()
        if "adaptive_spiking_enabled" in population.attributes
    )
    populations_with_homeostasis = sum(
        1
        for population in network.populations.values()
        if "homeostatic_target_rate_hz" in population.attributes
    )
    populations_with_background_noise = sum(
        1
        for population in network.populations.values()
        if "background_noise_value" in population.attributes
    )
    populations_with_coding_range = sum(
        1
        for population in network.populations.values()
        if "population_coding_range_degrees" in population.attributes
    )
    connections_with_receptor_dynamics = sum(
        1 for connection in network.connections if "receptor_type" in connection.attributes
    )
    connections_with_short_term_plasticity = sum(
        1
        for connection in network.connections
        if "short_term_plasticity_type" in connection.attributes
    )
    graph_neuromodulation_rules = len(network.metadata.get("neuromodulation_rules", []))
    graph_short_term_plasticity_rules = len(network.metadata.get("short_term_plasticity_rules", []))

    if adaptive_spiking_populations:
        warning_summary[f"warning_{len(warning_summary)}"] = (
            "Adaptive spiking survives in population metadata only; the current "
            "materializer still emits base LIF nodes rather than adaptive neuron operators."
        )

    if populations_with_background_noise:
        warning_summary[f"warning_{len(warning_summary)}"] = (
            "Background noise survives in population metadata only; the current "
            "materializer does not emit executable stochastic input processes."
        )

    if populations_with_coding_range:
        warning_summary[f"warning_{len(warning_summary)}"] = (
            "Population coding range survives in population metadata only; the current "
            "materializer does not emit executable encoding-range operators."
        )

    if populations_with_homeostasis:
        for name, population in network.populations.items():
            rate = population.attributes.get("homeostatic_target_rate_hz")
            if isinstance(rate, int | float):
                tau_scalar = (
                    population.membrane_time_constant
                    if population.membrane_time_constant is not None
                    else DEFAULT_MEMBRANE_TIME_CONSTANT
                )
                v_threshold = float(rate) * tau_scalar
                warning_summary[f"warning_{len(warning_summary)}"] = (
                    f"Population {name!r} homeostatic target rate {rate} Hz approximated "
                    f"as LIF threshold {v_threshold:.4f} (= rate × tau). This is a "
                    "steady-state approximation only."
                )

    connections_with_non_scaled_stp = sum(
        1
        for connection in network.connections
        if "short_term_plasticity_type" in connection.attributes
        and not (
            connection.attributes.get("short_term_plasticity_type") == "depression"
            and isinstance(connection.attributes.get("utilization_rate"), int | float)
        )
    )
    if connections_with_non_scaled_stp or graph_short_term_plasticity_rules:
        warning_summary[f"warning_{len(warning_summary)}"] = (
            "Short-term plasticity survives in metadata only; the current materializer "
            "does not emit executable synaptic plasticity operators."
        )

    if graph_neuromodulation_rules:
        warning_summary[f"warning_{len(warning_summary)}"] = (
            "Neuromodulation rules are preserved as structured metadata; no NIR executable "
            f"operators are emitted. {graph_neuromodulation_rules} rule(s) validated."
        )

    if population_shapes_count := sum(
        1 for population in network.populations.values() if population.shape is not None
    ):
        warning_summary[f"warning_{len(warning_summary)}"] = (
            "Population shapes survive as first-class metadata while current NIR node sizes "
            "still use flattened neuron counts."
        )

    if network.metadata.get("global_receptor_dynamics") is not None:
        warning_summary[f"warning_{len(warning_summary)}"] = (
            "Global receptor dynamics are preserved in graph metadata only."
        )

    connections_with_executable_delay = sum(
        1
        for connection in network.connections
        if effective_connection_delay(network, connection) is not None
    )

    connection_summary = {
        "total": len(network.connections),
        "dense_scalar_broadcast": sum(
            1
            for connection in network.connections
            if classify_connection_representation(
                connection,
                source_size=_dimension(connection, "source"),
                target_size=_dimension(connection, "target"),
            )
            == "dense_scalar_broadcast"
        ),
        "structured_one_to_one": structured_one_to_one_connections,
        "structured_binary_mask": structured_binary_mask_connections,
        "dense_matrix": explicit_dense_connections,
        "resized_heuristic_matrix": resized_heuristic_connections,
        "approximate_dense_connections": approximate_connections,
        "structured_intent_metadata_only": structured_intent_connections,
        "delay_nodes": connections_with_executable_delay,
    }
    metadata_only_summary = {
        "connections_with_delay": 0,
        "connections_with_learning_rules": sum(
            1
            for connection in network.connections
            if connection_learning_rules(network, connection)
        ),
        "timing_declarations": len(network.timing_declarations),
        "unscoped_learning_rules": sum(
            1 for rule in network.learning_rules if rule.source is None or rule.target is None
        ),
        "adaptive_spiking_populations": adaptive_spiking_populations,
        "populations_with_homeostatic_plasticity": populations_with_homeostasis,
        "populations_with_background_noise": populations_with_background_noise,
        "populations_with_coding_range": populations_with_coding_range,
        "connections_with_receptor_dynamics": connections_with_receptor_dynamics,
        "connections_with_short_term_plasticity": connections_with_short_term_plasticity,
        "populations_with_shape": population_shapes_count,
        "global_receptor_dynamics": (
            1 if network.metadata.get("global_receptor_dynamics") is not None else 0
        ),
        "graph_neuromodulation_rules": graph_neuromodulation_rules,
        "graph_short_term_plasticity_rules": graph_short_term_plasticity_rules,
        "metadata_only_connections": metadata_only_connections,
    }
    return NirLoweringSummary(
        concept_verdicts=concept_verdicts,
        connection_summary=connection_summary,
        metadata_only_summary=metadata_only_summary,
        warning_summary=warning_summary,
    )
