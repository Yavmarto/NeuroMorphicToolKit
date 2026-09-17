from neurochip.app.schemas.estimation import NetworkInput
from neurochip.app.services.power_estimator import estimate_latency, estimate_power


def get_mock_network():
    return NetworkInput(
        num_neurons=100,
        num_synapses=1000,
        neuron_model="LIF",
        populations=[{"name": "pop1", "size": 100}],
        connections=[{"pre": "pop1", "post": "pop1", "weight_count": 1000}],
        weight_bit_width=32,
        network_depth=10,
    )


def test_estimate_power_teensy():
    net = get_mock_network()
    result = estimate_power(net, "teensy41")

    assert result.target_id == "teensy41"
    assert result.total_energy_pj > 0
    assert len(result.per_population_breakdown) == 1
    assert result.exceeds_envelope is False


def test_estimate_latency_teensy():
    net = get_mock_network()
    result = estimate_latency(net, "teensy41")

    assert result.target_id == "teensy41"
    assert result.network_depth == 10
    assert result.typical_us > 0
    assert result.clock_speed_mhz == 600


def test_estimate_latency_loihi():
    net = get_mock_network()
    result = estimate_latency(net, "loihi2")

    assert result.target_id == "loihi2"
    # Loihi has clock_speed_mhz = 0 in mock profile likely, or handles it as async
    # Let's check typical_us calculation for async
    assert result.typical_us > 0
