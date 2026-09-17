"""Unit tests for Teensy Deployment Contract and planner integration."""

import pytest
from pydantic import ValidationError

from neurocnl.contracts.teensy_deployment_contract import (
    TEENSY_LIMITS,
    TEENSY_TOPOLOGY,
    TeensyDeployabilityVerdict,
    TeensyDeploymentResult,
    TeensyHardwareLimits,
    TeensyIOMapping,
    TeensyRejectionReason,
)
from neurocnl.ir.types import (
    ConnectionIR,
    LearningRuleIR,
    NetworkIR,
    PopulationIR,
    SourceProvenance,
    TimingDeclarationIR,
)
from neurocnl.planner import plan_teensy_deployability

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _minimal_lif_ir(
    *,
    n_pops: int = 2,
    pop_size: int = 10,
    connected: bool = True,
) -> NetworkIR:
    """Build a minimal feedforward LIF network IR for testing."""
    pops = {}
    for i in range(n_pops):
        name = f"pop_{i}"
        role = "sensory" if i == 0 else ("motor" if i == n_pops - 1 else "interneuron")
        pops[name] = PopulationIR(
            name=name, size=pop_size, role=role, population_type="lif"
        )

    conns = []
    if connected:
        pop_names = list(pops.keys())
        for i in range(len(pop_names) - 1):
            conns.append(
                ConnectionIR(source=pop_names[i], target=pop_names[i + 1], weight=1.0)
            )

    return NetworkIR(populations=pops, connections=conns)


# ---------------------------------------------------------------------------
# TeensyHardwareLimits
# ---------------------------------------------------------------------------


class TestTeensyHardwareLimits:
    def test_defaults_match_teensy41(self) -> None:
        limits = TeensyHardwareLimits()
        assert limits.MAX_NEURONS == 4096
        assert limits.MAX_IO_PINS == 55
        assert limits.MEMORY_BUDGET_KB == 1024
        assert limits.TIMESTEP_SECONDS == 0.001
        assert "LIF" in limits.SUPPORTED_NEURON_MODELS
        assert 8 in limits.SUPPORTED_WEIGHT_BIT_WIDTHS
        assert 16 in limits.SUPPORTED_WEIGHT_BIT_WIDTHS
        assert 32 in limits.SUPPORTED_WEIGHT_BIT_WIDTHS

    def test_frozen(self) -> None:
        with pytest.raises(ValidationError):
            TEENSY_LIMITS.MAX_NEURONS = 8192  # type: ignore[misc]

    def test_max_synapses_decreases_with_bit_width(self) -> None:
        assert (
            TEENSY_LIMITS.max_synapses_for_bit_width(8)
            > TEENSY_LIMITS.max_synapses_for_bit_width(16)
            > TEENSY_LIMITS.max_synapses_for_bit_width(32)
        )

    def test_max_synapses_positive(self) -> None:
        for bw in TEENSY_LIMITS.SUPPORTED_WEIGHT_BIT_WIDTHS:
            assert TEENSY_LIMITS.max_synapses_for_bit_width(bw) > 0

    def test_max_synapses_float32_property(self) -> None:
        assert (
            TEENSY_LIMITS.max_synapses_for_bit_width(32)
            == TEENSY_LIMITS.MAX_SYNAPSES_FLOAT32
        )

    def test_max_synapses_int8_property(self) -> None:
        assert (
            TEENSY_LIMITS.max_synapses_for_bit_width(8)
            == TEENSY_LIMITS.MAX_SYNAPSES_INT8
        )


# ---------------------------------------------------------------------------
# TeensyTopologyConstraints
# ---------------------------------------------------------------------------


class TestTeensyTopologyConstraints:
    def test_defaults(self) -> None:
        assert not TEENSY_TOPOLOGY.allow_recurrent
        assert not TEENSY_TOPOLOGY.allow_lateral_inhibition
        assert not TEENSY_TOPOLOGY.allow_learning_rules
        assert not TEENSY_TOPOLOGY.allow_axonal_delays


