import pytest

from neurochip.app.schemas.estimation import NetworkInput
from neurochip.app.services.constraint_analyzer import analyze


def get_base_network() -> NetworkInput:
    return NetworkInput(
        num_neurons=100,
        num_synapses=1000,
        neuron_model="LIF",
        populations=[{"name": "pop1", "size": 100}],
        connections=[{"pre": "pop1", "post": "pop1", "weight_count": 1000}],
        weight_bit_width=8,
        network_depth=10,
    )


def test_analyze_pass_all_constraints():
    net = get_base_network()
    # Teensy 4.1 has 4096 neurons, 1024 KB memory. This easily fits.
    report = analyze(net, "teensy41")

    assert report.neuron_fit == "pass"
    assert report.memory_fit == "pass"
    assert report.quantization_needed is False
    assert len(report.unsupported_features) == 0


def test_analyze_memory_overflow():
    net = get_base_network()
    # Increase synapses to overflow memory (Teensy 4.1 has 1024KB)
    # 1024 KB = ~1,048,576 bytes
    # To overflow we need > 1M bytes
    # 8-bit weight (1 byte) + 2 ints index (8 bytes) = 9 bytes per synapse
    net.num_synapses = 150_000  # ~1.35 MB
    report = analyze(net, "teensy41")

    assert report.memory_fit == "fail"


def test_analyze_capacity_limit():
    net = get_base_network()
    # Teensy 4.1 has 4096 neurons max capacity
    net.num_neurons = 5000
    report = analyze(net, "teensy41")

    assert report.neuron_fit == "fail"


def test_analyze_quantization_needed():
    net = get_base_network()
    # Akida supports up to 4 bits
    net.weight_bit_width = 8
    report = analyze(net, "akida")

    assert report.quantization_needed is True
    assert report.weight_bit_width_required == 4


def test_analyze_unsupported_model():
    net = get_base_network()
    net.neuron_model = "Hodgkin-Huxley"  # Teensy 4.1 doesn't support this
    report = analyze(net, "teensy41")

    assert len(report.unsupported_features) > 0
    assert "Hodgkin-Huxley" in report.unsupported_features[0]


def test_analyze_warning_levels():
    net = get_base_network()
    # 85% capacity of Teensy 4.1 (4096 * 0.85 = ~3481)
    net.num_neurons = 3500
    report = analyze(net, "teensy41")

    assert report.neuron_fit == "warn"


@pytest.mark.parametrize(
    ("num_synapses", "expected_pass"),
    [
        (15360, True),
        (15361, False),
        (20000, False),
    ],
)
def test_pynq_synapse_capacity_boundary(num_synapses: int, expected_pass: bool) -> None:
    net = get_base_network()
    net.num_synapses = num_synapses
    net.connections = [{"pre": "pop1", "post": "pop1", "weight_count": num_synapses}]
    report = analyze(net, "pynq_z2")

    rejection_codes = {rejection.code for rejection in report.rejections}
    if expected_pass:
        assert "synapse_capacity_exceeded" not in rejection_codes
    else:
        assert "synapse_capacity_exceeded" in rejection_codes
