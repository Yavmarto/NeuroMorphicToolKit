"""Property-based tests for Teensy Deployment Contract.

Uses Hypothesis to verify invariants hold across randomized inputs:
- Fail-closed: verdict DEPLOYABLE iff rejections empty
- Capacity rejection: >4096 neurons → NOT_DEPLOYABLE
- Learning rule rejection: any learning rules → NOT_DEPLOYABLE
- Valid networks: all constraints met → DEPLOYABLE
- Constants match: TeensyHardwareLimits ↔ teensy41.json
"""

import json
import os

import pytest
from hypothesis import given, settings
from hypothesis import strategies as st
from hypothesis.strategies import DrawFn
from pydantic import ValidationError

from neurocnl.contracts.teensy_deployment_contract import (
    TEENSY_LIMITS,
    TeensyDeployabilityVerdict,
    TeensyDeploymentResult,
    TeensyRejectionReason,
)
from neurocnl.ir.types import ConnectionIR, LearningRuleIR, NetworkIR, PopulationIR
from neurocnl.planner import plan_teensy_deployability

# ---------------------------------------------------------------------------
# Strategies
# ---------------------------------------------------------------------------

_safe_pop_size = st.integers(min_value=1, max_value=50)
_small_pop_count = st.integers(min_value=1, max_value=5)


@st.composite
def feedforward_lif_ir(draw: DrawFn) -> NetworkIR:
    """Generate a valid feedforward LIF network IR."""
    n_pops = draw(_small_pop_count)
    pop_size = draw(_safe_pop_size)
    pops = {}
    for i in range(n_pops):
        name = f"pop_{i}"
        pops[name] = PopulationIR(name=name, size=pop_size, population_type="lif")
    conns = []
    pop_names = list(pops.keys())
    for i in range(len(pop_names) - 1):
        conns.append(
            ConnectionIR(source=pop_names[i], target=pop_names[i + 1], weight=1.0)
        )
    return NetworkIR(populations=pops, connections=conns)


@st.composite
def oversized_ir(draw: DrawFn) -> NetworkIR:
    """Generate an IR with more neurons than MAX_NEURONS."""
    pop_size = draw(
        st.integers(min_value=TEENSY_LIMITS.MAX_NEURONS + 1, max_value=10000)
    )
    return NetworkIR(
        populations={
            "big": PopulationIR(name="big", size=pop_size, population_type="lif"),
        },
    )


@st.composite
def learning_ir(draw: DrawFn) -> NetworkIR:
    """Generate an IR with a learning rule."""
    base_ir = draw(feedforward_lif_ir())
    rule_kind = draw(st.sampled_from(["stdp", "pes", "bcm", "oja"]))
    base_ir.learning_rules.append(LearningRuleIR(kind=rule_kind))
    return base_ir


# ---------------------------------------------------------------------------
# Properties
# ---------------------------------------------------------------------------


class TestFailClosedInvariant:
    """The fail-closed invariant must hold for all valid TeensyDeploymentResult instances."""

    @settings(max_examples=200)
    @given(
        rejections=st.lists(
            st.sampled_from(list(TeensyRejectionReason)),
            min_size=0,
            max_size=5,
        ),
    )
    def test_verdict_matches_rejections(
        self, rejections: list[TeensyRejectionReason]
    ) -> None:
        """verdict=DEPLOYABLE iff rejections is empty."""
        unique_rejections = list(dict.fromkeys(rejections))
        if unique_rejections:
            verdict = TeensyDeployabilityVerdict.NOT_DEPLOYABLE
        else:
            verdict = TeensyDeployabilityVerdict.DEPLOYABLE
        result = TeensyDeploymentResult(
            verdict=verdict,
            rejections=unique_rejections,
        )
        if result.rejections:
            assert result.verdict == TeensyDeployabilityVerdict.NOT_DEPLOYABLE
        else:
            assert result.verdict in (
                TeensyDeployabilityVerdict.DEPLOYABLE,
                TeensyDeployabilityVerdict.DEPLOYABLE_WITH_WARNINGS,
            )

    @settings(max_examples=100)
    @given(
        rejections=st.lists(
            st.sampled_from(list(TeensyRejectionReason)),
            min_size=1,
            max_size=5,
        ),
    )
    def test_deployable_with_rejections_always_fails(
        self, rejections: list[TeensyRejectionReason]
    ) -> None:
        """Constructing DEPLOYABLE with rejections must raise ValidationError."""
        with pytest.raises(ValidationError):
            TeensyDeploymentResult(
                verdict=TeensyDeployabilityVerdict.DEPLOYABLE,
                rejections=list(dict.fromkeys(rejections)),
            )


