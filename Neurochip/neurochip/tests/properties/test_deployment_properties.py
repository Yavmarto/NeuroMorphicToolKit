from unittest.mock import patch

import pytest
from hypothesis import given, seed
from hypothesis import strategies as st
from pydantic import ValidationError

from neurochip.app.schemas.deployments import DeploymentManifest, TargetDevice
from neurochip.app.schemas.estimation import NetworkInput
from neurochip.app.services.constraint_analyzer import analyze
from neurochip.contracts.hardware_contracts import HardwareProfile

# Fixed seed for reproducibility as per Acceptance Criteria
FIXED_SEED = 42

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


def create_hardware_profile(
    id,
    name,
    manufacturer,
    description,
    core_count,
    neuron_capacity,
    supported_neuron_models,
    weight_bit_widths,
    on_chip_memory_kb,
    io_pins,
    clock_speed_mhz,
    power_envelope_mw,
    pj_per_spike_op,
    access,
    notes,
):
    """
    Helper to create a HardwareProfile, ensuring the system-enforced memory fit
    invariant (neuron_capacity * 6 <= on_chip_memory_kb * 1024) is satisfied
    by scaling memory to match the generated capacity.
    """
    # 6 bytes per neuron is a hard system invariant defined in HardwareProfile
    required_bytes = neuron_capacity * 6
    required_kb = (required_bytes + 1023) // 1024

    # Respect Pydantic's on_chip_memory_kb limits (1KB - 16384KB)
    on_chip_memory_kb = max(on_chip_memory_kb, min(required_kb, 16384))

    # If the required memory exceeds the hard limit of 16MB, we must cap neurons instead
    if (neuron_capacity * 6) > (16384 * 1024):
        neuron_capacity = (16384 * 1024) // 6

    return HardwareProfile(
        id=id,
        name=name,
        manufacturer=manufacturer,
        description=description,
        core_count=core_count,
        neuron_capacity=neuron_capacity,
        supported_neuron_models=supported_neuron_models,
        weight_bit_widths=weight_bit_widths,
        on_chip_memory_kb=on_chip_memory_kb,
        io_pins=io_pins,
        clock_speed_mhz=clock_speed_mhz,
        power_envelope_mw=power_envelope_mw,
        pj_per_spike_op=pj_per_spike_op,
        access=access,
        notes=notes,
    )


hardware_profile_strategy = st.builds(
    create_hardware_profile,
    id=st.text(min_size=1),
    name=st.text(min_size=1),
    manufacturer=st.text(min_size=1),
    description=st.text(min_size=1),
    core_count=st.integers(min_value=1, max_value=128),
    neuron_capacity=st.integers(min_value=1, max_value=1000000),
    supported_neuron_models=st.lists(
        st.sampled_from(["LIF", "Izhikevich"]), min_size=1, unique=True
    ),
    weight_bit_widths=st.lists(st.integers(min_value=1, max_value=32), min_size=1, unique=True),
    on_chip_memory_kb=st.integers(min_value=1, max_value=16384),
    io_pins=st.integers(min_value=1, max_value=100),
    clock_speed_mhz=st.floats(min_value=1.0, max_value=1000.0),
    power_envelope_mw=st.floats(min_value=1.0, max_value=1000.0),
    pj_per_spike_op=st.floats(min_value=0.1, max_value=10.0),
    access=st.text(min_size=1),
    notes=st.text(min_size=1),
)


@seed(FIXED_SEED)
@given(network=network_input_strategy, target=hardware_profile_strategy)
def test_analyzer_memory_invariant(network, target):
    """
    Property: If the analyzer reports 'pass' for memory fit, the estimated
    memory usage MUST be less than or equal to the available memory.
    """
    with patch("neurochip.app.services.constraint_analyzer._load_target", return_value=target):
        report = analyze(network, target.id)
        if report.memory_fit == "pass":
            assert report.memory_usage_kb <= report.memory_available_kb


@seed(FIXED_SEED)
@given(network=network_input_strategy, target=hardware_profile_strategy)
def test_analyzer_neuron_invariant(network, target):
    """
    Property: If the analyzer reports 'pass' for neuron fit, the network's
    neuron count MUST be less than or equal to the target capacity.
    """
    with patch("neurochip.app.services.constraint_analyzer._load_target", return_value=target):
        report = analyze(network, target.id)
        if report.neuron_fit == "pass":
            assert report.network_neurons <= report.target_capacity


def test_loihi2_firmware_minimum():
    """Assert DeploymentManifest(target_device=TargetDevice.LOIHI_2, firmware_version="1.9.9") raises ValidationError."""
    with pytest.raises(ValidationError) as exc_info:
        DeploymentManifest(
            target_device=TargetDevice.LOIHI_2,
            core_count=1,
            firmware_version="1.9.9",
            checksum_sha256="a" * 64,
        )
    assert "Minimum version required: 2.0.0" in str(exc_info.value)


def test_loihi2_firmware_valid():
    """Assert firmware_version="2.0.0" is accepted for Loihi 2."""
    manifest = DeploymentManifest(
        target_device=TargetDevice.LOIHI_2,
        core_count=1,
        firmware_version="2.0.0",
        checksum_sha256="a" * 64,
    )
    assert manifest.firmware_version == "2.0.0"


def test_spinnaker_firmware_minimum():
    """SpiNNaker < 2.0.0 must be rejected."""
    with pytest.raises(ValidationError) as exc_info:
        DeploymentManifest(
            target_device=TargetDevice.SPINNAKER,
            core_count=1,
            firmware_version="1.9.9",
            checksum_sha256="a" * 64,
        )
    assert "Minimum version required: 2.0.0" in str(exc_info.value)


def test_brainscales_firmware_minimum():
    """BrainScaleS < 2.0.0 must be rejected."""
    with pytest.raises(ValidationError) as exc_info:
        DeploymentManifest(
            target_device=TargetDevice.BRAINSCALES,
            core_count=1,
            firmware_version="1.9.9",
            checksum_sha256="a" * 64,
        )
    assert "Minimum version required: 2.0.0" in str(exc_info.value)


def test_teensy_firmware_minimum():
    """Assert firmware_version="0.9.9" is rejected for Teensy 4.1."""
    with pytest.raises(ValidationError) as exc_info:
        DeploymentManifest(
            target_device=TargetDevice.TEENSY_41,
            core_count=1,
            firmware_version="0.9.9",
            checksum_sha256="a" * 64,
        )
    assert "Minimum version required: 1.0.0" in str(exc_info.value)


def test_teensy_firmware_valid():
    """Assert firmware_version="1.0.0" is accepted for Teensy 4.1."""
    manifest = DeploymentManifest(
        target_device=TargetDevice.TEENSY_41,
        core_count=1,
        firmware_version="1.0.0",
        checksum_sha256="a" * 64,
    )
    assert manifest.firmware_version == "1.0.0"
