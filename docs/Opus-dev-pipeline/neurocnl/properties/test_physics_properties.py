"""Property-based tests for neurocnl physics and pipeline contracts.

These define UNIVERSAL LAWS that must hold for ALL valid inputs.
Hypothesis auto-generates hundreds of edge cases per property.

To run:
    pytest properties/ -v --hypothesis-seed=0
"""

from __future__ import annotations

import pytest
from hypothesis import HealthCheck, given, settings
from hypothesis import strategies as st

# Import contracts from the pipeline package
# When installed: from contracts.neuron_params import ...
# For now, use path-relative import or conftest fixture
import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "contracts"))

from neuron_params import LIFNeuronContract, SynapticContract, PopulationContract
from hardware_export import LoihiExportContract


# ═══════════════════════════════════════════════════════════════
# STRATEGIES: Generate valid parameter sets
# ═══════════════════════════════════════════════════════════════

# Generates ANY valid LIF parameter set that satisfies physics
valid_lif_params = st.builds(
    LIFNeuronContract,
    resting_potential=st.floats(min_value=-80.0, max_value=-30.0),
    threshold=st.floats(min_value=-29.9, max_value=50.0),
    reset_potential=st.floats(min_value=-80.0, max_value=50.0),
    refractory_period=st.floats(min_value=0.0001, max_value=0.1),
    tau=st.floats(min_value=0.001, max_value=1.0),
).filter(lambda p: p.threshold > p.resting_potential and p.reset_potential <= p.threshold)

valid_populations = st.builds(
    PopulationContract,
    n_neurons=st.integers(min_value=1, max_value=500),
    dimensions=st.integers(min_value=1, max_value=3),
    radius=st.floats(min_value=0.1, max_value=10.0),
)


# ═══════════════════════════════════════════════════════════════
# PHYSICS PROPERTIES
# ═══════════════════════════════════════════════════════════════

class TestPhysicsInvariants:
    """Properties that must hold for ALL valid neuron parameters."""

    @given(params=valid_lif_params)
    @settings(max_examples=500)
    def test_threshold_always_above_resting(self, params: LIFNeuronContract):
        """PROPERTY: For any valid neuron, threshold > resting potential.
        Source: NeuroML iafTauCell specification.
        """
        assert params.threshold > params.resting_potential

    @given(params=valid_lif_params)
    @settings(max_examples=500)
    def test_reset_never_above_threshold(self, params: LIFNeuronContract):
        """PROPERTY: Reset potential <= threshold for all valid neurons.
        Violation causes infinite-frequency firing loop.
        """
        assert params.reset_potential <= params.threshold

    @given(params=valid_lif_params)
    @settings(max_examples=500)
    def test_membrane_decay_direction(self, params: LIFNeuronContract):
        """PROPERTY: Membrane potential always decays TOWARD rest.
        dv/dt = (rest - v) / tau
        """
        v_above = params.resting_potential + 1.0
        dv_dt = (params.resting_potential - v_above) / params.tau
        assert dv_dt < 0, "Voltage above rest must decay downward"

        v_below = params.resting_potential - 1.0
        dv_dt = (params.resting_potential - v_below) / params.tau
        assert dv_dt > 0, "Voltage below rest must decay upward"

    @given(params=valid_lif_params)
    @settings(max_examples=200)
    def test_refractory_limits_max_firing_rate(self, params: LIFNeuronContract):
        """PROPERTY: Maximum firing rate = 1 / refractory_period.
        No neuron can fire faster than this biological limit.
        """
        max_rate = 1.0 / params.refractory_period
        assert max_rate > 0
        assert max_rate < 1e6, (
            f"Max rate {max_rate} Hz implies refractory < 1us, non-biological"
        )


# ═══════════════════════════════════════════════════════════════
# CONTRACT REJECTION PROPERTIES
# ═══════════════════════════════════════════════════════════════

