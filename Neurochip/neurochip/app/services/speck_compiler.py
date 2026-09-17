"""Speck mapped-network compiler analysis.

This module does not claim to be a full SynSense backend-native compiler.
It performs the truthful compile step Neurochip can currently support:
classify the mapped network, derive a sequential deployment plan when
possible, and surface the exact limitations in artifact metadata.
"""

from __future__ import annotations

from typing import Any, Literal


def compile_speck_mapped_network(mapped_network: dict[str, Any]) -> dict[str, Any]:
    """Compile a mapped Speck payload into a truthful deployment plan."""
    populations = list(mapped_network.get("populations", []))
    connections = list(mapped_network.get("connections", []))
    network_summary = dict(mapped_network.get("network_summary", {}))

    population_ids = [str(pop.get("id", f"pop_{idx}")) for idx, pop in enumerate(populations)]
    outgoing: dict[str, list[dict[str, Any]]] = {pop_id: [] for pop_id in population_ids}
    incoming_count: dict[str, int] = {pop_id: 0 for pop_id in population_ids}

    for conn in connections:
        source = str(conn.get("source", ""))
        target = str(conn.get("target", ""))
        if source in outgoing:
            outgoing[source].append(conn)
        if target in incoming_count:
            incoming_count[target] += 1

    has_branching = any(len(conn_list) > 1 for conn_list in outgoing.values())
    has_merging = any(count > 1 for count in incoming_count.values())
    is_linear_chain = not has_branching and not has_merging
    output_population_size = int(populations[-1].get("size", 0) or 0) if populations else 0

    compiler_issues: list[str] = []
    if has_branching:
        compiler_issues.append("branching_topology_not_supported_for_native_speck_compile")
    if has_merging:
        compiler_issues.append("merging_topology_not_supported_for_native_speck_compile")
    if output_population_size <= 0:
        compiler_issues.append("missing_output_population")

    compiler_backend: Literal["normalized_sequential", "unsupported"]
    deployable = is_linear_chain and output_population_size > 0
    compiler_backend = "normalized_sequential" if deployable else "unsupported"

    if output_population_size <= 16:
        output_event_mode: Literal["readout_pin", "spike_monitor"] = "readout_pin"
        input_spike_layer = 12
    else:
        output_event_mode = "spike_monitor"
        input_spike_layer = 0

    scheduled_layers = [
        {
            "population_id": str(pop.get("id", f"pop_{idx}")),
            "size": int(pop.get("size", 0) or 0),
            "neuron_model": str(pop.get("neuron_model", "lif")).lower(),
            "role": str(pop.get("role", "hidden")).lower(),
            "layer_index": idx,
        }
        for idx, pop in enumerate(populations)
    ]
    scheduled_connections = [
        {
            "source": str(conn.get("source", "")),
            "target": str(conn.get("target", "")),
            "weight": conn.get("weight"),
            "delay": conn.get("delay"),
        }
        for conn in connections
    ]

    return {
        "compiler_backend": compiler_backend,
        "deployable": deployable,
        "topology_mode": "linear_chain" if is_linear_chain else "general_dag",
        "compiler_issues": compiler_issues,
        "input_spike_layer": input_spike_layer,
        "output_event_mode": output_event_mode,
        "scheduled_layers": scheduled_layers,
        "scheduled_connections": scheduled_connections,
        "population_count": len(populations),
        "connection_count": len(connections),
        "network_summary": network_summary,
    }
