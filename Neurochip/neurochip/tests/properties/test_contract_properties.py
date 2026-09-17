import re

import pytest
from hypothesis import given
from hypothesis import strategies as st
from pydantic import ValidationError

from neurochip.app.schemas.deployments import DeploymentManifest, TargetDevice
from neurochip.app.schemas.estimation import LatencyEstimate, PowerEstimate
from neurochip.contracts.fault_contracts import FaultSweepResult
from neurochip.contracts.hardware_contracts import HardwareProfile
from neurochip.contracts.quantization_contracts import QuantizationConfig, QuantizationResult

# Regex for SemVer and SHA-256 (matching pydantic fields in contracts)
SEMVER_REGEX = r"^\d+\.\d+\.\d+$"
SHA256_REGEX = r"^[a-fA-F0-9]{64}$"


@given(st.text())
def test_deployment_manifest_firmware_semver(version):
    """Test that DeploymentManifest only accepts valid SemVer firmware versions."""
    is_semver = bool(re.match(SEMVER_REGEX, version))
    is_valid = is_semver and [int(x) for x in version.split(".")] >= [1, 0, 0]
    try:
        DeploymentManifest(
            target_device=TargetDevice.TEENSY_41,
            core_count=1,
            firmware_version=version,
            checksum_sha256="a" * 64,
        )
        assert is_valid
    except ValidationError:
        assert not is_valid


@given(st.text())
def test_deployment_manifest_checksum_sha256(checksum):
    """Test that DeploymentManifest only accepts valid SHA-256 checksums."""
    is_valid = bool(re.match(SHA256_REGEX, checksum))
    try:
        DeploymentManifest(
            target_device=TargetDevice.TEENSY_41,
            core_count=1,
            firmware_version="1.0.0",
            checksum_sha256=checksum,
        )
        assert is_valid
    except ValidationError:
        assert not is_valid


@given(st.floats(min_value=0, max_value=100.0), st.sampled_from(TargetDevice))
def test_quantization_precision_loss_bound(loss_pct, target):
    """Test invariant: QuantizationResult accuracy loss must be within 25.0%."""
    # Use a valid bit-width for the target
    bit_width = QuantizationConfig.SUPPORTED_BIT_WIDTHS[target][0]

    def create_qr():
        return QuantizationResult(
            target_device=target,
            bit_width=bit_width,
            accuracy=0.9,
            accuracy_loss_pct=loss_pct,
            memory_size_kb=100.0,
            memory_reduction_factor=4.0,
            spike_fidelity=0.95,
            power_estimate_pj=10.0,
        )

    if loss_pct > 25.0:
        with pytest.raises(ValidationError):
            create_qr()
    else:
        qr = create_qr()
        assert qr.accuracy_loss_pct <= 25.0


@given(st.sampled_from(TargetDevice), st.integers(min_value=1, max_value=64))
def test_quantization_config_bit_width_invariant(target, bit_width):
    """Test target-specific bit-width validation in QuantizationConfig."""
    supported = QuantizationConfig.SUPPORTED_BIT_WIDTHS.get(target, [])

    def create_qc():
        return QuantizationConfig(
            target_device=target,
            bit_width=bit_width,
            scaling_factor=1.0,
            rounding_mode="nearest",
        )

    if bit_width not in supported:
        with pytest.raises(ValidationError):
            create_qc()
    else:
        qc = create_qc()
        assert qc.bit_width in supported


@given(
    st.integers(min_value=1, max_value=1000000),  # neuron_capacity
    st.integers(min_value=1, max_value=16384),  # on_chip_memory_kb
)
def test_hardware_memory_fit_invariant(capacity, memory_kb):
    """
    Test invariant: neuron_capacity * 6 bytes <= on_chip_memory_kb * 1024.
    """
    bytes_required = capacity * 6
    bytes_available = memory_kb * 1024

    def create_hp():
        return HardwareProfile(
            id="test",
            name="Test",
            manufacturer="Test",
            description="Test",
            core_count=1,
            neuron_capacity=capacity,
            supported_neuron_models=["LIF"],
            weight_bit_widths=[8],
            on_chip_memory_kb=memory_kb,
            io_pins=10,
            clock_speed_mhz=100.0,
            power_envelope_mw=10.0,
            pj_per_spike_op=1.0,
            access="open",
            notes="Test",
        )

    if bytes_required > bytes_available:
        with pytest.raises(ValidationError) as exc_info:
            create_hp()
        assert "Memory fit violation" in str(exc_info.value)
    else:
        hp = create_hp()
        assert hp.neuron_capacity * 6 <= hp.on_chip_memory_kb * 1024