# ---------------------------------------------------------------------------
# TeensyIOMapping
# ---------------------------------------------------------------------------


class TestTeensyIOMapping:
    def test_valid_mapping(self) -> None:
        mapping = TeensyIOMapping(
            input_population="sensory",
            output_population="motor",
            input_pins=[0, 1, 2],
            output_pins=[3, 4, 5],
        )
        assert mapping.input_population == "sensory"

    def test_pin_out_of_range(self) -> None:
        with pytest.raises(ValidationError, match="GPIO pin"):
            TeensyIOMapping(
                input_population="sensory",
                output_population="motor",
                input_pins=[100],
                output_pins=[3],
            )

    def test_negative_pin(self) -> None:
        with pytest.raises(ValidationError, match="GPIO pin"):
            TeensyIOMapping(
                input_population="sensory",
                output_population="motor",
                input_pins=[-1],
                output_pins=[3],
            )

    def test_duplicate_input_pins(self) -> None:
        with pytest.raises(ValidationError, match="Duplicate input"):
            TeensyIOMapping(
                input_population="sensory",
                output_population="motor",
                input_pins=[0, 0],
                output_pins=[3],
            )

    def test_overlapping_pins(self) -> None:
        with pytest.raises(ValidationError, match="overlap"):
            TeensyIOMapping(
                input_population="sensory",
                output_population="motor",
                input_pins=[0, 1],
                output_pins=[1, 2],
            )

    def test_too_many_pins(self) -> None:
        all_pins = list(range(55))
        with pytest.raises(ValidationError, match="exceeds"):
            TeensyIOMapping(
                input_population="sensory",
                output_population="motor",
                input_pins=all_pins,
                output_pins=[0],
            )


# ---------------------------------------------------------------------------
# TeensyDeploymentResult — fail-closed invariant
# ---------------------------------------------------------------------------


class TestTeensyDeploymentResult:
    def test_deployable_empty_rejections(self) -> None:
        result = TeensyDeploymentResult(
            verdict=TeensyDeployabilityVerdict.DEPLOYABLE,
            rejections=[],
        )
        assert result.verdict == TeensyDeployabilityVerdict.DEPLOYABLE

    def test_deployable_with_warnings(self) -> None:
        result = TeensyDeploymentResult(
            verdict=TeensyDeployabilityVerdict.DEPLOYABLE_WITH_WARNINGS,
            rejections=[],
            warnings=["Near capacity"],
        )
        assert result.verdict == TeensyDeployabilityVerdict.DEPLOYABLE_WITH_WARNINGS

    def test_not_deployable_with_rejections(self) -> None:
        result = TeensyDeploymentResult(
            verdict=TeensyDeployabilityVerdict.NOT_DEPLOYABLE,
            rejections=[TeensyRejectionReason.EXCEEDS_NEURON_CAPACITY],
        )
        assert result.verdict == TeensyDeployabilityVerdict.NOT_DEPLOYABLE

    def test_fail_closed_rejects_deployable_with_rejections(self) -> None:
        with pytest.raises(ValidationError, match="Fail-closed"):
            TeensyDeploymentResult(
                verdict=TeensyDeployabilityVerdict.DEPLOYABLE,
                rejections=[TeensyRejectionReason.EXCEEDS_NEURON_CAPACITY],
            )

    def test_fail_closed_rejects_not_deployable_without_rejections(self) -> None:
        with pytest.raises(ValidationError, match="Fail-closed"):
            TeensyDeploymentResult(
                verdict=TeensyDeployabilityVerdict.NOT_DEPLOYABLE,
                rejections=[],
            )


# ---------------------------------------------------------------------------
# plan_teensy_deployability — happy path
# ---------------------------------------------------------------------------


