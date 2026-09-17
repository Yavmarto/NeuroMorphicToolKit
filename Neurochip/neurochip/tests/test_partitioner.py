from neurochip.app.schemas.estimation import NetworkInput
from neurochip.app.services.partitioner import partition_by_population, suggest_partitions


def get_mock_network():
    return NetworkInput(
        num_neurons=1000,
        num_synapses=5000,
        neuron_model="LIF",
        populations=[{"name": "pop1", "size": 600}, {"name": "pop2", "size": 400}],
        connections=[
            {"pre": "pop1", "post": "pop1", "weight_count": 2000},
            {"pre": "pop2", "post": "pop2", "weight_count": 1000},
            {"pre": "pop1", "post": "pop2", "weight_count": 2000},
        ],
        weight_bit_width=32,
        network_depth=10,
    )


def test_partition_by_population():
    net = get_mock_network()
    # Capacity is 700, so pop1 (600) fits in part1, but pop2 (400) needs part2.
    plan = partition_by_population(net, target_capacity=700)

    assert plan.num_partitions == 2
    assert plan.strategy == "by_population"
    assert len(plan.partitions) == 2
    assert plan.partitions[0].neuron_count == 600
    assert plan.partitions[1].neuron_count == 400
    assert plan.total_inter_partition_synapses == 2000  # pop1 -> pop2


def test_suggest_partitions():
    net = get_mock_network()
    # No partitioning needed if capacity is large
    suggestions = suggest_partitions(net, target_capacity=2000)
    assert len(suggestions) == 0

    # Partitioning suggested if capacity is small
    suggestions = suggest_partitions(net, target_capacity=500)
    assert len(suggestions) == 1
    assert suggestions[0].num_partitions >= 2