@given(st.lists(st.integers(min_value=-10, max_value=64), min_size=1))
def test_hardware_profile_bit_widths_positive(bit_widths):
    """Test invariant: HardwareProfile weight_bit_widths must be positive."""

    def create_hp():
        return HardwareProfile(
            id="test",
            name="Test",
            manufacturer="Test",
            description="Test",
            core_count=1,
            neuron_capacity=100,
            supported_neuron_models=["LIF"],
            weight_bit_widths=bit_widths,
            on_chip_memory_kb=1024,
            io_pins=10,
            clock_speed_mhz=100.0,
            power_envelope_mw=10.0,
            pj_per_spike_op=1.0,
            access="open",
            notes="Test",
        )

    if any(bw <= 0 for bw in bit_widths):
        with pytest.raises(ValidationError):
            create_hp()
    else:
        hp = create_hp()
        assert all(bw > 0 for bw in hp.weight_bit_widths)


@given(st.lists(st.floats(min_value=0, max_value=1.0), min_size=1))
def test_fault_sweep_rate_limit(rates):
    """Test invariant: maximum fault injection rate must be 0.3 (30%)."""

    def create_fsr():
        return FaultSweepResult(
            fault_type="stuck-at-0",
            fault_rates=rates,
            accuracies=[0.9] * len(rates),
            accuracy_ci_lower=[0.85] * len(rates),
            accuracy_ci_upper=[0.95] * len(rates),
            threshold_90pct=0.1,
        )

    if any(r > 0.3 for r in rates):
        with pytest.raises(ValidationError) as exc_info:
            create_fsr()
        assert "Fault injection rate exceeds 0.3 (30%) limit" in str(exc_info.value)
    else:
        fsr = create_fsr()
        assert all(r <= 0.3 for r in fsr.fault_rates)


@given(
    st.floats(min_value=0, max_value=1000),  # best
    st.floats(min_value=0, max_value=1000),  # typical
    st.floats(min_value=0, max_value=1000),  # worst
)
def test_latency_estimate_monotonicity(best, typical, worst):
    """Test invariant: best_case_us <= typical_us <= worst_case_us."""

    def create_le():
        return LatencyEstimate(
            target_id="test",
            network_depth=5,
            best_case_us=best,
            typical_us=typical,
            worst_case_us=worst,
            clock_speed_mhz=100.0,
            inter_core_overhead_us=1.0,
        )

    if not (best <= typical <= worst):
        with pytest.raises(ValidationError) as exc_info:
            create_le()
        assert "Latency order violation" in str(exc_info.value)
    else:
        le = create_le()
        assert le.best_case_us <= le.typical_us <= le.worst_case_us


@given(st.floats(max_value=-0.01))
def test_power_estimate_non_negative(energy):
    """Test invariant: PowerEstimate total_energy_pj must be non-negative."""
    with pytest.raises(ValidationError):
        PowerEstimate(
            target_id="test",
            total_energy_pj=energy,
            per_population_breakdown=[],
            power_envelope_mw=10.0,
            exceeds_envelope=False,
            notes="Test",
        )


def _get_valid_hardware_profile_kwargs():
    """Helper to provide a base set of valid HardwareProfile arguments."""
    return {
        "id": "test-hw",
        "name": "Test Hardware",
        "manufacturer": "NeuroChip Corp",
        "description": "Standard test profile",
        "core_count": 1,
        "neuron_capacity": 1000,
        "supported_neuron_models": ["LIF", "Izhikevich"],
        "weight_bit_widths": [8, 16],
        "on_chip_memory_kb": 1024,
        "io_pins": 40,
        "clock_speed_mhz": 200.0,
        "power_envelope_mw": 50.0,
        "pj_per_spike_op": 0.5,
        "access": "public",
        "notes": "None",
    }


def test_core_count_lower_boundary():
    """Test that core_count=0 is rejected."""
    kwargs = _get_valid_hardware_profile_kwargs()
    kwargs["core_count"] = 0
    with pytest.raises(ValidationError):
        HardwareProfile(**kwargs)


def test_core_count_upper_boundary():
    """Test that core_count=129 is rejected."""
    kwargs = _get_valid_hardware_profile_kwargs()
    kwargs["core_count"] = 129
    with pytest.raises(ValidationError):
        HardwareProfile(**kwargs)


@given(st.integers(min_value=1, max_value=128))
def test_core_count_valid_range(core_count):
    """Test that valid core_counts (1-128) are accepted."""
    kwargs = _get_valid_hardware_profile_kwargs()
    kwargs["core_count"] = core_count
    hp = HardwareProfile(**kwargs)
    assert hp.core_count == core_count
