"""Network partitioning service — splits large networks across multiple chips/cores."""

from dataclasses import dataclass
from typing import Any

from ..schemas.estimation import NetworkInput


@dataclass
class Partition:
    id: int
    neuron_ids: list[int]
    population_names: list[str]
    neuron_count: int
    synapse_count: int
    inter_partition_connections: int


@dataclass
class PartitionPlan:
    strategy: str
    num_partitions: int
    partitions: list[Partition]
    total_inter_partition_synapses: int
    estimated_latency_overhead_pct: float


def partition_by_population(network: NetworkInput, target_capacity: int) -> PartitionPlan:
    """
    Partition the network by population boundaries.

    Each partition gets whole populations until it reaches the target capacity.
    """
    partitions: list[Partition] = []
    current_neurons: list[int] = []
    current_pops: list[str] = []
    current_count = 0
    partition_id = 0
    neuron_offset = 0

    for pop in network.populations:
        pop_size = pop["size"]

        if current_count + pop_size > target_capacity and current_count > 0:
            # Start a new partition
            partitions.append(
                Partition(
                    id=partition_id,
                    neuron_ids=list(current_neurons),
                    population_names=list(current_pops),
                    neuron_count=current_count,
                    synapse_count=0,  # calculated below
                    inter_partition_connections=0,
                )
            )
            partition_id += 1
            current_neurons = []
            current_pops = []
            current_count = 0

        neuron_ids = list(range(neuron_offset, neuron_offset + pop_size))
        current_neurons.extend(neuron_ids)
        current_pops.append(pop["name"])
        current_count += pop_size
        neuron_offset += pop_size

    # Final partition
    if current_count > 0:
        partitions.append(
            Partition(
                id=partition_id,
                neuron_ids=list(current_neurons),
                population_names=list(current_pops),
                neuron_count=current_count,
                synapse_count=0,
                inter_partition_connections=0,
            )
        )

    # Calculate inter-partition connections
    pop_to_partition = {}
    for p in partitions:
        for name in p.population_names:
            pop_to_partition[name] = p.id

    total_inter = 0
    for conn in network.connections:
        pre_part = pop_to_partition.get(conn["pre"])
        post_part = pop_to_partition.get(conn["post"])
        if pre_part is not None and post_part is not None and pre_part != post_part:
            total_inter += conn["weight_count"]
            for p in partitions:
                if p.id == pre_part or p.id == post_part:
                    p.inter_partition_connections += conn["weight_count"]

    # Estimate latency overhead: ~5% per inter-partition hop
    overhead = min(50.0, total_inter / max(network.num_synapses, 1) * 100 * 5)

    return PartitionPlan(
        strategy="by_population",
        num_partitions=len(partitions),
        partitions=partitions,
        total_inter_partition_synapses=total_inter,
        estimated_latency_overhead_pct=round(overhead, 2),
    )


def suggest_partitions(network: NetworkInput, target_capacity: int) -> list[PartitionPlan]:
    """Return partition suggestions using available strategies."""
    suggestions = []

    if network.num_neurons > target_capacity:
        suggestions.append(partition_by_population(network, target_capacity))

    return suggestions


def plan_to_response(plan: PartitionPlan) -> dict[str, Any]:
    """Convert a :class:`PartitionPlan` dataclass to a dict for ``PartitionPlanResponse``.

    Strips the internal ``neuron_ids`` lists (large, not needed by callers) and
    returns only the fields required by the schema.
    """
    return {
        "strategy": plan.strategy,
        "num_partitions": plan.num_partitions,
        "partitions": [
            {
                "id": p.id,
                "population_names": p.population_names,
                "neuron_count": p.neuron_count,
                "synapse_count": p.synapse_count,
                "inter_partition_connections": p.inter_partition_connections,
            }
            for p in plan.partitions
        ],
        "total_inter_partition_synapses": plan.total_inter_partition_synapses,
        "estimated_latency_overhead_pct": plan.estimated_latency_overhead_pct,
    }
