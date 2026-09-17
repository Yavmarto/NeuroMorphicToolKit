import pytest

pytest.importorskip("torch")

import torch
import torch.nn as nn

from neurocnl.converter.sinabs_io import HAS_SINABS, SinabsIO
from neurocnl.ir.types import ConnectionIR, NetworkIR, PopulationIR, TimingDeclarationIR

if HAS_SINABS:
    import sinabs.layers as sl
    from sinabs.network import Network as SinabsNetwork

pytestmark = pytest.mark.skipif(not HAS_SINABS, reason="sinabs not installed")


def test_sinabs_io_from_neurocnl_lif() -> None:
    io = SinabsIO()
    ir = NetworkIR()
    ir.populations["pop_0"] = PopulationIR(
        name="pop_0", size=10, population_type="lif", membrane_time_constant=20.0
    )
    ir.timing_declarations.append(TimingDeclarationIR(kind="timestep", value=2.0))

    model = io.from_neurocnl(ir)
    assert isinstance(model, SinabsNetwork)

    # Extract the actual sequential model depending on sinabs internals
    seq = (
        model.spiking_model
        if hasattr(model, "spiking_model") and model.spiking_model is not None
        else getattr(model, "analog_model", getattr(model, "sequence", model))
    )

    assert len(list(seq.children())) == 1
    layer = list(seq.children())[0]
    assert isinstance(layer, sl.LIF)
    assert layer.tau_mem == 20.0
    # The record attribute or equivalent parameter is internal, check config or parameters if needed


def test_sinabs_io_from_neurocnl_iaf_expleak() -> None:
    io = SinabsIO()
    ir = NetworkIR()
    ir.populations["pop_iaf"] = PopulationIR(name="pop_iaf", size=10, population_type="iaf")
    ir.populations["pop_expleak"] = PopulationIR(
        name="pop_expleak",
        size=10,
        population_type="expleak",
        membrane_time_constant=15.0,
    )

    model = io.from_neurocnl(ir)
    seq = (
        model.spiking_model
        if hasattr(model, "spiking_model") and model.spiking_model is not None
        else getattr(model, "analog_model", getattr(model, "sequence", model))
    )

    children = list(seq.children())
    assert len(children) == 2
    # In a network without connections, the order of iteration over populations is kept
    # but we should just check the types present
    types = [type(c) for c in children]
    assert sl.IAF in types
    assert sl.ExpLeak in types

    for child in children:
        if isinstance(child, sl.ExpLeak):
            assert child.tau_mem == 15.0


def test_sinabs_io_from_neurocnl_connections() -> None:
    io = SinabsIO()
    ir = NetworkIR()
    ir.populations["pop_a"] = PopulationIR(name="pop_a", size=5, population_type="lif")
    ir.populations["pop_b"] = PopulationIR(name="pop_b", size=3, population_type="lif")
    # In sinabs/PyTorch, weight matrix for Linear(in_features, out_features) is out_features x in_features
    # Let's mock a weight as list of lists.
    weight_matrix = [[0.5] * 5 for _ in range(3)]
    ir.connections.append(ConnectionIR(source="pop_a", target="pop_b", weight=weight_matrix))

    model = io.from_neurocnl(ir)
    seq = (
        model.spiking_model
        if hasattr(model, "spiking_model") and model.spiking_model is not None
        else getattr(model, "analog_model", getattr(model, "sequence", model))
    )

    children = list(seq.children())

    # We expect Pop_a -> Connection -> Pop_b
    assert len(children) == 3
    assert isinstance(children[0], sl.LIF)
    assert isinstance(children[1], nn.Linear)
    assert isinstance(children[2], sl.LIF)

    linear = children[1]
    assert linear.in_features == 5
    assert linear.out_features == 3
    assert torch.allclose(linear.weight, torch.tensor(weight_matrix))


def test_sinabs_io_from_neurocnl_branching() -> None:
    io = SinabsIO()
    ir = NetworkIR()
    ir.populations["input"] = PopulationIR(name="input", size=4, population_type="lif")
    ir.populations["branch_a"] = PopulationIR(name="branch_a", size=2, population_type="lif")
    ir.populations["branch_b"] = PopulationIR(name="branch_b", size=2, population_type="iaf")
    ir.connections.append(ConnectionIR(source="input", target="branch_a", weight=1.0))
    ir.connections.append(ConnectionIR(source="input", target="branch_b", weight=0.5))

    model = io.from_neurocnl(ir)

    assert isinstance(model, SinabsNetwork)
    seq = (
        model.spiking_model
        if hasattr(model, "spiking_model") and model.spiking_model is not None
        else getattr(model, "analog_model", getattr(model, "sequence", model))
    )
    output = seq(torch.zeros(1, 1, 4))
    assert output.shape[-1] == 4


def test_sinabs_io_to_neurocnl() -> None:
    io = SinabsIO()

    seq = nn.Sequential(sl.LIF(tau_mem=10.0), nn.Linear(5, 3, bias=False), sl.IAF())
    # Mocking basic weight
    with torch.no_grad():
        # Set weights deterministically for easier check
        seq[1].weight.fill_(0.5)  # type: ignore[operator]

    model = SinabsNetwork(seq)

    ir = io.to_neurocnl(model)

    assert len(ir.populations) == 2
    assert ir.populations["pop_0"].population_type == "lif"
    assert ir.populations["pop_1"].population_type == "iaf"

    assert len(ir.connections) == 1
    conn = ir.connections[0]
    assert conn.source == "pop_0"
    assert conn.target == "pop_1"
    # Wait, the weight is a list of lists.
    import numpy as np

    assert np.allclose(np.array(conn.weight), 0.5)


def test_sinabs_simulation_forward_pass() -> None:
    """Manual validation gate step: convert 2-population LIF network, run one forward pass on CPU."""
    io = SinabsIO()
    ir = NetworkIR()
    ir.populations["pop_1"] = PopulationIR(name="pop_1", size=10, population_type="lif")
    ir.populations["pop_2"] = PopulationIR(name="pop_2", size=5, population_type="lif")
    ir.connections.append(ConnectionIR(source="pop_1", target="pop_2", weight=1.0))
    ir.timing_declarations.append(TimingDeclarationIR(kind="timestep", value=1.0))

    model = io.from_neurocnl(ir)

    # Batch size 2, Sequence length 1, Features 10
    input_tensor = torch.zeros(2, 1, 10)
    # Add some spikes to trigger forward pass correctly
    input_tensor[0, 0, 0] = 1.0

    # Forward pass
    # Note: to call SinabsNetwork as a module directly on spikes, we need from_model or equivalent.
    # We can just call analog_model if we instantiated it directly with Sequential of sl.* layers.
    # sinabs.network.Network calls self.spiking_model(), which we might not have initialized if we just passed Sequential.
    # Actually, if we constructed layers as sl.* and put them in Sequential, it IS a spiking model.
    seq = (
        model.spiking_model
        if hasattr(model, "spiking_model") and model.spiking_model is not None
        else getattr(model, "analog_model", getattr(model, "sequence", model))
    )
    output_tensor = seq(input_tensor)

    # Output could be varying due to model logic, let's just assert shape.
    # Depending on sinabs version and layer wrapper, output shape might be Batch x Features for single timestep
    # if seq is used directly without Time wrapper, or Batch x Time x Features.
    assert output_tensor.shape == (2, 1, 5) or output_tensor.shape == (2, 5)