class TestPlanTeensyDeployabilityHappyPath:
    def test_minimal_network_deployable(self) -> None:
        ir = _minimal_lif_ir(n_pops=2, pop_size=10)
        result = plan_teensy_deployability(ir)
        assert result.verdict == TeensyDeployabilityVerdict.DEPLOYABLE
        assert result.rejections == []
        assert result.network_summary["n_neurons"] == 20
        assert result.network_summary["n_populations"] == 2

    def test_single_population(self) -> None:
        ir = _minimal_lif_ir(n_pops=1, pop_size=5, connected=False)
        result = plan_teensy_deployability(ir)
        assert result.verdict == TeensyDeployabilityVerdict.DEPLOYABLE

    def test_three_layer_feedforward(self) -> None:
        ir = _minimal_lif_ir(n_pops=3, pop_size=20)
        result = plan_teensy_deployability(ir)
        assert result.verdict == TeensyDeployabilityVerdict.DEPLOYABLE

    def test_max_neurons_exact(self) -> None:
        """Exactly MAX_NEURONS across multiple pops should not trigger EXCEEDS_NEURON_CAPACITY."""
        # Use multiple pops with sizes ≤ MAX_IO_PINS to avoid IO_SHAPE_MISMATCH
        n_pops = TEENSY_LIMITS.MAX_NEURONS // 50  # 4096 / 50 = 81 pops of 50
        remainder = TEENSY_LIMITS.MAX_NEURONS % 50
        ir = _minimal_lif_ir(n_pops=n_pops, pop_size=50)
        if remainder > 0:
            extra_name = f"pop_{n_pops}"
            ir.populations[extra_name] = PopulationIR(
                name=extra_name, size=remainder, population_type="lif"
            )
        total = sum(p.size for p in ir.populations.values() if p.size)
        assert total == TEENSY_LIMITS.MAX_NEURONS
        result = plan_teensy_deployability(ir)
        assert TeensyRejectionReason.EXCEEDS_NEURON_CAPACITY not in result.rejections


# ---------------------------------------------------------------------------
# plan_teensy_deployability — rejection paths
# ---------------------------------------------------------------------------


