import pytest
from pydantic import ValidationError

from neurochip.contracts import (
    DeploymentManifest,
    FaultSweepResult,
    HardwareProfile,
    LatencyEstimate,
    PowerEstimate,
    QuantizationConfig,
    QuantizationResult,
    TargetDevice,
)


# HardwareProfile Tests
def test_hardware_profile_valid():
    hp = HardwareProfile(
        id="test",
        name="Test",
        manufacturer="Test",
        description="Test",
        core_count=64,
        neuron_capacity=4096,
        supported_neuron_models=["LIF"],
        weight_bit_widths=[8],
        on_chip_memory_kb=1024,
        io_pins=55,
        clock_speed_mhz=600.0,
        power_envelope_mw=100.0,
        pj_per_spike_op=500.0,
        access="open",
        notes="Test",
    )
    assert hp.core_count == 64
    assert hp.on_chip_memory_kb == 1024
    assert hp.clock_speed_mhz == 600.0


def test_hardware_profile_invalid_core_count():
    with pytest.raises(ValidationError):
        HardwareProfile(
            id="test",
            name="Test",
            manufacturer="Test",
            description="Test",
            core_count=0,
            neuron_capacity=4096,
            supported_neuron_models=["LIF"],
            weight_bit_widths=[8],
            on_chip_memory_kb=1024,
            io_pins=55,
            clock_speed_mhz=600.0,
            power_envelope_mw=100.0,
            pj_per_spike_op=500.0,
            access="open",
            notes="Test",
        )


def test_hardware_profile_invalid_on_chip_memory_kb():
    with pytest.raises(ValidationError):
        HardwareProfile(
            id="test",
            name="Test",
            manufacturer="Test",
            description="Test",
            core_count=64,
            neuron_capacity=4096,
            supported_neuron_models=["LIF"],
            weight_bit_widths=[8],
            on_chip_memory_kb=0,
            io_pins=55,
            clock_speed_mhz=600.0,
            power_envelope_mw=100.0,
            pj_per_spike_op=500.0,
            access="open",
            notes="Test",
        )


def test_hardware_profile_invalid_clock_speed_mhz():
    with pytest.raises(ValidationError):
        HardwareProfile(
            id="test",
            name="Test",
            manufacturer="Test",
            description="Test",
            core_count=64,
            neuron_capacity=4096,
            supported_neuron_models=["LIF"],
            weight_bit_widths=[8],
            on_chip_memory_kb=1024,
            io_pins=55,
            clock_speed_mhz=0.5,
            power_envelope_mw=100.0,
            pj_per_spike_op=500.0,
            access="open",
            notes="Test",
        )


# DeploymentManifest Tests
def test_deployment_manifest_valid():
    dm = DeploymentManifest(
        target_device=TargetDevice.TEENSY_41,
        core_count=1,
        firmware_version="1.0.0",
        checksum_sha256="a" * 64,
    )
    assert dm.target_device == TargetDevice.TEENSY_41
    assert dm.firmware_version == "1.0.0"
    assert dm.checksum_sha256 == "a" * 64


def test_deployment_manifest_invalid_version_for_target():
    with pytest.raises(ValidationError):
        DeploymentManifest(
            target_device=TargetDevice.LOIHI_2,
            core_count=1,
            firmware_version="1.9.9",
            checksum_sha256="a" * 64,
        )


def test_deployment_manifest_invalid_target_device():
    with pytest.raises(ValidationError):
        DeploymentManifest(
            target_device="Unknown Device",  # type: ignore[arg-type]
            core_count=1,
            firmware_version="1.2.3",
            checksum_sha256="a" * 64,
        )


def test_deployment_manifest_invalid_firmware_version():
    with pytest.raises(ValidationError):
        DeploymentManifest(
            target_device=TargetDevice.TEENSY_41,
            core_count=1,
            firmware_version="v1.2.3",
            checksum_sha256="a" * 64,
        )


