"""Tests for PYNQ deployment contract and planner exportability."""

import pytest
from pydantic import ValidationError

from neurocnl.contracts.pynq_deployment_contract import (
    PYNQ_LIMITS,
    PynqExportResult,
    PynqRejectionReason,
    PynqSupportState,
)
from neurocnl.ir.types import ConnectionIR, LearningRuleIR, NetworkIR, PopulationIR
from neurocnl.planner import plan_pynq_exportability

# ---------------------------------------------------------------------------
# Contract invariant tests
# ---------------------------------------------------------------------------


class TestPynqExportResultInvariant:
    """Fail-closed invariant: rejections empty ⟺ state != NOT_EXPORTABLE."""

    def test_exportable_no_rejections(self) -> None:
        result = PynqExportResult(
            support_state=PynqSupportState.EXPORTABLE,
            rejections=[],
        )
        assert result.support_state == PynqSupportState.EXPORTABLE

    def test_exportable_with_warnings_no_rejections(self) -> None:
        result = PynqExportResult(
            support_state=PynqSupportState.EXPORTABLE_WITH_WARNINGS,
            rejections=[],
            warnings=["Near 80% capacity"],
        )
        assert result.support_state == PynqSupportState.EXPORTABLE_WITH_WARNINGS

    def test_not_exportable_with_rejections(self) -> None:
        result = PynqExportResult(
            support_state=PynqSupportState.NOT_EXPORTABLE,
            rejections=[PynqRejectionReason.EXCEEDS_NEURON_CAPACITY],
        )
        assert result.support_state == PynqSupportState.NOT_EXPORTABLE

    def test_invariant_violation_rejections_but_exportable(self) -> None:
        with pytest.raises(ValidationError, match="Fail-closed violation"):
            PynqExportResult(
                support_state=PynqSupportState.EXPORTABLE,
                rejections=[PynqRejectionReason.EXCEEDS_NEURON_CAPACITY],
            )

    def test_invariant_violation_no_rejections_but_not_exportable(self) -> None:
        with pytest.raises(ValidationError, match="Fail-closed violation"):
            PynqExportResult(
                support_state=PynqSupportState.NOT_EXPORTABLE,
                rejections=[],
            )

    def test_not_deployable_with_rejections(self) -> None:
        result = PynqExportResult(
            support_state=PynqSupportState.NOT_DEPLOYABLE,
            rejections=[PynqRejectionReason.BOARD_UNREACHABLE],
        )
        assert result.support_state == PynqSupportState.NOT_DEPLOYABLE

    def test_all_rejection_reasons_have_messages(self) -> None:
        from neurocnl.contracts.pynq_deployment_contract import REJECTION_MESSAGES

        for reason in PynqRejectionReason:
            assert (
                reason in REJECTION_MESSAGES
            ), f"Rejection reason {reason.value!r} has no human-readable message"


# ---------------------------------------------------------------------------
# Hardware limits tests
# ---------------------------------------------------------------------------


class TestPynqHardwareLimits:
    def test_limits_frozen(self) -> None:
        with pytest.raises(ValidationError):
            PYNQ_LIMITS.MAX_NEURONS = 1  # type: ignore[misc]

    def test_max_synapses_int4(self) -> None:
        result = PYNQ_LIMITS.max_synapses_for_bit_width(4)
        assert result == 0

    def test_max_synapses_int8(self) -> None:
        result = PYNQ_LIMITS.max_synapses_for_bit_width(8)
        assert result == 262144

    def test_max_synapses_int16(self) -> None:
        result = PYNQ_LIMITS.max_synapses_for_bit_width(16)
        assert result == 0


# ---------------------------------------------------------------------------
# Planner tests: plan_pynq_exportability
# ---------------------------------------------------------------------------


def _make_ir(
    populations: dict[str, PopulationIR] | None = None,
    connections: list[ConnectionIR] | None = None,
    learning_rules: list[LearningRuleIR] | None = None,
) -> NetworkIR:
    """Helper to build a minimal NetworkIR for testing."""
    return NetworkIR(
        populations=populations or {},
        connections=connections or [],
        learning_rules=learning_rules or [],
    )


