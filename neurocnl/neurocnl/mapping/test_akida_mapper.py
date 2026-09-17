"""Tests for the shared NeuroCNL → Akida mapping layer."""

from __future__ import annotations

import pytest

from neurocnl.contracts.akida_deployment_contract import AkidaSupportState
from neurocnl.ir.types import (
    AkidaBlockType,
    AkidaConnectionPropertyIR,
    AkidaHardwareIR,
    ConnectionIR,
    LearningRuleIR,
    NetworkIR,
    PopulationIR,
    SourceProvenance,
)
from neurocnl.mapping.akida_mapper import (
    AkidaMappingRejectedError,
    map_network_ir_to_akida_representation,
)


def _sequential_ir(
    akida_version: str = "Akida1",
    include_property: bool = False,
) -> NetworkIR:
    populations = {
        "sensory": PopulationIR(
            name="sensory",
            size=8,
            role="sensory",
            population_type="lif",
            provenance=[SourceProvenance(line=1, concept="threshold_firing")],
        ),
        "motor": PopulationIR(
            name="motor",
            size=4,
            role="motor",
            population_type="lif",
            provenance=[SourceProvenance(line=2, concept="threshold_firing")],
        ),
    }
    connections = [
        ConnectionIR(
            source="sensory",
            target="motor",
            weight=1.0,
            provenance=[SourceProvenance(line=10, concept="synaptic_weight")],
        )
    ]
    properties = []
    if include_property:
        properties.append(
            AkidaConnectionPropertyIR(
                block_type=AkidaBlockType.TEMPORAL,
                source="sensory",
                target="motor",
                provenance=[SourceProvenance(line=20, concept="akida_spatiotemporal")],
            )
        )

    return NetworkIR(
        populations=populations,
        connections=connections,
        akida_hardware=AkidaHardwareIR(
            version=akida_version,
            provenance=[SourceProvenance(line=30, concept="akida_hardware")],
        ),
        akida_connection_properties=properties,
        metadata={"provenance": [SourceProvenance(line=99, concept="network_topology")]},
    )


def test_maps_sequential_akida1_ir() -> None:
    mapped = map_network_ir_to_akida_representation(_sequential_ir(akida_version="Akida1"))

    assert mapped.akida_version == "akida1"
    assert mapped.input_population == "sensory"
    assert [population.id for population in mapped.populations] == ["sensory", "motor"]
    assert mapped.connections[0].source == "sensory"
    assert mapped.connections[0].target == "motor"
    assert mapped.connections[0].units == 4
    assert mapped.topology_verdict == "faithful"
    assert mapped.network_summary["n_populations"] == 2


def test_maps_sequential_akida2_ir_with_property_provenance() -> None:
    mapped = map_network_ir_to_akida_representation(
        _sequential_ir(akida_version="Akida2", include_property=True)
    )

    assert mapped.akida_version == "akida2"
    assert mapped.connections[0].block_type == "temporal"
    assert mapped.connections[0].property_provenance[0].concept == "akida_spatiotemporal"
    assert mapped.metadata_provenance[0].concept == "network_topology"


def test_mapping_is_deterministic() -> None:
    ir = _sequential_ir()

    mapped_a = map_network_ir_to_akida_representation(ir)
    mapped_b = map_network_ir_to_akida_representation(ir)

    assert mapped_a.model_dump() == mapped_b.model_dump()


def test_mapping_preserves_population_and_connection_provenance() -> None:
    mapped = map_network_ir_to_akida_representation(_sequential_ir())

    assert mapped.populations[0].provenance[0].line == 1
    assert mapped.connections[0].provenance[0].line == 10


def test_mapping_honors_explicit_version_normalization() -> None:
    ir = _sequential_ir()
    ir.akida_hardware = None

    mapped = map_network_ir_to_akida_representation(ir, akida_version="Akida 2.0")

    assert mapped.akida_version == "akida2"


def test_rejects_approximate_akida2_branching_topology() -> None:
    ir = NetworkIR(
        populations={
            "sensory": PopulationIR(name="sensory", size=8, population_type="lif"),
            "interneuron": PopulationIR(name="interneuron", size=6, population_type="lif"),
            "motor": PopulationIR(name="motor", size=4, population_type="lif"),
        },
        connections=[
            ConnectionIR(source="sensory", target="interneuron", weight=1.0),
            ConnectionIR(source="sensory", target="motor", weight=1.0),
        ],
        akida_hardware=AkidaHardwareIR(version="Akida2"),
    )

    with pytest.raises(
        AkidaMappingRejectedError,
        match="branching or ambiguous fan-out",
    ) as exc_info:
        map_network_ir_to_akida_representation(ir)

    assert exc_info.value.export_result.support_state == AkidaSupportState.EXPORTABLE_SCAFFOLD


def test_rejects_akida1_connection_properties() -> None:
    ir = _sequential_ir(akida_version="Akida1", include_property=True)

    with pytest.raises(AkidaMappingRejectedError, match="akida_connection_properties_on_v1"):
        map_network_ir_to_akida_representation(ir)


def test_rejects_learning_rules() -> None:
    ir = _sequential_ir()
    ir.learning_rules.append(
        LearningRuleIR(
            kind="stdp_learning",
            source="sensory",
            target="motor",
            provenance=[SourceProvenance(line=40, concept="stdp_learning")],
        )
    )

    with pytest.raises(AkidaMappingRejectedError, match="unsupported_learning_rule"):
        map_network_ir_to_akida_representation(ir)


def test_rejects_ambiguous_unscoped_connection_property() -> None:
    ir = NetworkIR(
        populations={
            "a": PopulationIR(name="a", size=8, population_type="lif"),
            "b": PopulationIR(name="b", size=8, population_type="lif"),
            "c": PopulationIR(name="c", size=8, population_type="lif"),
        },
        connections=[
            ConnectionIR(source="a", target="b", weight=1.0),
            ConnectionIR(source="b", target="c", weight=1.0),
        ],
        akida_hardware=AkidaHardwareIR(version="Akida2"),
        akida_connection_properties=[
            AkidaConnectionPropertyIR(
                block_type=AkidaBlockType.SPATIAL,
                provenance=[SourceProvenance(line=50, concept="akida_spatiotemporal")],
            )
        ],
    )

    with pytest.raises(AkidaMappingRejectedError, match="unscoped Akida connection properties"):
        map_network_ir_to_akida_representation(ir)
