import nir
import pytest

from neurocnl.export.sinabs_exporter import export_sinabs
from neurocnl.ir.types import NetworkIR


def test_export_sinabs_nir_deprecation_warning() -> None:
    """Verify that passing an NIRGraph raises a DeprecationWarning."""
    graph = nir.NIRGraph(nodes={}, edges=[])

    with pytest.warns(
        DeprecationWarning, match="Exporting sinabs via NIRGraph is deprecated"
    ):
        result = export_sinabs(graph)

    # The deprecated NIR path's generated `build_model` takes a `num_timesteps`
    # kwarg (needed to reconstruct the sinabs `Network` for inference), unlike
    # the direct-from-NetworkIR path's zero-arg `build_model()`.
    assert "def build_model(num_timesteps=25):" in result


def test_export_sinabs_network_ir() -> None:
    """Verify that passing a NetworkIR directly uses the new direct approach."""
    ir = NetworkIR()

    result = export_sinabs(ir)

    # Check that it returns the string output expected for NetworkIR
    assert "auto-generated directly from NeuroCNL IR" in result
    assert "def build_model():" in result


def test_export_sinabs_branching_fails_at_export_time() -> None:
    """Branching NetworkIR must raise NotImplementedError at export time, not in generated code."""
    from neurocnl.ir.types import ConnectionIR, PopulationIR

    ir = NetworkIR()
    ir.populations["src"] = PopulationIR(name="src", population_type="lif")
    ir.populations["dst_a"] = PopulationIR(name="dst_a", population_type="lif")
    ir.populations["dst_b"] = PopulationIR(name="dst_b", population_type="lif")
    ir.connections.append(ConnectionIR(source="src", target="dst_a", weight=1.0))
    ir.connections.append(ConnectionIR(source="src", target="dst_b", weight=1.0))

    with pytest.raises(NotImplementedError, match="Branching topology"):
        export_sinabs(ir)
