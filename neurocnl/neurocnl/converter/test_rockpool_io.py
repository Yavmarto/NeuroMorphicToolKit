"""Tests for RockpoolIO direct converter."""

import pytest

pytest.importorskip("rockpool")

import numpy as np
import rockpool.nn.modules as rpm
from rockpool.nn.combinators import Sequential

from neurocnl.converter.rockpool_io import RockpoolIO
from neurocnl.ir.types import ConnectionIR, NetworkIR, PopulationIR, TimingDeclarationIR


def test_rockpool_io_from_neurocnl() -> None:
    """Test converting from NeuroCNL IR to Rockpool Sequential."""
    ir = NetworkIR(
        timing_declarations=[TimingDeclarationIR(kind="timestep", value=0.002, unit="s")],
        populations={
            "pop1": PopulationIR(
                name="pop1",
                size=10,
                population_type="lif",
                membrane_time_constant=0.02,
                threshold=1.5,
            ),
            "pop2": PopulationIR(
                name="pop2",
                size=5,
                population_type="expsyn",
                membrane_time_constant=0.03,
                threshold=2.0,
                attributes={"synapse_time_constant": 0.006},
            ),
        },
        connections=[
            ConnectionIR(source="pop1", target="pop2", weight=0.5),
        ],
    )

    converter = RockpoolIO()
    rp_model = converter.from_neurocnl(ir)

    assert hasattr(rp_model, "modules")

    # We should have LIF -> Linear -> ExpSyn
    modules = list(rp_model)
    assert len(modules) == 3

    # Pop1 - LIF
    lif = modules[0]
    assert isinstance(lif, rpm.LIF)
    assert lif.size_in == 10
    assert np.all(lif.tau_mem == pytest.approx(0.02))
    assert lif.dt == pytest.approx(0.002)

    # Connection - Linear
    linear = modules[1]
    assert isinstance(linear, rpm.Linear)
    assert linear.shape == (10, 5)
    assert np.all(linear.weight == pytest.approx(0.5))

    # Pop2 - ExpSyn
    expsyn = modules[2]
    assert isinstance(expsyn, rpm.ExpSyn)
    assert expsyn.size_in == 5
    assert np.all(expsyn.tau_mem == pytest.approx(0.03))
    assert np.all(expsyn.tau_syn == pytest.approx(0.006))
    assert expsyn.dt == pytest.approx(0.002)


def test_rockpool_io_to_neurocnl() -> None:
    """Test converting from Rockpool Sequential to NeuroCNL IR."""
    rp_model = Sequential(
        rpm.LIF(10),
        rpm.Linear(shape=(10, 5), weight=np.full((10, 5), 0.5)),
        rpm.ExpSyn(5),
    )

    rp_model[0].tau_mem = np.full((10,), 0.02)
    rp_model[0].threshold = np.full((10,), 1.5)

    rp_model[2].tau_mem = np.full((5,), 0.03)
    rp_model[2].tau_syn = np.full((5,), 0.006)
    rp_model[2].threshold = np.full((5,), 2.0)

    converter = RockpoolIO()
    ir = converter.to_neurocnl(rp_model, dt=0.001)  # type: ignore[attr-defined]  # pre-existing gap: RockpoolIO has no to_neurocnl

    assert isinstance(ir, NetworkIR)

    assert len(ir.timing_declarations) == 1
    assert ir.timing_declarations[0].value == pytest.approx(0.001)

    assert len(ir.populations) == 2
    assert "pop_0" in ir.populations
    assert "pop_1" in ir.populations

    pop0 = ir.populations["pop_0"]
    assert pop0.size == 10
    assert pop0.population_type == "lif"
    assert pop0.membrane_time_constant == pytest.approx(0.02)
    assert pop0.threshold == pytest.approx(1.5)

    pop2 = ir.populations["pop_1"]
    assert pop2.size == 5
    assert pop2.population_type == "expsyn"
    assert pop2.membrane_time_constant == pytest.approx(0.03)
    assert pop2.threshold == pytest.approx(2.0)
    assert pop2.attributes["synapse_time_constant"] == pytest.approx(0.006)

    assert len(ir.connections) == 1
    conn = ir.connections[0]
    assert conn.source == "pop_0"
    assert conn.target == "pop_1"
    assert conn.weight == pytest.approx(0.5)
