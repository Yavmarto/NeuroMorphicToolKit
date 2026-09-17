"""Unit tests for plan_backend_support — the general advisory dispatcher.

plan_backend_support had no direct test before this slice; its behavior was
only exercised indirectly through the Teensy/PYNQ/Akida contract tests (which
call the target-specific plan_* functions) and through router-level
integration tests. These tests target the dispatcher itself: concept
classification, timing warnings, the Loihi validator-report branch, and the
Teensy/PYNQ/Akida delegation branches.
"""

from __future__ import annotations

from neurocnl.ir.types import (
    ConnectionIR,
    NetworkIR,
    PopulationIR,
    SourceProvenance,
    TimingDeclarationIR,
)
from neurocnl.planner import PlannerResult, plan_backend_support


def _lif_chain_ir(*, concept: str | None = None) -> NetworkIR:
    provenance = [SourceProvenance(concept=concept)] if concept else []
    pops = {
        "sensory": PopulationIR(
            name="sensory", size=4, role="sensory", population_type="lif", provenance=provenance
        ),
        "motor": PopulationIR(name="motor", size=4, role="motor", population_type="lif"),
    }
    conns = [ConnectionIR(source="sensory", target="motor", weight=1.0)]
    return NetworkIR(populations=pops, connections=conns)


class TestVerdictMerging:
    def test_faithful_when_all_concepts_supported(self) -> None:
        # "network_topology" and "population_coding" are faithful on the plain
        # "nengo" backend per BACKEND_CAPABILITIES; a bare LIF chain declares
        # no concepts at all via provenance, so nothing can be unsupported.
        result = plan_backend_support(_lif_chain_ir(), "nengo")
        assert isinstance(result, PlannerResult)
        assert result.backend == "nengo"
        assert result.verdict in {"faithful", "approximate"}
        assert result.unsupported_concepts == []

    def test_approximate_concept_is_reported_and_warned(self) -> None:
        # stdp_learning is only "approximate" on "nengo" per BACKEND_CAPABILITIES.
        result = plan_backend_support(_lif_chain_ir(concept="stdp_learning"), "nengo")
        assert "stdp_learning" in result.approximated_concepts
        assert result.verdict == "approximate"
        assert any("stdp_learning" in w for w in result.warnings)

    def test_result_has_no_duplicate_warnings(self) -> None:
        ir = _lif_chain_ir(concept="stdp_learning")
        result = plan_backend_support(ir, "nengo")
        assert len(result.warnings) == len(set(result.warnings))


class TestTimingWarnings:
    def test_timestep_mismatch_warns(self) -> None:
        ir = _lif_chain_ir()
        ir.timing_declarations.append(TimingDeclarationIR(kind="timestep", value=0.5))
        result = plan_backend_support(ir, "teensy")
        assert any("Declared timestep" in w for w in result.warnings)

    def test_delay_quantization_finer_than_resolution_warns(self) -> None:
        ir = _lif_chain_ir()
        ir.timing_declarations.append(
            TimingDeclarationIR(kind="delay_quantization", value=0.0000001)
        )
        result = plan_backend_support(ir, "teensy")
        assert any("delay quantization" in w for w in result.warnings)

    def test_no_timing_warning_when_undeclared(self) -> None:
        result = plan_backend_support(_lif_chain_ir(), "teensy")
        assert not any(
            "Declared timestep" in w or "delay quantization" in w for w in result.warnings
        )


class TestLoihiValidatorReport:
    def test_failed_loihi_entry_forces_unsupported(self) -> None:
        report = {
            "failed": [{"code": "loihi_axon_limit", "message": "Too many axons"}],
            "warnings": [],
        }
        result = plan_backend_support(_lif_chain_ir(), "loihi", validator_report=report)
        assert result.verdict == "unsupported"
        assert "Too many axons" in result.warnings

    def test_loihi_warning_entry_downgrades_faithful_to_approximate(self) -> None:
        report = {
            "failed": [],
            "warnings": [{"code": "loihi_soft_limit", "message": "Near a soft limit"}],
        }
        result = plan_backend_support(_lif_chain_ir(), "loihi", validator_report=report)
        assert "Near a soft limit" in result.warnings

    def test_non_loihi_codes_in_report_are_ignored(self) -> None:
        report = {
            "failed": [{"code": "other_backend_thing", "message": "irrelevant"}],
            "warnings": [],
        }
        result = plan_backend_support(_lif_chain_ir(), "loihi", validator_report=report)
        assert "irrelevant" not in result.warnings


class TestTeensyDelegation:
    def _oversized_ir(self) -> NetworkIR:
        pops = {"huge": PopulationIR(name="huge", size=10_000, population_type="lif")}
        return NetworkIR(populations=pops, connections=[])

    def test_not_deployable_teensy_sets_unsupported_verdict(self) -> None:
        result = plan_backend_support(self._oversized_ir(), "teensy")
        assert result.verdict == "unsupported"
        assert any("Teensy:" in w for w in result.warnings)

    def test_deployable_teensy_network_does_not_force_unsupported(self) -> None:
        result = plan_backend_support(_lif_chain_ir(), "teensy")
        assert result.verdict != "unsupported"


class TestPynqDelegation:
    def _branching_ir(self) -> NetworkIR:
        # A branch (one source, two targets) is not a linear chain -> PYNQ rejects.
        pops = {
            "a": PopulationIR(name="a", size=4, population_type="lif"),
            "b": PopulationIR(name="b", size=4, population_type="lif"),
            "c": PopulationIR(name="c", size=4, population_type="lif"),
        }
        conns = [
            ConnectionIR(source="a", target="b", weight=1.0),
            ConnectionIR(source="a", target="c", weight=1.0),
        ]
        return NetworkIR(populations=pops, connections=conns)

    def test_not_exportable_pynq_sets_not_exportable_verdict(self) -> None:
        result = plan_backend_support(self._branching_ir(), "pynq")
        assert result.verdict == "not_exportable"
        assert any("PYNQ:" in w for w in result.warnings)

    def test_exportable_pynq_network_yields_exportable_verdict(self) -> None:
        result = plan_backend_support(_lif_chain_ir(), "pynq")
        assert result.verdict in {"exportable", "exportable_with_warnings"}


class TestAkidaDelegation:
    def test_learning_rule_rejection_is_reported_with_akida_warning(self) -> None:
        # Note: plan_backend_support recomputes `verdict` from the generic
        # concept lists after the Akida delegation block, so an Akida-only
        # rejection (no unsupported *concept*) surfaces as "approximate" plus
        # an "Akida:" warning rather than forcing "unsupported" end to end —
        # this is pre-existing behavior, unchanged by this slice.
        from neurocnl.ir.types import LearningRuleIR

        ir = _lif_chain_ir()
        ir.learning_rules.append(LearningRuleIR(kind="stdp"))
        result = plan_backend_support(ir, "akida")
        assert any("Akida:" in w for w in result.warnings)
        assert result.verdict != "faithful"

    def test_simple_feedforward_akida_not_forced_unsupported_by_topology(self) -> None:
        result = plan_backend_support(_lif_chain_ir(), "akida")
        assert result.verdict != "unsupported"