class TestCapacityRejection:
    """Networks exceeding neuron capacity must be rejected."""

    @settings(max_examples=50)
    @given(ir=oversized_ir())
    def test_oversized_always_rejected(self, ir: NetworkIR) -> None:
        result = plan_teensy_deployability(ir)
        assert result.verdict == TeensyDeployabilityVerdict.NOT_DEPLOYABLE
        assert TeensyRejectionReason.EXCEEDS_NEURON_CAPACITY in result.rejections


class TestLearningRuleRejection:
    """Networks with learning rules must be rejected."""

    @settings(max_examples=50)
    @given(ir=learning_ir())
    def test_learning_always_rejected(self, ir: NetworkIR) -> None:
        result = plan_teensy_deployability(ir)
        assert result.verdict == TeensyDeployabilityVerdict.NOT_DEPLOYABLE
        assert TeensyRejectionReason.UNSUPPORTED_LEARNING_RULE in result.rejections


class TestValidNetworkAccepted:
    """Small feedforward LIF networks must be accepted."""

    @settings(max_examples=100)
    @given(ir=feedforward_lif_ir())
    def test_small_feedforward_accepted(self, ir: NetworkIR) -> None:
        result = plan_teensy_deployability(ir)
        assert result.verdict in (
            TeensyDeployabilityVerdict.DEPLOYABLE,
            TeensyDeployabilityVerdict.DEPLOYABLE_WITH_WARNINGS,
        )
        assert TeensyRejectionReason.EXCEEDS_NEURON_CAPACITY not in result.rejections


class TestPlannerResultConsistency:
    """Planner output must be internally consistent."""

    @settings(max_examples=100)
    @given(ir=feedforward_lif_ir())
    def test_network_summary_matches(self, ir: NetworkIR) -> None:
        result = plan_teensy_deployability(ir)
        summary = result.network_summary
        expected_neurons = sum(
            p.size if p.size else 50 for p in ir.populations.values()
        )
        assert summary["n_neurons"] == expected_neurons
        assert summary["n_populations"] == len(ir.populations)
        assert summary["n_connections"] == len(ir.connections)


class TestConstantsMatchHardwareProfile:
    """TeensyHardwareLimits constants must match teensy41.json."""

    def test_constants_match_json(self) -> None:
        json_path = os.path.join(
            os.path.dirname(__file__),
            "..",
            "..",
            "..",
            "..",
            "Neurochip",
            "neurochip",
            "targets",
            "teensy41.json",
        )
        json_path = os.path.normpath(json_path)
        if not os.path.exists(json_path):
            pytest.skip("teensy41.json not found at expected path")

        with open(json_path) as f:
            hw = json.load(f)

        assert hw["neuron_capacity"] == TEENSY_LIMITS.MAX_NEURONS
        assert hw["io_pins"] == TEENSY_LIMITS.MAX_IO_PINS
        assert hw["on_chip_memory_kb"] == TEENSY_LIMITS.MEMORY_BUDGET_KB
        assert hw["clock_speed_mhz"] == TEENSY_LIMITS.CLOCK_SPEED_MHZ
        assert hw["power_envelope_mw"] == TEENSY_LIMITS.POWER_ENVELOPE_MW
        assert hw["pj_per_spike_op"] == TEENSY_LIMITS.PJ_PER_SPIKE_OP
        assert set(TEENSY_LIMITS.SUPPORTED_WEIGHT_BIT_WIDTHS) == set(
            hw["weight_bit_widths"]
        )


class TestMemoryFormula:
    """Memory estimation must be consistent across modules."""

    @settings(max_examples=50)
    @given(
        bit_width=st.sampled_from([8, 16, 32]),
    )
    def test_max_synapses_fits_in_budget(self, bit_width: int) -> None:
        """max_synapses_for_bit_width must actually fit in memory."""
        max_syn = TEENSY_LIMITS.max_synapses_for_bit_width(bit_width)
        weight_bytes = max_syn * (bit_width / 8)
        neuron_bytes = TEENSY_LIMITS.MAX_NEURONS * 6
        index_bytes = max_syn * 8
        total_kb = (weight_bytes + neuron_bytes + index_bytes) / 1024
        assert total_kb <= TEENSY_LIMITS.MEMORY_BUDGET_KB

    @settings(max_examples=50)
    @given(
        bit_width=st.sampled_from([8, 16, 32]),
    )
    def test_one_more_synapse_exceeds_budget(self, bit_width: int) -> None:
        """max_synapses + 1 must exceed memory budget."""
        max_syn = TEENSY_LIMITS.max_synapses_for_bit_width(bit_width)
        over_syn = max_syn + 1
        weight_bytes = over_syn * (bit_width / 8)
        neuron_bytes = TEENSY_LIMITS.MAX_NEURONS * 6
        index_bytes = over_syn * 8
        total_kb = (weight_bytes + neuron_bytes + index_bytes) / 1024
        assert total_kb > TEENSY_LIMITS.MEMORY_BUDGET_KB
