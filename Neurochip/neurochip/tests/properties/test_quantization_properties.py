from hypothesis import given, seed
from hypothesis import strategies as st

from neurochip.app.schemas.deployments import TargetDevice
from neurochip.app.schemas.estimation import NetworkInput
from neurochip.app.services.quantizer import quantize

# Fixed seed for reproducibility as per Acceptance Criteria
FIXED_SEED = 42

# 25% accuracy loss is a hard limit defined in the QuantizationResult schema
MAX_ACCURACY_LOSS_PCT = 25.0

network_input_strategy = st.builds(
    NetworkInput,
    num_neurons=st.integers(min_value=1, max_value=1000000),
    num_synapses=st.integers(min_value=0, max_value=10000000),
    neuron_model=st.sampled_from(["LIF", "Izhikevich"]),
    populations=st.lists(st.dictionaries(st.text(), st.just({})), max_size=5),
    connections=st.lists(st.dictionaries(st.text(), st.just({})), max_size=5),
    weight_bit_width=st.integers(min_value=1, max_value=32),
    network_depth=st.integers(min_value=1, max_value=100),
)


@seed(FIXED_SEED)
@given(
    network=network_input_strategy,
    bit_width=st.sampled_from([8, 16, 32]),
    target=st.just(TargetDevice.TEENSY_41),
)
def test_quantization_accuracy_bounds(network, bit_width, target):
    """
    Property: Quantization accuracy loss must remain within defined bounds (<= 25.0%).
    This verifies that the simulator adheres to the QuantizationResult contract
    and reflects system constraints.
    """
    result = quantize(network, bit_width, target_device=target)
    assert result.accuracy_loss_pct <= MAX_ACCURACY_LOSS_PCT
    assert 0.0 <= result.accuracy <= 1.0


@seed(FIXED_SEED)
@given(
    network=network_input_strategy,
    bit_width=st.sampled_from([1, 2, 4, 8]),
    target=st.just(TargetDevice.LOIHI_2),
)
def test_quantization_memory_positivity(network, bit_width, target):
    """
    Property: Memory usage and reduction factor must be non-negative.
    """
    result = quantize(network, bit_width, target_device=target)
    assert result.memory_size_kb >= 0.0
    if network.num_synapses > 0:
        assert result.memory_reduction_factor > 0.0
