"""Tests for Dream-Hand learning sync artifact generation."""

from __future__ import annotations

from neurocnl.handoff import (
    build_dreamhand_learning_sync_artifact,
    build_dreamhand_learning_sync_artifacts,
)
from neurocnl.ir.types import (
    ConnectionIR,
    LearningRuleIR,
    NetworkIR,
    PopulationIR,
    SourceProvenance,
)


def _stdp_ir() -> NetworkIR:
    return NetworkIR(
        populations={
            "sensory": PopulationIR(name="sensory", size=16),
            "motor": PopulationIR(name="motor", size=16),
        },
        connections=[ConnectionIR(source="sensory", target="motor", weight=1.5)],
        learning_rules=[
            LearningRuleIR(
                kind="stdp",
                window=0.02,
                provenance=[SourceProvenance(line=1, concept="stdp_learning")],
                attributes={"update_direction": "strengthen"},
            ),
            LearningRuleIR(
                kind="stdp",
                weight_min=0.1,
                weight_max=3.0,
                provenance=[SourceProvenance(line=2, concept="stdp_learning")],
                attributes={},
            ),
        ],
    )


def test_build_loihi_learning_sync_artifact_infers_single_connection_scope() -> None:
    artifact = build_dreamhand_learning_sync_artifact(_stdp_ir(), "loihi")

    assert artifact["backend"] == "loihi"
    assert artifact["synchronization_mode"] == "native_on_chip"
    assert artifact["capability_verdict"] == "approximate"
    assert artifact["native_learning_supported"] is True
    assert len(artifact["rules"]) == 2

    strengthen_rule = artifact["rules"][0]
    assert strengthen_rule["source"] == "sensory"
    assert strengthen_rule["target"] == "motor"
    assert strengthen_rule["scope"] == "inferred_single_connection"
    assert strengthen_rule["quantized_delta"] == 1
    assert strengthen_rule["weight_min"] == 0.1
    assert strengthen_rule["weight_max"] == 3.0


def test_build_akida_learning_sync_artifact_marks_host_sync() -> None:
    artifact = build_dreamhand_learning_sync_artifact(_stdp_ir(), "akida2")

    assert artifact["backend"] == "akida2"
    assert artifact["hardware_family"] == "akida"
    assert artifact["synchronization_mode"] == "host_quantized_sync"
    assert artifact["native_learning_supported"] is False
    assert artifact["capability_verdict"] == "unsupported"


def test_build_learning_sync_artifacts_returns_backend_map() -> None:
    artifacts = build_dreamhand_learning_sync_artifacts(_stdp_ir())
    assert set(artifacts) == {"loihi", "akida"}