class TestPlanPynqExportability:
    def test_simple_network_exportable(self) -> None:
        ir = _make_ir(
            populations={
                "sensory": PopulationIR(name="sensory", size=10),
                "motor": PopulationIR(name="motor", size=5),
            },
            connections=[
                ConnectionIR(source="sensory", target="motor", weight=1.0),
            ],
        )
        result = plan_pynq_exportability(ir)
        assert result.support_state == PynqSupportState.EXPORTABLE
        assert result.rejections == []

    def test_exceeds_neuron_capacity(self) -> None:
        ir = _make_ir(
            populations={
                "big_pop": PopulationIR(name="big_pop", size=70000),
            },
        )
        result = plan_pynq_exportability(ir)
        assert result.support_state == PynqSupportState.NOT_EXPORTABLE
        assert PynqRejectionReason.EXCEEDS_NEURON_CAPACITY in result.rejections

    def test_exceeds_synapse_capacity(self) -> None:
        # 600 * 600 = 360000 synapses > the 262144-weight on-chip cache, while
        # both populations stay inside the per-layer neuron limit.
        ir = _make_ir(
            populations={
                "a": PopulationIR(name="a", size=600),
                "b": PopulationIR(name="b", size=600),
            },
            connections=[
                ConnectionIR(source="a", target="b", weight=1.0),
            ],
        )
        result = plan_pynq_exportability(ir)
        assert result.support_state == PynqSupportState.NOT_EXPORTABLE
        assert PynqRejectionReason.EXCEEDS_SYNAPSE_CAPACITY in result.rejections

    def test_unsupported_neuron_model(self) -> None:
        ir = _make_ir(
            populations={
                "pop": PopulationIR(
                    name="pop", size=10, population_type="hodgkin_huxley"
                ),
            },
        )
        result = plan_pynq_exportability(ir)
        assert result.support_state == PynqSupportState.NOT_EXPORTABLE
        assert PynqRejectionReason.UNSUPPORTED_NEURON_MODEL in result.rejections

    def test_lif_neuron_model_accepted(self) -> None:
        ir = _make_ir(
            populations={
                "pop": PopulationIR(name="pop", size=10, population_type="lif"),
            },
        )
        result = plan_pynq_exportability(ir)
        assert PynqRejectionReason.UNSUPPORTED_NEURON_MODEL not in result.rejections

    def test_izhikevich_neuron_model_rejected(self) -> None:
        ir = _make_ir(
            populations={
                "pop": PopulationIR(name="pop", size=10, population_type="izhikevich"),
            },
        )
        result = plan_pynq_exportability(ir)
        assert PynqRejectionReason.UNSUPPORTED_NEURON_MODEL in result.rejections

    def test_learning_rules_rejected(self) -> None:
        ir = _make_ir(
            populations={
                "a": PopulationIR(name="a", size=10),
                "b": PopulationIR(name="b", size=10),
            },
            connections=[
                ConnectionIR(source="a", target="b", weight=1.0),
            ],
            learning_rules=[
                LearningRuleIR(kind="stdp", source="a", target="b"),
            ],
        )
        result = plan_pynq_exportability(ir)
        assert result.support_state == PynqSupportState.NOT_EXPORTABLE
        assert PynqRejectionReason.UNSUPPORTED_LEARNING_RULE in result.rejections

    def test_recurrent_connections_rejected(self) -> None:
        ir = _make_ir(
            populations={
                "a": PopulationIR(name="a", size=10),
                "b": PopulationIR(name="b", size=10),
            },
            connections=[
                ConnectionIR(source="a", target="b", weight=1.0),
                ConnectionIR(source="b", target="a", weight=0.5),
            ],
        )
        result = plan_pynq_exportability(ir)
        assert result.support_state == PynqSupportState.NOT_EXPORTABLE
        assert PynqRejectionReason.UNSUPPORTED_TOPOLOGY in result.rejections

    def test_unsupported_bit_width_rejected(self) -> None:
        ir = _make_ir(
            populations={
                "pop": PopulationIR(name="pop", size=10),
            },
        )
        result = plan_pynq_exportability(ir, bit_width=32)
        assert result.support_state == PynqSupportState.NOT_EXPORTABLE
        assert PynqRejectionReason.WEIGHT_BIT_WIDTH_UNSUPPORTED in result.rejections

    def test_near_capacity_produces_warnings(self) -> None:
        # 4 x 900 = 3600 neurons, ~88% of the overlay's 4096-neuron capacity,
        # with each layer inside the 1024-neuron per-layer limit.
        ir = _make_ir(
            populations={
                f"big_{index}": PopulationIR(name=f"big_{index}", size=900)
                for index in range(4)
            },
        )
        result = plan_pynq_exportability(ir)
        assert result.support_state == PynqSupportState.EXPORTABLE_WITH_WARNINGS
        assert any("neurons" in w and "80%" in w for w in result.warnings)

    def test_network_summary_populated(self) -> None:
        ir = _make_ir(
            populations={
                "a": PopulationIR(name="a", size=10),
                "b": PopulationIR(name="b", size=5),
            },
            connections=[
                ConnectionIR(source="a", target="b", weight=1.0),
            ],
        )
        result = plan_pynq_exportability(ir)
        assert result.network_summary["n_neurons"] == 15
        assert result.network_summary["n_synapses"] == 50
        assert result.network_summary["quantization_bits"] == 8
        assert "memory_estimate_kb" in result.network_summary


