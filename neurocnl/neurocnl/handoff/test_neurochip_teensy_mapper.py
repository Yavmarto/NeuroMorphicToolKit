"""Integration tests for NeuroCNL → Neurochip Teensy handoff mapper.

Covers:
- Deployable feedforward network → correct payload
- Rejected network (STDP learning) → TeensyHandoffRejectedError
- Rejected network (recurrent) → TeensyHandoffRejectedError
- Deterministic payload generation
- Default population size fallback
- Network depth computation
"""

from __future__ import annotations

import json

import pytest

from neurocnl.contracts.teensy_deployment_contract import (
    TeensyDeployabilityVerdict,
    TeensyDeploymentResult,
    TeensyRejectionReason,
)
from neurocnl.handoff.neurochip_teensy_mapper import (
    HandoffResult,
    TeensyHandoffRejectedError,
    _compute_network_depth,
    map_network_ir_to_teensy_payload,
)
from neurocnl.ir.types import (
    ConnectionIR,
    LearningRuleIR,
    NetworkIR,
    PopulationIR,
    SourceProvenance,
)

# ---------------------------------------------------------------------------
# IR builder helpers
# ---------------------------------------------------------------------------


def _feedforward_ir(
    n_pops: int = 2,
    pop_size: int = 10,
    pop_type: str = "lif",
) -> NetworkIR:
    """Build a minimal feedforward LIF network IR."""
    pops = {}
    for i in range(n_pops):
        role = "sensory" if i == 0 else ("motor" if i == n_pops - 1 else "interneuron")
        name = f"pop_{i}"
        pops[name] = PopulationIR(
            name=name,
            size=pop_size,
            role=role,
            population_type=pop_type,
            provenance=[SourceProvenance(line=i + 1, concept="network_topology")],
        )
    conns = []
    names = list(pops)
    for i in range(len(names) - 1):
        conns.append(
            ConnectionIR(
                source=names[i],
                target=names[i + 1],
                weight=1.0,
                provenance=[SourceProvenance(line=100 + i, concept="synaptic_weight")],
            )
        )
    return NetworkIR(populations=pops, connections=conns)


def _recurrent_ir() -> NetworkIR:
    """A → B → A (cycle)."""
    pops = {
        "a": PopulationIR(name="a", size=10, role="sensory", population_type="lif"),
        "b": PopulationIR(name="b", size=10, role="motor", population_type="lif"),
    }
    conns = [
        ConnectionIR(source="a", target="b", weight=1.0),
        ConnectionIR(source="b", target="a", weight=1.0),
    ]
    return NetworkIR(populations=pops, connections=conns)


def _ir_with_learning_rule() -> NetworkIR:
    """Feedforward network with an STDP learning rule (unsupported on Teensy)."""
    pops = {
        "sensory": PopulationIR(name="sensory", size=10, role="sensory", population_type="lif"),
        "motor": PopulationIR(name="motor", size=10, role="motor", population_type="lif"),
    }
    conns = [ConnectionIR(source="sensory", target="motor", weight=1.0)]
    rule = LearningRuleIR(
        kind="stdp_learning",
        source="sensory",
        target="motor",
        provenance=[SourceProvenance(line=1, concept="stdp_learning")],
    )
    return NetworkIR(populations=pops, connections=conns, learning_rules=[rule])


def _ir_with_none_sizes(n_pops: int = 2) -> NetworkIR:
    """Feedforward network where populations have size=None."""
    pops = {}
    for i in range(n_pops):
        role = "sensory" if i == 0 else "motor"
        name = f"pop_{i}"
        pops[name] = PopulationIR(name=name, size=None, role=role, population_type="lif")
    conns = []
    names = list(pops)
    for i in range(len(names) - 1):
        conns.append(ConnectionIR(source=names[i], target=names[i + 1], weight=1.0))
    return NetworkIR(populations=pops, connections=conns)


# ---------------------------------------------------------------------------
# TestDeployableNetwork
# ---------------------------------------------------------------------------


class TestDeployableNetwork:
    """A minimal feedforward LIF network should produce a valid payload."""

    def test_payload_fields(self) -> None:
        ir = _feedforward_ir(n_pops=2, pop_size=10)
        result = map_network_ir_to_teensy_payload(ir)

        assert isinstance(result, HandoffResult)
        p = result.payload

        assert p["num_neurons"] == 20
        assert p["num_synapses"] == 100  # 10 × 10
        assert p["neuron_model"] == "LIF"
        assert p["weight_bit_width"] == 32
        assert p["network_depth"] == 2

        assert len(p["populations"]) == 2
        assert len(p["connections"]) == 1

    def test_population_dicts(self) -> None:
        ir = _feedforward_ir(n_pops=3, pop_size=5)
        result = map_network_ir_to_teensy_payload(ir)
        pops = result.payload["populations"]

        # Sorted by name
        assert pops[0]["name"] == "pop_0"
        assert pops[0]["size"] == 5
        assert pops[1]["name"] == "pop_1"
        assert pops[2]["name"] == "pop_2"

    def test_connection_dicts(self) -> None:
        ir = _feedforward_ir(n_pops=3, pop_size=5)
        result = map_network_ir_to_teensy_payload(ir)
        conns = result.payload["connections"]

        assert len(conns) == 2
        assert conns[0]["pre"] == "pop_0"
        assert conns[0]["post"] == "pop_1"
        assert conns[0]["weight_count"] == 25  # 5 × 5
        assert conns[1]["pre"] == "pop_1"
        assert conns[1]["post"] == "pop_2"

    def test_json_serializable(self) -> None:
        ir = _feedforward_ir()
        result = map_network_ir_to_teensy_payload(ir)
        # Must not raise
        serialized = json.dumps(result.payload, sort_keys=True)
        assert isinstance(serialized, str)

    def test_provenance_attached(self) -> None:
        ir = _feedforward_ir(n_pops=2, pop_size=10)
        result = map_network_ir_to_teensy_payload(ir)

        prov = result.provenance
        assert "pop_0" in prov.populations
        assert "pop_1" in prov.populations
        assert len(prov.connections) == 1
        assert prov.connections[0]["source"] == "pop_0"

    def test_deployment_verdict(self) -> None:
        ir = _feedforward_ir()
        result = map_network_ir_to_teensy_payload(ir)

        assert result.deployment_result.verdict in {
            TeensyDeployabilityVerdict.DEPLOYABLE,
            TeensyDeployabilityVerdict.DEPLOYABLE_WITH_WARNINGS,
        }
        assert result.deployment_result.rejections == []

    def test_custom_bit_width(self) -> None:
        ir = _feedforward_ir()
        result = map_network_ir_to_teensy_payload(ir, weight_bit_width=8)
        assert result.payload["weight_bit_width"] == 8


