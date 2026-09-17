"""Service layer for Lava simulator deploy-payload construction.

Extracted from backend/app/routers/deploy.py to keep the router thin.
All domain logic for building and validating a Neurochip-compatible Lava
simulator payload lives here.
"""

from __future__ import annotations

from collections import defaultdict, deque
from typing import Any

import numpy as np

from neurocnl.ir import ConnectionIR, NetworkIR, PopulationIR
from neurocnl.planner import plan_backend_support


def population_size(population: PopulationIR) -> int:
    """Return the effective neuron count for a population."""
    if population.size is not None and population.size > 0:
        return population.size
    if population.shape:
        flattened = 1
        for axis in population.shape:
            flattened *= axis
        return flattened
    return 1


def compute_network_depth(ir: NetworkIR) -> int:
    """Return the longest feed-forward path length (in layers) in the network."""
    if not ir.populations:
        return 1

    indegree: dict[str, int] = dict.fromkeys(ir.populations, 0)
    adjacency: dict[str, list[str]] = defaultdict(list)

    for connection in ir.connections:
        adjacency[connection.source].append(connection.target)
        indegree[connection.target] = indegree.get(connection.target, 0) + 1
        indegree.setdefault(connection.source, 0)

    frontier = deque(name for name in sorted(ir.populations) if indegree.get(name, 0) == 0)
    depth = dict.fromkeys(frontier, 1)

    while frontier:
        current = frontier.popleft()
        for target in adjacency.get(current, ()):
            depth[target] = max(depth.get(target, 1), depth[current] + 1)
            indegree[target] -= 1
            if indegree[target] == 0:
                frontier.append(target)

    return max(depth.values(), default=1)


def default_weight(connection: ConnectionIR) -> float:
    """Return the scalar weight for a connection, applying polarity sign."""
    weight = 1.0 if connection.weight is None else float(connection.weight)
    if connection.polarity == "inhibitory" and weight > 0:
        return -weight
    return weight


def connection_matrix(
    connection: ConnectionIR,
    *,
    source_size: int,
    target_size: int,
) -> list[list[float]]:
    """Build a dense weight matrix for a connection.

    Handles one_to_one, binary_mask, and fully-connected patterns.
    """
    expected_shape = (target_size, source_size)

    if connection.weight is not None and not isinstance(connection.weight, int | float):
        weight_array = np.asarray(connection.weight, dtype=float)
        if weight_array.shape != expected_shape:
            raise ValueError(
                f"Lava handoff expected explicit weight shape {expected_shape} for "
                f"{connection.source!r} -> {connection.target!r}, got {weight_array.shape}."
            )
        if connection.connectivity_pattern == "binary_mask":
            mask = np.asarray(connection.connectivity_mask, dtype=float)
            if mask.shape != expected_shape:
                raise ValueError(
                    f"Binary-mask Lava handoff expected shape {expected_shape} for "
                    f"{connection.source!r} -> {connection.target!r}, got {mask.shape}."
                )
            if connection.polarity == "inhibitory":
                weight_array = -np.abs(weight_array)
            return (weight_array * mask).tolist()
        if connection.polarity == "inhibitory":
            weight_array = -np.abs(weight_array)
        return weight_array.tolist()

    scalar_weight = default_weight(connection)

    if connection.connectivity_pattern == "one_to_one":
        if source_size != target_size:
            raise ValueError(
                f"One-to-one Lava handoff requires equal source/target sizes, got "
                f"{source_size} -> {target_size} for "
                f"{connection.source!r} -> {connection.target!r}."
            )
        matrix = np.zeros((target_size, source_size), dtype=float)
        np.fill_diagonal(matrix, scalar_weight)
        return matrix.tolist()

    if connection.connectivity_pattern == "binary_mask":
        mask = np.asarray(connection.connectivity_mask, dtype=float)
        if mask.shape != expected_shape:
            raise ValueError(
                f"Binary-mask Lava handoff expected shape {expected_shape} for "
                f"{connection.source!r} -> {connection.target!r}, got {mask.shape}."
            )
        if connection.weight is None or isinstance(connection.weight, int | float):
            return (mask * scalar_weight).tolist()

    return np.full((target_size, source_size), scalar_weight, dtype=float).tolist()