class TestPlanPynqQuantisation:
    """int8 quantisation is lossy on purpose; only the impossible is refused.

    The old gate demanded every scaled weight land exactly on an integer, which
    contradicted the `np.round` in the quantiser it guarded. It never fired while
    PYNQ weights were zeros (max_abs 0 skipped it) or hand-picked literals, and
    rejected every trained matrix the moment real values arrived.
    """

    @staticmethod
    def _ir_with_weight(weight: list[list[float]]) -> NetworkIR:
        return _make_ir(
            populations={
                "a": PopulationIR(name="a", size=2, population_type="lif"),
                "b": PopulationIR(name="b", size=1, population_type="lif"),
            },
            connections=[ConnectionIR(source="a", target="b", weight=weight)],
        )

    def test_ordinary_trained_floats_are_exportable(self) -> None:
        result = plan_pynq_exportability(self._ir_with_weight([[0.37, -0.9142]]))
        assert PynqRejectionReason.WEIGHT_NOT_QUANTIZABLE not in result.rejections
        assert result.support_state != PynqSupportState.NOT_EXPORTABLE

    def test_non_finite_weights_are_rejected(self) -> None:
        result = plan_pynq_exportability(self._ir_with_weight([[1.0, float("nan")]]))
        assert result.support_state == PynqSupportState.NOT_EXPORTABLE
        assert PynqRejectionReason.WEIGHT_NOT_QUANTIZABLE in result.rejections

    def test_weights_that_round_to_zero_warn_rather_than_reject(self) -> None:
        # 1e-4 against a 100.0 maximum scales to 0.000127 and rounds away, so that
        # synapse will not fire on the board. Worth saying; not worth refusing.
        result = plan_pynq_exportability(self._ir_with_weight([[100.0, 1e-4]]))
        assert PynqRejectionReason.WEIGHT_NOT_QUANTIZABLE not in result.rejections
        assert result.support_state == PynqSupportState.EXPORTABLE_WITH_WARNINGS
        assert any("round to zero" in warning for warning in result.warnings)

    def test_all_zero_weights_neither_warn_nor_reject(self) -> None:
        # The pre-sidecar default: a spec-derived matrix is all zeros. It must stay
        # exportable (that is what the hardware bring-up path relies on) and must
        # not claim weights were lost, because there were none to lose.
        result = plan_pynq_exportability(self._ir_with_weight([[0.0, 0.0]]))
        assert result.support_state == PynqSupportState.EXPORTABLE
        assert not any("round to zero" in warning for warning in result.warnings)


