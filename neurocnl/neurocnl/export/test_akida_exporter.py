"""Tests for the BrainChip Akida exporter."""

from __future__ import annotations

import pytest

from neurocnl.export.akida_exporter import export_akida
from neurocnl.ir.types import ConnectionIR, NetworkIR, PopulationIR


def _lif_network_ir() -> NetworkIR:
    populations = {
        "sensory": PopulationIR(
            name="sensory",
            size=8,
            role="sensory",
            population_type="lif",
            threshold=1.0,
            membrane_time_constant=10.0,
        ),
        "motor": PopulationIR(
            name="motor",
            size=4,
            role="motor",
            population_type="lif",
            threshold=0.5,
            membrane_time_constant=5.0,
        ),
    }
    connections = [
        ConnectionIR(source="sensory", target="motor", weight=1.0),
    ]
    return NetworkIR(populations=populations, connections=connections)


def test_export_akida_returns_mapped_network_dict() -> None:
    payload = export_akida(_lif_network_ir())

    assert payload["akida_version"] == "akida1"
    assert payload["input_population"] == "sensory"
    assert [population["id"] for population in payload["populations"]] == [
        "sensory",
        "motor",
    ]
    assert len(payload["connections"]) == 1


def test_export_akida_preserves_lif_threshold_and_tau_in_attributes() -> None:
    payload = export_akida(_lif_network_ir())

    sensory = next(p for p in payload["populations"] if p["id"] == "sensory")
    motor = next(p for p in payload["populations"] if p["id"] == "motor")

    assert sensory["attributes"]["lif_threshold"] == 1.0
    assert sensory["attributes"]["lif_tau_mem"] == 10.0
    assert motor["attributes"]["lif_threshold"] == 0.5
    assert motor["attributes"]["lif_tau_mem"] == 5.0


def test_export_akida_rejects_branching_topology() -> None:
    from neurocnl.mapping.akida_mapper import AkidaMappingRejectedError

    populations = {
        "src": PopulationIR(name="src", population_type="lif"),
        "dst_a": PopulationIR(name="dst_a", population_type="lif"),
        "dst_b": PopulationIR(name="dst_b", population_type="lif"),
    }
    connections = [
        ConnectionIR(source="src", target="dst_a", weight=1.0),
        ConnectionIR(source="src", target="dst_b", weight=1.0),
    ]
    ir = NetworkIR(populations=populations, connections=connections)

    with pytest.raises(AkidaMappingRejectedError, match="unsupported_topology"):
        export_akida(ir)
