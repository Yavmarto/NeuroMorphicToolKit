import ast

import pytest

try:
    import sinabs.layers as sl

    HAS_SINABS = True
except ImportError:
    HAS_SINABS = False

import nir
import numpy as np

pytest.importorskip("torch")
import torch.nn as nn

from neurocnl.converter.sinabs_io import SinabsIO


@pytest.mark.skipif(not HAS_SINABS, reason="sinabs not installed")
def test_sinabs_to_nir():
    """Test conversion of sinabs sequential model to NIR."""
    io = SinabsIO()
    model = nn.Sequential(nn.Linear(2, 2, bias=False), sl.LIF(tau_mem=10.0))

    nir_graph = io.to_nir(model)
    assert isinstance(nir_graph, nir.NIRGraph)

    nodes = nir_graph.nodes
    edges = nir_graph.edges

    assert len(nodes) == 2
    assert "layer_0" in nodes
    assert "layer_1" in nodes

    assert isinstance(nodes["layer_0"], nir.Linear)
    assert isinstance(nodes["layer_1"], nir.LIF)
    assert nodes["layer_1"].tau == np.array([10.0])

    assert len(edges) == 1
    assert edges[0] == ("layer_0", "layer_1")


def test_nir_to_sinabs():
    """Test conversion of NIR graph to sinabs model code string."""
    io = SinabsIO()

    nodes = {
        "l1": nir.Linear(weight=np.array([[1.0, 2.0]])),
        "lif1": nir.LIF(
            tau=np.array([10.0]),
            r=np.array([1.0]),
            v_leak=np.array([0.0]),
            v_threshold=np.array([1.0]),
        ),
    }
    edges = [("l1", "lif1")]
    graph = nir.NIRGraph(nodes=nodes, edges=edges)

    code = io.from_nir(graph)

    # from_nir returns a Python code string with real layer definitions
    assert isinstance(code, str)
    assert "def build_model" in code
    assert "import torch" in code
    assert "nir.Affine" in code, "expected exact Linear weights in the embedded NIR graph"
    assert "nir.LIF" in code, "expected effective LIF parameters in the embedded NIR graph"
    assert "sinabs_nir.from_nir" in code
    assert "spiking_model=spiking_model" in code
    assert "module.reset_fn = MembraneReset()" in code
    assert "StudioSinabsInference" in code
    assert "num_timesteps=25" in code
    assert "reset_states" in code
    assert "net = build_model()" in code
    assert "batch_size * self.num_timesteps" in code
    ast.parse(code)


def test_nir_to_sinabs_branching_fails_closed():
    """Branching NIR graph must fail at conversion time, not produce broken output."""
    io = SinabsIO()

    nodes = {
        "src": nir.IF(r=np.array([1.0]), v_threshold=np.array([1.0])),
        "dst_a": nir.IF(r=np.array([1.0]), v_threshold=np.array([1.0])),
        "dst_b": nir.IF(r=np.array([1.0]), v_threshold=np.array([1.0])),
    }
    edges = [("src", "dst_a"), ("src", "dst_b")]
    graph = nir.NIRGraph(nodes=nodes, edges=edges)

    with pytest.raises(NotImplementedError, match="Branching/merging NIR graph"):
        io.from_nir(graph)