class TestPlanTeensyDeployabilityRejections:
    def test_exceeds_neuron_capacity(self) -> None:
        ir = _minimal_lif_ir(n_pops=1, pop_size=5000, connected=False)
        result = plan_teensy_deployability(ir)
        assert result.verdict == TeensyDeployabilityVerdict.NOT_DEPLOYABLE
        assert TeensyRejectionReason.EXCEEDS_NEURON_CAPACITY in result.rejections

    def test_unsupported_neuron_model(self) -> None:
        ir = NetworkIR(
            populations={
                "pop_0": PopulationIR(
                    name="pop_0", size=10, population_type="izhikevich"
                ),
            },
        )
        result = plan_teensy_deployability(ir)
        assert result.verdict == TeensyDeployabilityVerdict.NOT_DEPLOYABLE
        assert TeensyRejectionReason.UNSUPPORTED_NEURON_MODEL in result.rejections

    def test_unsupported_learning_rule(self) -> None:
        ir = _minimal_lif_ir(n_pops=2, pop_size=10)
        ir.learning_rules.append(LearningRuleIR(kind="stdp", rate=0.01, window=0.02))
        result = plan_teensy_deployability(ir)
        assert result.verdict == TeensyDeployabilityVerdict.NOT_DEPLOYABLE
        assert TeensyRejectionReason.UNSUPPORTED_LEARNING_RULE in result.rejections

    def test_recurrent_self_connection(self) -> None:
        ir = NetworkIR(
            populations={
                "pop_0": PopulationIR(name="pop_0", size=10, population_type="lif"),
            },
            connections=[ConnectionIR(source="pop_0", target="pop_0", weight=1.0)],
        )
        result = plan_teensy_deployability(ir)
        assert result.verdict == TeensyDeployabilityVerdict.NOT_DEPLOYABLE
        assert TeensyRejectionReason.UNSUPPORTED_TOPOLOGY in result.rejections

    def test_recurrent_cycle(self) -> None:
        ir = NetworkIR(
            populations={
                "a": PopulationIR(name="a", size=10, population_type="lif"),
                "b": PopulationIR(name="b", size=10, population_type="lif"),
            },
            connections=[
                ConnectionIR(source="a", target="b", weight=1.0),
                ConnectionIR(source="b", target="a", weight=0.5),
            ],
        )
        result = plan_teensy_deployability(ir)
        assert result.verdict == TeensyDeployabilityVerdict.NOT_DEPLOYABLE
        assert TeensyRejectionReason.UNSUPPORTED_TOPOLOGY in result.rejections

    def test_axonal_delay(self) -> None:
        ir = _minimal_lif_ir(n_pops=2, pop_size=10)
        ir.connections[0].delay = 0.005
        result = plan_teensy_deployability(ir)
        assert result.verdict == TeensyDeployabilityVerdict.NOT_DEPLOYABLE
        assert TeensyRejectionReason.UNSUPPORTED_AXONAL_DELAY in result.rejections

    def test_timestep_too_fine(self) -> None:
        ir = _minimal_lif_ir(n_pops=2, pop_size=10)
        ir.timing_declarations.append(
            TimingDeclarationIR(kind="timestep", value=0.0001)
        )
        result = plan_teensy_deployability(ir)
        assert result.verdict == TeensyDeployabilityVerdict.NOT_DEPLOYABLE
        assert TeensyRejectionReason.TIMESTEP_INCOMPATIBLE in result.rejections

    def test_io_shape_too_large(self) -> None:
        """First population larger than MAX_IO_PINS."""
        ir = _minimal_lif_ir(n_pops=2, pop_size=10)
        ir.populations["pop_0"].size = 60  # > 55
        result = plan_teensy_deployability(ir)
        assert result.verdict == TeensyDeployabilityVerdict.NOT_DEPLOYABLE
        assert TeensyRejectionReason.IO_SHAPE_MISMATCH in result.rejections

    def test_multiple_rejections(self) -> None:
        """Network with multiple violations gets multiple rejections."""
        ir = NetworkIR(
            populations={
                "pop_0": PopulationIR(
                    name="pop_0", size=5000, population_type="izhikevich"
                ),
            },
            learning_rules=[LearningRuleIR(kind="stdp")],
        )
        result = plan_teensy_deployability(ir)
        assert result.verdict == TeensyDeployabilityVerdict.NOT_DEPLOYABLE
        assert len(result.rejections) >= 2

    def test_lateral_inhibition_concept_rejected(self) -> None:
        ir = NetworkIR(
            populations={
                "pop_0": PopulationIR(
                    name="pop_0",
                    size=10,
                    population_type="lif",
                    provenance=[SourceProvenance(concept="lateral_inhibition")],
                ),
            },
        )
        result = plan_teensy_deployability(ir)
        assert result.verdict == TeensyDeployabilityVerdict.NOT_DEPLOYABLE
        assert TeensyRejectionReason.UNSUPPORTED_TOPOLOGY in result.rejections


# ---------------------------------------------------------------------------
# plan_teensy_deployability — warning paths
# ---------------------------------------------------------------------------


class TestPlanTeensyDeployabilityWarnings:
    def test_near_capacity_warning(self) -> None:
        """Network above 80% capacity should produce warnings."""
        # 80% of 4096 = 3276.8. Use 3500 neurons across many small pops
        # to avoid IO_SHAPE_MISMATCH (each pop ≤ 55)
        ir = _minimal_lif_ir(n_pops=70, pop_size=50, connected=False)  # 70 * 50 = 3500
        result = plan_teensy_deployability(ir)
        assert result.verdict == TeensyDeployabilityVerdict.DEPLOYABLE_WITH_WARNINGS
        assert any("capacity" in w for w in result.warnings)

    def test_no_warnings_for_small_network(self) -> None:
        ir = _minimal_lif_ir(n_pops=2, pop_size=10)
        result = plan_teensy_deployability(ir)
        assert result.warnings == []