def test_deployment_manifest_invalid_checksum():
    with pytest.raises(ValidationError):
        DeploymentManifest(
            target_device=TargetDevice.TEENSY_41,
            core_count=1,
            firmware_version="1.0.0",
            checksum_sha256="abc",
        )


# QuantizationConfig Tests
def test_quantization_config_valid():
    qc = QuantizationConfig(
        target_device=TargetDevice.TEENSY_41,
        bit_width=8,
        scaling_factor=0.5,
        rounding_mode="nearest",
    )
    assert qc.bit_width == 8
    assert qc.scaling_factor == 0.5
    assert qc.rounding_mode == "nearest"


def test_quantization_config_invalid_bit_width():
    with pytest.raises(ValidationError):
        QuantizationConfig(
            target_device=TargetDevice.TEENSY_41,
            bit_width=0,
            scaling_factor=0.5,
            rounding_mode="nearest",
        )
    with pytest.raises(ValidationError):
        QuantizationConfig(
            target_device=TargetDevice.AKIDA,
            bit_width=8,
            scaling_factor=0.5,
            rounding_mode="nearest",
        )


def test_quantization_config_invalid_scaling_factor():
    with pytest.raises(ValidationError):
        QuantizationConfig(
            target_device=TargetDevice.TEENSY_41,
            bit_width=8,
            scaling_factor=0.0,
            rounding_mode="nearest",
        )


# QuantizationResult Tests
def test_quantization_result_invalid_loss():
    with pytest.raises(ValidationError):
        QuantizationResult(
            target_device=TargetDevice.TEENSY_41,
            bit_width=8,
            accuracy=0.7,
            accuracy_loss_pct=26.0,
            memory_size_kb=10.0,
            memory_reduction_factor=4.0,
            spike_fidelity=0.9,
            power_estimate_pj=100.0,
        )


# FaultSweepResult Tests
def test_fault_sweep_result_valid():
    fsr = FaultSweepResult(
        fault_type="dead_neuron",
        fault_rates=[0.0, 0.1, 0.3],
        accuracies=[0.9, 0.8, 0.7],
        accuracy_ci_lower=[0.85, 0.75, 0.65],
        accuracy_ci_upper=[0.95, 0.85, 0.75],
        threshold_90pct=0.1,
    )
    assert fsr.fault_rates == [0.0, 0.1, 0.3]


def test_fault_sweep_result_invalid_rate():
    with pytest.raises(ValidationError):
        FaultSweepResult(
            fault_type="dead_neuron",
            fault_rates=[0.0, 0.4],
            accuracies=[0.9, 0.6],
            accuracy_ci_lower=[0.85, 0.55],
            accuracy_ci_upper=[0.95, 0.65],
            threshold_90pct=0.1,
        )


# LatencyEstimate Tests
def test_latency_estimate_valid():
    le = LatencyEstimate(
        target_id="test",
        network_depth=5,
        best_case_us=10.0,
        typical_us=15.0,
        worst_case_us=20.0,
        clock_speed_mhz=100.0,
        inter_core_overhead_us=1.0,
    )
    assert le.best_case_us == 10.0


def test_latency_estimate_invalid_monotonic():
    with pytest.raises(ValidationError):
        LatencyEstimate(
            target_id="test",
            network_depth=5,
            best_case_us=10.0,
            typical_us=8.0,
            worst_case_us=20.0,
            clock_speed_mhz=100.0,
            inter_core_overhead_us=1.0,
        )
    with pytest.raises(ValidationError):
        LatencyEstimate(
            target_id="test",
            network_depth=5,
            best_case_us=10.0,
            typical_us=15.0,
            worst_case_us=12.0,
            clock_speed_mhz=100.0,
            inter_core_overhead_us=1.0,
        )


# PowerEstimate Tests
def test_power_estimate_invalid_energy():
    with pytest.raises(ValidationError):
        PowerEstimate(
            target_id="test",
            total_energy_pj=-1.0,
            per_population_breakdown=[],
            power_envelope_mw=10.0,
            exceeds_envelope=False,
            notes="Test",
        )