class TestPlanPynqPortPopulationsExcluded:
    """Declared I/O ports are DMA-mapped, not on-chip neurons or weights.

    ``export_pynq_from_ir`` drops port populations from its population list and
    its weight matrix, so every planner gate has to measure the same thing —
    otherwise the planner rejects networks the exporter would build happily.
    """

    @staticmethod
    def _ported_ir(
        *,
        input_size: int,
        hidden_size: int,
        output_size: int,
    ) -> NetworkIR:
        """`in port → hidden → out` plus an output port, the overlay-v1 shape."""
        return _make_ir(
            populations={
                "pixels": PopulationIR(
                    name="pixels", size=input_size, population_type="input"
                ),
                "hidden": PopulationIR(
                    name="hidden", size=hidden_size, population_type="lif"
                ),
                "out": PopulationIR(
                    name="out", size=output_size, population_type="lif"
                ),
                "labels": PopulationIR(
                    name="labels", size=output_size, population_type="output"
                ),
            },
            connections=[
                ConnectionIR(source="pixels", target="hidden", weight=1.0),
                ConnectionIR(source="hidden", target="out", weight=1.0),
                ConnectionIR(source="out", target="labels", weight=1.0),
            ],
        )

    def test_demo_network_with_large_input_port_is_exportable(self) -> None:
        # 64 → 128 → 10: 138 real neurons and one 128×10 weight matrix, both
        # well inside overlay-v1. Counting the 64-wide input port as neurons
        # (and its 64×128 projection as synapses) is what used to reject this.
        result = plan_pynq_exportability(
            self._ported_ir(input_size=64, hidden_size=128, output_size=10)
        )
        assert result.support_state == PynqSupportState.EXPORTABLE
        assert result.rejections == []

    def test_input_port_wider_than_neuron_capacity_still_exportable(self) -> None:
        # A 784-pixel MNIST-style input port is 3× the 256-neuron budget on its
        # own, but it never occupies neurons — only the two real populations do.
        result = plan_pynq_exportability(
            self._ported_ir(input_size=784, hidden_size=64, output_size=10)
        )
        assert PynqRejectionReason.EXCEEDS_NEURON_CAPACITY not in result.rejections
        assert PynqRejectionReason.EXCEEDS_SYNAPSE_CAPACITY not in result.rejections

    def test_summary_counts_only_real_populations(self) -> None:
        result = plan_pynq_exportability(
            self._ported_ir(input_size=64, hidden_size=128, output_size=10)
        )
        assert result.network_summary["n_neurons"] == 138
        assert result.network_summary["n_synapses"] == 1280
        assert result.network_summary["n_populations"] == 2
        assert result.network_summary["n_connections"] == 1

    def test_real_populations_still_gated(self) -> None:
        # The exclusion must not become a blanket bypass: a hidden layer over
        # capacity is still rejected even when it sits behind an input port.
        # 2000 neurons fits the 4096 total but breaks the 1024 per-layer limit,
        # because each layer's state lives in a fixed-width on-chip array.
        result = plan_pynq_exportability(
            self._ported_ir(input_size=8, hidden_size=2000, output_size=10)
        )
        assert result.support_state == PynqSupportState.NOT_EXPORTABLE
        assert PynqRejectionReason.EXCEEDS_NEURON_CAPACITY in result.rejections

    def test_port_weights_do_not_trigger_quantization_rejection(self) -> None:
        # A non-integer-mappable weight on a DMA-mapped port projection isn't
        # quantized to int8 by the exporter, so it must not reject the network.
        ir = self._ported_ir(input_size=16, hidden_size=32, output_size=4)
        ir.connections[0].weight = 0.1234567
        result = plan_pynq_exportability(ir)
        assert PynqRejectionReason.WEIGHT_NOT_QUANTIZABLE not in result.rejections
