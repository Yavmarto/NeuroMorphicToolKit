from neurochip.app.schemas.deployments import TargetDevice
from neurochip.app.schemas.estimation import NetworkInput
from neurochip.app.services.quantizer import quantize, quantize_batch


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


def test_quantize_single():
    net = get_mock_network()
    result = quantize(net, bit_width=8, target_device="Teensy 4.1")

    assert result.bit_width == 8
    assert 0.0 <= result.accuracy <= 1.0
    assert result.memory_size_kb > 0
    assert result.memory_reduction_factor == 4.0  # 32 / 8


def test_quantize_32bit():
    net = get_mock_network()
    result = quantize(net, bit_width=32, target_device="Teensy 4.1")

    # Due to noise in the model, accuracy might not be exactly 0.98
    assert 0.97 <= result.accuracy <= 0.99
    assert result.memory_reduction_factor == 1.0


def test_quantize_batch():
    net = get_mock_network()
    bit_widths = [1, 2, 4, 8]
    results = quantize_batch(net, bit_widths=bit_widths, target_device=TargetDevice.LOIHI_2.value)

    assert len(results) == 4
    for i, bw in enumerate(bit_widths):
        assert results[i].bit_width == bw


def test_quantize_batch_default():
    net = get_mock_network()
    results = quantize_batch(net, target_device="Teensy 4.1")
    assert len(results) == 3  # default for TEENSY_41 is [8, 16, 32]