# ---------------------------------------------------------------------------
# TestRejectedNetwork
# ---------------------------------------------------------------------------


class TestRejectedNetwork:
    """Networks that fail the deployability gate must raise."""

    def test_stdp_learning_rule_rejected(self) -> None:
        ir = _ir_with_learning_rule()
        with pytest.raises(TeensyHandoffRejectedError) as exc_info:
            map_network_ir_to_teensy_payload(ir)

        err = exc_info.value
        assert isinstance(err.deployment_result, TeensyDeploymentResult)
        assert err.deployment_result.verdict == TeensyDeployabilityVerdict.NOT_DEPLOYABLE
        assert TeensyRejectionReason.UNSUPPORTED_LEARNING_RULE in err.deployment_result.rejections

    def test_error_message_contains_reason(self) -> None:
        ir = _ir_with_learning_rule()
        with pytest.raises(TeensyHandoffRejectedError, match="unsupported_learning_rule"):
            map_network_ir_to_teensy_payload(ir)


class TestRejectedRecurrentNetwork:
    """Recurrent networks must be rejected."""

    def test_recurrent_rejected(self) -> None:
        ir = _recurrent_ir()
        with pytest.raises(TeensyHandoffRejectedError) as exc_info:
            map_network_ir_to_teensy_payload(ir)

        err = exc_info.value
        assert err.deployment_result.verdict == TeensyDeployabilityVerdict.NOT_DEPLOYABLE
        assert TeensyRejectionReason.UNSUPPORTED_TOPOLOGY in err.deployment_result.rejections


# ---------------------------------------------------------------------------
# TestDeterminism
# ---------------------------------------------------------------------------


class TestDeterminism:
    """Repeated calls on the same IR must produce identical payloads."""

    def test_identical_payloads(self) -> None:
        ir = _feedforward_ir(n_pops=3, pop_size=8)
        r1 = map_network_ir_to_teensy_payload(ir)
        r2 = map_network_ir_to_teensy_payload(ir)

        s1 = json.dumps(r1.payload, sort_keys=True)
        s2 = json.dumps(r2.payload, sort_keys=True)
        assert s1 == s2


# ---------------------------------------------------------------------------
# TestDefaultPopulationSize
# ---------------------------------------------------------------------------


class TestDefaultPopulationSize:
    """Populations with size=None should fall back to 50."""

    def test_none_size_defaults_to_50(self) -> None:
        ir = _ir_with_none_sizes(n_pops=2)
        result = map_network_ir_to_teensy_payload(ir)

        assert result.payload["num_neurons"] == 100  # 50 + 50
        for pop in result.payload["populations"]:
            assert pop["size"] == 50

    def test_synapse_count_uses_default(self) -> None:
        ir = _ir_with_none_sizes(n_pops=2)
        result = map_network_ir_to_teensy_payload(ir)

        assert result.payload["num_synapses"] == 2500  # 50 × 50


# ---------------------------------------------------------------------------
# TestNetworkDepth
# ---------------------------------------------------------------------------


class TestNetworkDepth:
    """Network depth = longest path from any root population."""

    def test_linear_chain_4(self) -> None:
        ir = _feedforward_ir(n_pops=4, pop_size=5)
        assert _compute_network_depth(ir) == 4

    def test_single_population(self) -> None:
        pops = {"only": PopulationIR(name="only", size=5, population_type="lif")}
        ir = NetworkIR(populations=pops)
        assert _compute_network_depth(ir) == 1

    def test_two_populations_one_connection(self) -> None:
        ir = _feedforward_ir(n_pops=2, pop_size=5)
        assert _compute_network_depth(ir) == 2

    def test_empty_network(self) -> None:
        ir = NetworkIR()
        assert _compute_network_depth(ir) == 1

    def test_diamond_topology(self) -> None:
        """Diamond: A → B, A → C, B → D, C → D  →  depth 3."""
        pops = {
            "a": PopulationIR(name="a", size=5, population_type="lif"),
            "b": PopulationIR(name="b", size=5, population_type="lif"),
            "c": PopulationIR(name="c", size=5, population_type="lif"),
            "d": PopulationIR(name="d", size=5, population_type="lif"),
        }
        conns = [
            ConnectionIR(source="a", target="b", weight=1.0),
            ConnectionIR(source="a", target="c", weight=1.0),
            ConnectionIR(source="b", target="d", weight=1.0),
            ConnectionIR(source="c", target="d", weight=1.0),
        ]
        ir = NetworkIR(populations=pops, connections=conns)
        assert _compute_network_depth(ir) == 3
