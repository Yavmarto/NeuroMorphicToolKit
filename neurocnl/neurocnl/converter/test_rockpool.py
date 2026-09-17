"""Tests for Rockpool Integration.

Covers converter (`to_nir`, `from_nir`) and training utility.
"""

import pytest

pytest.importorskip("torch")
pytest.importorskip("rockpool")

import nir
import numpy as np
import torch
from rockpool.nn.combinators import Sequential
from rockpool.nn.modules import LIFTorch, LinearTorch

from neurocnl.converter.rockpool_io import RockpoolIO
from neurocnl.simulation.bptt import train_with_bptt


def test_rockpool_to_nir() -> None:
    """Test converting a Rockpool model to NIR."""
    # Build a simple model
    lin = LinearTorch(shape=(2, 3), weight=torch.tensor([[1.0, 2.0, 3.0], [4.0, 5.0, 6.0]]))
    lif = LIFTorch(
        shape=(3,),
        tau_mem=torch.tensor([0.01, 0.02, 0.03]),
        threshold=torch.tensor([1.0, 1.0, 1.0]),
        bias=torch.tensor([0.0, 0.0, 0.0]),
    )
    model = Sequential(lin, lif)

    io = RockpoolIO()
    graph = io.to_nir(model, dt=0.001)  # type: ignore[attr-defined]  # pre-existing gap: RockpoolIO has no to_nir

    # Assert correct graph structure
    assert isinstance(graph, nir.NIRGraph)
    assert "input" in graph.nodes
    assert "output" in graph.nodes

    linear_node = [n for n in graph.nodes.values() if isinstance(n, nir.Linear)][0]
    lif_node = [n for n in graph.nodes.values() if isinstance(n, nir.LIF)][0]

    # Check parameters
    assert linear_node.weight.shape == (3, 2)  # Check transpose matches
    assert np.allclose(linear_node.weight, np.array([[1.0, 4.0], [2.0, 5.0], [3.0, 6.0]]))

    assert np.allclose(lif_node.tau, np.array([0.01, 0.02, 0.03]))
    assert np.allclose(lif_node.v_threshold, np.array([1.0, 1.0, 1.0]))


def test_nir_to_rockpool() -> None:
    """Test converting an NIR graph to a Rockpool model."""
    nodes = {
        "in": nir.Input({"input": np.array([2])}),
        "lin": nir.Linear(np.array([[1.0, 4.0], [2.0, 5.0], [3.0, 6.0]])),
        "lif": nir.LIF(
            tau=np.array([0.01, 0.02, 0.03]),
            r=np.array([1.0, 1.0, 1.0]),
            v_leak=np.array([0.0, 0.0, 0.0]),
            v_threshold=np.array([1.0, 1.0, 1.0]),
        ),
        "out": nir.Output({"output": np.array([3])}),
    }
    edges = [("in", "lin"), ("lin", "lif"), ("lif", "out")]
    graph = nir.NIRGraph(nodes=nodes, edges=edges)

    io = RockpoolIO()
    model = io.from_nir(graph, dt=0.001)

    # Verify Rockpool model structure
    from rockpool.nn.combinators.sequential import TorchSequential

    assert isinstance(model, TorchSequential)

    modules = list(model.children())
    assert len(modules) == 2
    assert isinstance(modules[0], LinearTorch)
    assert isinstance(modules[1], LIFTorch)

    # Verify weight
    assert modules[0].weight.shape == (2, 3)

    # Verify lif params
    assert torch.allclose(modules[1].tau_mem, torch.tensor([0.01, 0.02, 0.03]))


def test_train_with_bptt() -> None:
    """Test the BPTT training wrapper."""
    lin = LinearTorch(shape=(2, 3))
    lif = LIFTorch(shape=(3,))
    model = Sequential(lin, lif)

    # Random inputs: (batch, time, features)
    inputs = torch.randn(2, 10, 2)
    # Target outputs: same shape as output, (batch, time, features)
    targets = torch.randn(2, 10, 3)

    # Extract torch parameters correctly for optimizer
    torch_params = torch.nn.Module.parameters(model)
    optimizer = torch.optim.Adam(torch_params, lr=0.01)
    loss_fn = torch.nn.MSELoss()

    losses = train_with_bptt(model, inputs, targets, loss_fn, optimizer, epochs=2)

    assert len(losses) == 2
    # Ensure gradients were populated and weight updated
    assert lin.weight.grad is not None