def build_lava_deploy_payload(ir: NetworkIR, weight_bit_width: int) -> dict[str, Any]:
    """Build a Neurochip /api/neurochip/hardware/lava/compile-compatible payload."""
    populations: list[dict[str, Any]] = []
    pop_sizes: dict[str, int] = {}
    num_neurons = 0

    for name in sorted(ir.populations):
        population = ir.populations[name]
        size = population_size(population)
        pop_sizes[name] = size
        num_neurons += size
        populations.append(
            {
                "name": name,
                "size": size,
                "threshold": (population.threshold if population.threshold is not None else 1.0),
                "refractory_period": (
                    population.refractory_period
                    if population.refractory_period is not None
                    else 0.002
                ),
                "tau_rc": (
                    population.membrane_time_constant
                    if population.membrane_time_constant is not None
                    else 0.02
                ),
                "role": population.role,
            }
        )

    connections: list[dict[str, Any]] = []
    num_synapses = 0

    for conn in sorted(ir.connections, key=lambda item: (item.source, item.target)):
        source_size = pop_sizes.get(conn.source, 1)
        target_size = pop_sizes.get(conn.target, 1)
        weights = connection_matrix(
            conn,
            source_size=source_size,
            target_size=target_size,
        )
        weight_count = source_size * target_size
        num_synapses += weight_count
        connections.append(
            {
                "pre": conn.source,
                "post": conn.target,
                "weight_count": weight_count,
                "weights": weights,
                "delay": conn.delay,
                "connectivity_pattern": conn.connectivity_pattern,
            }
        )

    return {
        "num_neurons": num_neurons,
        "num_synapses": num_synapses,
        "neuron_model": "LIF",
        "populations": populations,
        "connections": connections,
        "weight_bit_width": weight_bit_width,
        "network_depth": compute_network_depth(ir),
    }


def lava_network_summary(ir: NetworkIR, weight_bit_width: int) -> dict[str, Any]:
    """Return neuron/synapse counts and memory estimate for a Lava handoff payload."""
    neuron_count = sum(population_size(pop) for pop in ir.populations.values())
    synapse_count = 0
    for connection in ir.connections:
        source = ir.populations.get(connection.source)
        target = ir.populations.get(connection.target)
        source_size = population_size(source) if source is not None else 1
        target_size = population_size(target) if target is not None else 1
        synapse_count += source_size * target_size

    memory_kb = 0.0
    if synapse_count > 0:
        memory_kb = (synapse_count * weight_bit_width) / 8 / 1024

    return {
        "n_neurons": neuron_count,
        "n_synapses": synapse_count,
        "memory_estimate_kb": round(memory_kb, 2),
        "quantization_bits": weight_bit_width,
        "n_populations": len(ir.populations),
        "n_connections": len(ir.connections),
        "n_learning_rules": len(ir.learning_rules),
        "runtime_target": "loihi2_simulator",
    }


def lava_support_payload(
    ir: NetworkIR, *, weight_bit_width: int
) -> tuple[str, list[str], list[str]]:
    """Run the Lava backend support check and return (support_state, warnings, rejections)."""
    planner_result = plan_backend_support(ir, "lava")
    warnings = list(planner_result.warnings)
    rejections: list[str] = []

    if ir.learning_rules:
        rejections.append(
            "Lava simulator execution currently supports static weights only; "
            "on-network learning rules are unsupported."
        )

    if planner_result.unsupported_concepts:
        rejections.extend(
            f"Unsupported Lava concept: {concept}."
            for concept in planner_result.unsupported_concepts
        )

    if planner_result.approximated_concepts:
        warnings.extend(
            f"Lava lowers concept {concept!r} approximately."
            for concept in planner_result.approximated_concepts
            if f"Lava lowers concept {concept!r} approximately." not in warnings
        )

    if rejections:
        return "unsupported", warnings, rejections
    if planner_result.verdict == "approximate":
        return "exportable_with_warnings", warnings, rejections
    return "exportable", warnings, rejections
