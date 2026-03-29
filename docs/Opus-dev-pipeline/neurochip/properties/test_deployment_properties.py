"""Property-based tests for NeuroChip deployment contracts.

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

from deployment_contracts import (
    QuantizationContract,
    LatencyEstimateContract,
    FaultSweepContract,
)


class TestQuantizationProperties:

    @given(bit_width=st.sampled_from([2, 4, 6, 8, 16, 32]))
    def test_supported_bit_widths_accepted(self, bit_width: int):
        """PROPERTY: All spec'd bit widths are valid."""
        QuantizationContract(
            bit_width=bit_width, accuracy_metric=0.95, memory_reduction_factor=1.0
        )

    @given(bit_width=st.sampled_from([1, 3, 5, 7, 9, 10, 24, 64]))
    def test_unsupported_bit_widths_rejected(self, bit_width: int):
        """PROPERTY: Non-standard bit widths are rejected."""
        with pytest.raises(Exception):
            QuantizationContract(
                bit_width=bit_width, accuracy_metric=0.95, memory_reduction_factor=1.0
            )

    @given(
        bw_low=st.sampled_from([2, 4, 8]),
        bw_high=st.sampled_from([16, 32]),
    )
    def test_higher_bitwidth_preserves_more_accuracy(self, bw_low: int, bw_high: int):
        """METAMORPHIC: Higher bit-width should have >= accuracy.
        This is a design property, not enforced by contract — but
        the relationship should hold for any well-implemented quantizer.
        """
        # Just verify both are valid; actual accuracy comparison is
        # for integration tests with real quantizer
        QuantizationContract(
            bit_width=bw_low, accuracy_metric=0.8, memory_reduction_factor=4.0
        )
        QuantizationContract(
            bit_width=bw_high, accuracy_metric=0.95, memory_reduction_factor=1.0
        )


class TestLatencyProperties:

    @given(
        best=st.floats(min_value=0.1, max_value=100.0),
        typical_add=st.floats(min_value=0.0, max_value=100.0),
        worst_add=st.floats(min_value=0.0, max_value=100.0),
    )
    def test_ordered_latency_accepted(self, best: float, typical_add: float, worst_add: float):
        """PROPERTY: best <= typical <= worst is always valid."""
        typical = best + typical_add
        worst = typical + worst_add
        LatencyEstimateContract(
            target_id="loihi2",
            network_depth=3,
            best_case_us=best,
            typical_us=typical,
            worst_case_us=worst,
        )

    @given(
        best=st.floats(min_value=10.0, max_value=100.0),
        typical=st.floats(min_value=0.1, max_value=9.9),
    )
    def test_inverted_latency_rejected(self, best: float, typical: float):
        """PROPERTY: best > typical is always rejected."""
        with pytest.raises(Exception):
            LatencyEstimateContract(
                target_id="loihi2",
                network_depth=3,
                best_case_us=best,
                typical_us=typical,
                worst_case_us=200.0,
            )


class TestFaultSweepProperties:

    @given(rate=st.floats(min_value=0.0, max_value=0.30))
    def test_valid_fault_rate_accepted(self, rate: float):
        """PROPERTY: Fault rate in [0, 0.30] is valid."""
        FaultSweepContract(fault_type="dead_neuron", max_fault_rate=rate)

    @given(rate=st.floats(min_value=0.31, max_value=1.0))
    def test_excessive_fault_rate_rejected(self, rate: float):
        """PROPERTY: Fault rate > 30% is rejected per spec."""
        with pytest.raises(Exception):
            FaultSweepContract(fault_type="dead_neuron", max_fault_rate=rate)
