"""Property-based tests for Neuro-Dream-Hand hardware contracts.

Tests SPEC.md Phase 4 (HITL) and Phase 5 (Chip Deployment) properties.

To run:
    pytest properties/ -v --hypothesis-seed=0
"""

from __future__ import annotations

import pytest
from hypothesis import given
from hypothesis import strategies as st

import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "contracts"))

from hardware_contracts import (
    SerialBridgeContract,
    SensorFrameContract,
    EMGSpikeOutputContract,
    FaultInjectionContract,
    CrossbarExportContract,
    DropTestContract,
)


# ═══════════════════════════════════════════════════════════════
# SERIAL PROTOCOL PROPERTIES
# ═══════════════════════════════════════════════════════════════

class TestSerialProtocolProperties:

    @given(grip=st.floats(min_value=0.0, max_value=1.0))
    def test_valid_grip_always_accepted(self, grip: float):
        """PROPERTY: Any grip in [0.0, 1.0] is valid."""
        contract = SerialBridgeContract(grip_value=grip)
        assert 0.0 <= contract.grip_value <= 1.0

    @given(grip=st.floats(min_value=1.001, max_value=100.0))
    def test_over_range_grip_rejected(self, grip: float):
        """PROPERTY: Grip > 1.0 is always rejected (actuator damage risk)."""
        with pytest.raises(Exception):
            SerialBridgeContract(grip_value=grip)

    @given(grip=st.floats(min_value=-100.0, max_value=-0.001))
    def test_negative_grip_rejected(self, grip: float):
        """PROPERTY: Negative grip is always rejected."""
        with pytest.raises(Exception):
            SerialBridgeContract(grip_value=grip)

    @given(grip=st.floats(min_value=0.0, max_value=1.0))
    def test_grip_to_uint16_roundtrip(self, grip: float):
        """PROPERTY: grip → uint16 → float loses less than 1 LSB."""
        uint16_val = round(grip * 65535)
        reconstructed = uint16_val / 65535.0
        assert abs(reconstructed - grip) < (1.0 / 65535.0) + 1e-9


class TestSensorFrameProperties:

    @given(force_raw=st.integers(min_value=0, max_value=4095))
    def test_valid_adc_always_accepted(self, force_raw: int):
        """PROPERTY: Any 12-bit ADC value is valid."""
        SensorFrameContract(
            timestamp_ms=0, force_raw=force_raw, force_N=0.0, slip_vz=0.0
        )

    @given(force_raw=st.integers(min_value=4096, max_value=100000))
    def test_over_12bit_adc_rejected(self, force_raw: int):
        """PROPERTY: ADC values > 4095 are rejected (12-bit hardware)."""
        with pytest.raises(Exception):
            SensorFrameContract(
                timestamp_ms=0, force_raw=force_raw, force_N=0.0, slip_vz=0.0
            )


# ═══════════════════════════════════════════════════════════════
# EMG ENCODING PROPERTIES
# ═══════════════════════════════════════════════════════════════

class TestEMGProperties:

    @given(output=st.floats(min_value=0.0, max_value=1.0))
    def test_valid_emg_output_accepted(self, output: float):
        """PROPERTY: EMG spike output in [0, 1] is valid."""
        EMGSpikeOutputContract(value=output)

    @given(output=st.floats(min_value=1.001, max_value=100.0))
    def test_over_range_emg_rejected(self, output: float):
        """PROPERTY: EMG output > 1.0 is rejected."""
        with pytest.raises(Exception):
            EMGSpikeOutputContract(value=output)


# ═══════════════════════════════════════════════════════════════
# FAULT INJECTION PROPERTIES
# ═══════════════════════════════════════════════════════════════

class TestFaultInjectionProperties:

    @given(
        dead=st.floats(min_value=0.0, max_value=0.30),
        stuck=st.floats(min_value=0.0, max_value=0.30),
        noise=st.floats(min_value=0.0, max_value=0.30),
    )
    def test_valid_faults_accepted(self, dead: float, stuck: float, noise: float):
        """PROPERTY: All fault fractions in [0, 0.30] are valid."""
        FaultInjectionContract(
            dead_neuron_fraction=dead,
            stuck_at_fraction=stuck,
            weight_noise_sigma=noise,
        )

    @given(dead=st.floats(min_value=0.31, max_value=1.0))
    def test_excessive_dead_neurons_rejected(self, dead: float):
        """PROPERTY: Dead neuron fraction > 30% rejected per SPEC."""
        with pytest.raises(Exception):
            FaultInjectionContract(dead_neuron_fraction=dead)


# ═══════════════════════════════════════════════════════════════
# CROSSBAR PROPERTIES
# ═══════════════════════════════════════════════════════════════

class TestCrossbarProperties:

    @given(
        g_min=st.floats(min_value=1e-12, max_value=1e-7),
        g_max=st.floats(min_value=1e-6, max_value=1e-3),
    )
    def test_valid_conductance_range(self, g_min: float, g_max: float):
        """PROPERTY: Any g_min < g_max > 0 is valid."""
        CrossbarExportContract(g_min=g_min, g_max=g_max)

    @given(g=st.floats(min_value=1e-9, max_value=1e-6))
    def test_equal_min_max_rejected(self, g: float):
        """PROPERTY: g_min == g_max is rejected (degenerate range)."""
        with pytest.raises(Exception):
            CrossbarExportContract(g_min=g, g_max=g)


# ═══════════════════════════════════════════════════════════════
# DROP TEST PROPERTIES
# ═══════════════════════════════════════════════════════════════

class TestDropTestProperties:

    @given(
        sim_rate=st.floats(min_value=0.0, max_value=100.0),
        real_rate=st.floats(min_value=0.0, max_value=100.0),
    )
    def test_gap_within_15pct_accepted(self, sim_rate: float, real_rate: float):
        """PROPERTY: Sim-to-real gap <= 15 pct points is accepted."""
        gap = abs(sim_rate - real_rate)
        if gap <= 15.0:
            DropTestContract(sim_survival_rate=sim_rate, real_survival_rate=real_rate)
        else:
            with pytest.raises(Exception):
                DropTestContract(sim_survival_rate=sim_rate, real_survival_rate=real_rate)