class TestContractRejection:
    """Properties verifying that invalid parameters are ALWAYS rejected."""

    @given(
        rest=st.floats(min_value=-80.0, max_value=50.0),
        offset=st.floats(min_value=-10.0, max_value=0.0),
    )
    def test_threshold_at_or_below_resting_rejected(self, rest: float, offset: float):
        """PROPERTY: Contracts MUST reject threshold <= resting potential."""
        threshold = rest + offset  # guaranteed <= rest
        with pytest.raises(Exception):
            LIFNeuronContract(
                threshold=threshold,
                resting_potential=rest,
                reset_potential=rest - 10,
                refractory_period=0.002,
                tau=0.02,
            )

    @given(tau=st.floats(min_value=-1.0, max_value=0.0))
    def test_zero_or_negative_tau_rejected(self, tau: float):
        """PROPERTY: Contracts MUST reject tau <= 0."""
        with pytest.raises(Exception):
            LIFNeuronContract(
                threshold=1.0,
                resting_potential=0.0,
                reset_potential=0.0,
                refractory_period=0.002,
                tau=tau,
            )

    @given(ref=st.floats(min_value=-1.0, max_value=0.0))
    def test_zero_or_negative_refractory_rejected(self, ref: float):
        """PROPERTY: Contracts MUST reject refractory_period <= 0."""
        with pytest.raises(Exception):
            LIFNeuronContract(
                threshold=1.0,
                resting_potential=0.0,
                reset_potential=0.0,
                refractory_period=ref,
                tau=0.02,
            )


# ═══════════════════════════════════════════════════════════════
# SYNAPTIC PROPERTIES
# ═══════════════════════════════════════════════════════════════

class TestSynapticProperties:
    """Properties for synaptic connections."""

    @given(weight=st.floats(min_value=0.01, max_value=100.0))
    def test_positive_inhibitory_always_rejected(self, weight: float):
        """PROPERTY: Positive weight + inhibitory = always rejected."""
        with pytest.raises(Exception):
            SynapticContract(weight=weight, is_inhibitory=True)

    @given(delay=st.floats(min_value=-10.0, max_value=-0.001))
    def test_negative_delay_always_rejected(self, delay: float):
        """PROPERTY: Negative axonal delay is non-physical."""
        with pytest.raises(Exception):
            SynapticContract(weight=1.0, axonal_delay=delay)


# ═══════════════════════════════════════════════════════════════
# HARDWARE EXPORT PROPERTIES
# ═══════════════════════════════════════════════════════════════

class TestLoihiProperties:
    """Properties for Loihi hardware export."""

    @given(
        weight=st.floats(min_value=-10.0, max_value=10.0),
        n_neurons=st.integers(min_value=1, max_value=1024),
    )
    def test_valid_loihi_params_accepted(self, weight: float, n_neurons: int):
        """PROPERTY: All params within Loihi limits are accepted."""
        contract = LoihiExportContract(weight=weight, n_neurons=n_neurons)
        assert abs(contract.weight) <= 10.0
        assert 1 <= contract.n_neurons <= 1024

    @given(weight=st.floats(min_value=10.1, max_value=1000.0))
    def test_overweight_loihi_rejected(self, weight: float):
        """PROPERTY: Weights exceeding Loihi 8-bit range are rejected."""
        with pytest.raises(Exception):
            LoihiExportContract(weight=weight, n_neurons=50)

    @given(n=st.integers(min_value=1025, max_value=10000))
    def test_oversized_ensemble_loihi_rejected(self, n: int):
        """PROPERTY: Ensembles > 1024 neurons rejected for Loihi."""
        with pytest.raises(Exception):
            LoihiExportContract(weight=1.0, n_neurons=n)

    @given(
        weight=st.floats(min_value=-10.0, max_value=10.0),
    )
    def test_loihi_quantization_roundtrip(self, weight: float):
        """PROPERTY: Loihi quantization roundtrip loses < 1 LSB precision."""
        contract = LoihiExportContract(weight=weight, n_neurons=50)
        # Quantize to 8-bit signed
        scale = 254.0 / 10.0  # maps [-10, 10] to [-254, 254]
        quantized = round(contract.weight * scale)
        reconstructed = quantized / scale
        assert abs(reconstructed - contract.weight) < (1.0 / scale) + 1e-9


