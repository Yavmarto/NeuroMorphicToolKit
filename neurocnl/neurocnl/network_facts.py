"""Immutable, per-graph facts shared by planner.py's target-specific checks.

Each field here replaces a computation that ``planner.py``'s Teensy, PYNQ, and
Akida deployability checks previously re-derived independently — in two cases
(the unsupported-concept scan, the memory-estimate formula) with byte-for-byte
duplicated code. This module owns no target-specific thresholds, contract
types, or rejection policy — only the raw facts every target reads from and
interprets under its own limits.
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from neurocnl.ir.types import PORT_POPULATION_TYPES, NetworkIR

DEFAULT_POPULATION_SIZE = 50  # Nengo generator default when CNL doesn't specify size


def is_port_population(pop: object) -> bool:
    """True when a population is a declared input/output port, not real neurons."""
    population_type = getattr(pop, "population_type", None)
    return bool(population_type and population_type.lower() in PORT_POPULATION_TYPES)


def _effective_size(pop: object) -> int:
    size = getattr(pop, "size", None)
    return int(size) if size else DEFAULT_POPULATION_SIZE


def _flatten_weight(weight: object) -> list[float]:
    if weight is None:
        return []
    if isinstance(weight, int | float):
        return [float(weight)]
    return [float(value) for value in np.asarray(weight, dtype=float).flatten()]


def _detect_recurrent_connections(ir: NetworkIR) -> list[str]:
    """Detect connections that form cycles (recurrent / feedback).

    Returns list of human-readable descriptions of recurrent connections.
    """
    adjacency: dict[str, set[str]] = {}
    for conn in ir.connections:
        adjacency.setdefault(conn.source, set()).add(conn.target)

    recurrent: list[str] = []
    for conn in ir.connections:
        if conn.source == conn.target:
            recurrent.append(f"self-connection on '{conn.source}'")
            continue
        visited: set[str] = set()
        stack = [conn.target]
        while stack:
            node = stack.pop()
            if node == conn.source:
                recurrent.append(
                    f"cycle via '{conn.source}' → '{conn.target}' → ... → '{conn.source}'"
                )
                break
            if node not in visited:
                visited.add(node)
                stack.extend(adjacency.get(node, set()) - visited)
    return recurrent


@dataclass(frozen=True, slots=True)
class NetworkFacts:
    """One immutable snapshot of the raw facts derivable from a ``NetworkIR``."""

    population_sizes: dict[str, int]
    port_population_names: frozenset[str]
    real_population_names: frozenset[str]
    n_neurons_total: int
    n_neurons_excluding_ports: int
    n_populations_total: int
    n_populations_excluding_ports: int
    n_synapses_total: int
    n_synapses_excluding_ports: int
    n_connections_total: int
    real_connection_pairs: frozenset[tuple[str, str]]
    provenance_concepts: frozenset[str]
    neuron_models_used: frozenset[str]
    has_recurrent_connections: bool
    recurrent_connection_descriptions: tuple[str, ...]
    has_axonal_delays: bool
    declared_timestep_seconds: float | None
    declared_delay_quantization_seconds: float | None
    connection_weights_total: tuple[float, ...]
    connection_weights_excluding_ports: tuple[float, ...]
    max_abs_weight: float | None

    @staticmethod
    def from_ir(ir: NetworkIR) -> NetworkFacts:
        population_sizes = {name: _effective_size(pop) for name, pop in ir.populations.items()}
        port_population_names = frozenset(
            name for name, pop in ir.populations.items() if is_port_population(pop)
        )
        real_population_names = frozenset(ir.populations) - port_population_names

        n_neurons_total = sum(population_sizes.values())
        n_neurons_excluding_ports = sum(
            size for name, size in population_sizes.items() if name in real_population_names
        )

        def synapse_count(*, exclude_ports: bool) -> int:
            total = 0
            for conn in ir.connections:
                if exclude_ports and (
                    conn.source in port_population_names or conn.target in port_population_names
                ):
                    continue
                pre_size = population_sizes.get(conn.source, DEFAULT_POPULATION_SIZE)
                post_size = population_sizes.get(conn.target, DEFAULT_POPULATION_SIZE)
                total += pre_size * post_size
            return total

        real_connection_pairs = frozenset(
            (conn.source, conn.target)
            for conn in ir.connections
            if conn.source
            and conn.target
            and conn.source in real_population_names
            and conn.target in real_population_names
        )

        provenance_concepts: set[str] = set()
        for population in ir.populations.values():
            provenance_concepts.update(
                provenance.concept for provenance in population.provenance if provenance.concept
            )
        for connection in ir.connections:
            provenance_concepts.update(
                provenance.concept for provenance in connection.provenance if provenance.concept
            )

        neuron_models_used = frozenset(
            pop.population_type.lower() for pop in ir.populations.values() if pop.population_type
        )

        recurrent_descriptions = tuple(_detect_recurrent_connections(ir))

        has_axonal_delays = any(
            conn.delay is not None and conn.delay > 0 for conn in ir.connections
        )

        declared_timestep_seconds = next(
            (
                item.value
                for item in ir.timing_declarations
                if item.kind == "timestep" and item.value is not None
            ),
            None,
        )
        declared_delay_quantization_seconds = next(
            (
                item.value
                for item in ir.timing_declarations
                if item.kind == "delay_quantization" and item.value is not None
            ),
            None,
        )

        weights_total: list[float] = []
        weights_excluding_ports: list[float] = []
        for conn in ir.connections:
            flat = _flatten_weight(conn.weight)
            if not flat:
                continue
            weights_total.extend(flat)
            if (
                conn.source not in port_population_names
                and conn.target not in port_population_names
            ):
                weights_excluding_ports.extend(flat)

        max_abs_weight = max((abs(w) for w in weights_total), default=None)

        return NetworkFacts(
            population_sizes=population_sizes,
            port_population_names=port_population_names,
            real_population_names=real_population_names,
            n_neurons_total=n_neurons_total,
            n_neurons_excluding_ports=n_neurons_excluding_ports,
            n_populations_total=len(ir.populations),
            n_populations_excluding_ports=len(real_population_names),
            n_synapses_total=synapse_count(exclude_ports=False),
            n_synapses_excluding_ports=synapse_count(exclude_ports=True),
            n_connections_total=len(ir.connections),
            real_connection_pairs=real_connection_pairs,
            provenance_concepts=frozenset(provenance_concepts),
            neuron_models_used=neuron_models_used,
            has_recurrent_connections=bool(recurrent_descriptions),
            recurrent_connection_descriptions=recurrent_descriptions,
            has_axonal_delays=has_axonal_delays,
            declared_timestep_seconds=declared_timestep_seconds,
            declared_delay_quantization_seconds=declared_delay_quantization_seconds,
            connection_weights_total=tuple(weights_total),
            connection_weights_excluding_ports=tuple(weights_excluding_ports),
            max_abs_weight=max_abs_weight,
        )
