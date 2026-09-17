"""Tests for execution of generated Lava code in Loihi2SimCfg."""

import nengo
import pytest

pytest.importorskip("lava")

from neurocnl.export.lava_exporter import export_lava
from neurocnl.ir.types import NetworkIR, TimingDeclarationIR


@pytest.mark.lava_sim
def test_lava_sim_execution() -> None:
    """Test that generated Lava code successfully runs under Loihi2SimCfg."""
    net = nengo.Network()
    with net:
        pop1 = nengo.Ensemble(10, 1, label="sensory")
        pop2 = nengo.Ensemble(10, 1, label="motor")
        nengo.Connection(pop1, pop2, transform=0.5)

    ir = NetworkIR()
    ir.timing_declarations.append(
        TimingDeclarationIR(kind="simulation_time", value=0.05, unit="seconds")
    )

    code = export_lava(net, hw_mode=False, ir=ir)

    assert "RunSteps(num_steps=50)" in code

    # Execute the generated code
    namespace: dict[str, object] = {}
    exec(code, namespace)

    # Check variables were created in the namespace
    assert "sensory" in namespace
    assert "motor" in namespace
    assert "conn_sensory_to_motor" in namespace


@pytest.mark.loihi_hw
def test_lava_hw_path() -> None:
    """Placeholder for hardware path tests requiring Loihi 2."""
    pytest.skip("Loihi 2 hardware not available in CI environment.")