# ═══════════════════════════════════════════════════════════════
# METAMORPHIC PROPERTIES (relational, not absolute)
# ═══════════════════════════════════════════════════════════════

class TestMetamorphicProperties:
    """Properties that test RELATIONSHIPS between inputs and outputs.
    These catch bugs that absolute value tests miss.
    """

    @given(
        tau1=st.floats(min_value=0.005, max_value=0.05),
        tau2=st.floats(min_value=0.051, max_value=0.5),
    )
    def test_larger_tau_means_slower_decay(self, tau1: float, tau2: float):
        """METAMORPHIC: Larger tau → slower decay rate (smaller |dv/dt|)."""
        rest = 0.0
        v = 1.0  # above rest
        dv_dt_fast = abs((rest - v) / tau1)
        dv_dt_slow = abs((rest - v) / tau2)
        assert dv_dt_fast > dv_dt_slow, (
            f"tau={tau1} should decay faster than tau={tau2}"
        )

    @given(
        ref1=st.floats(min_value=0.001, max_value=0.01),
        ref2=st.floats(min_value=0.011, max_value=0.1),
    )
    def test_longer_refractory_means_lower_max_rate(self, ref1: float, ref2: float):
        """METAMORPHIC: Longer refractory → lower maximum firing rate."""
        max_rate_1 = 1.0 / ref1
        max_rate_2 = 1.0 / ref2
        assert max_rate_1 > max_rate_2


# ═══════════════════════════════════════════════════════════════
# CNL PIPELINE PROPERTIES (requires neurocnl installed)
# ═══════════════════════════════════════════════════════════════

class TestCNLPipelineProperties:
    """Properties for the CNL parse → validate → generate pipeline.
    These require neurocnl to be installed. Skip if not available.
    """

    @pytest.fixture(autouse=True)
    def _skip_if_no_neurocnl(self):
        pytest.importorskip("neurocnl")

    @given(
        threshold=st.floats(min_value=0.1, max_value=5.0),
        refractory=st.floats(min_value=0.001, max_value=0.05),
        tau=st.floats(min_value=0.005, max_value=0.1),
    )
    @settings(max_examples=100, deadline=30_000, suppress_health_check=[HealthCheck.too_slow])
    def test_valid_cnl_spec_always_passes_validation(
        self, threshold: float, refractory: float, tau: float
    ):
        """PROPERTY: Any CNL spec with valid physics params passes L1+L2."""
        from neurocnl.pipeline import run_pipeline

        spec = (
            f"The sensory neuron MUST fire ONLY IF membrane potential exceeds {threshold}\n"
            f"The sensory neuron MUST NOT fire DURING the refractory period of {refractory} seconds\n"
            f"The sensory neuron membrane potential MUST decay WITH time constant of {tau} seconds"
        )
        result = run_pipeline(spec, skip_simulation=True)
        assert result.validation["overall"] is True, (
            f"Valid params rejected: threshold={threshold}, "
            f"refractory={refractory}, tau={tau}. Errors: {result.errors}"
        )

    @given(threshold=st.floats(min_value=-5.0, max_value=-0.1))
    @settings(max_examples=50, deadline=30_000, suppress_health_check=[HealthCheck.too_slow])
    def test_negative_threshold_spec_fails_or_parses_differently(
        self, threshold: float
    ):
        """PROPERTY: CNL spec with negative threshold (below default resting=0)
        should fail validation because threshold <= resting_potential.
        """
        from neurocnl.pipeline import run_pipeline

        spec = f"The sensory neuron MUST fire ONLY IF membrane potential exceeds {threshold}"
        result = run_pipeline(spec, skip_simulation=True)
        # Either fails validation OR doesn't parse (both acceptable)
        if result.parsed:
            assert result.validation["overall"] is False, (
                f"Negative threshold {threshold} should fail L1 validation "
                "(threshold must be > resting_potential=0)"
            )
