import nengo
import nir
import numpy as np
import pytest

from neurocnl.converter.brian2_io import Brian2IO
from neurocnl.converter.lava_io import LavaIO
from neurocnl.converter.nengo_io import NengoIO
from neurocnl.converter.pivot import ModelConverter
from neurocnl.converter.pynn_io import PyNNIO


@pytest.fixture
def nengo_model() -> nengo.Network:
    net = nengo.Network(label="test_net")
    with net:
        pre = nengo.Ensemble(20, 1, label="pre")
        post = nengo.Ensemble(20, 1, label="post")
        nengo.Connection(pre.neurons, post.neurons, transform=0.1)
    return net


@pytest.fixture
def converter() -> ModelConverter:
    c = ModelConverter()
    c.register_framework("nengo", NengoIO())
    c.register_framework("lava", LavaIO())
    c.register_framework("pynn", PyNNIO())
    c.register_framework("brian2", Brian2IO())
    return c


def test_nengo_to_lava(nengo_model: nengo.Network, converter: ModelConverter) -> None:
    lava_code = converter.convert(nengo_model, "nengo", "lava")
    assert isinstance(lava_code, str)
    assert "LIF" in lava_code
    assert "Dense" in lava_code
    assert "pre" in lava_code
    assert "post" in lava_code


def test_nengo_to_pynn(nengo_model: nengo.Network, converter: ModelConverter) -> None:
    pynn_code = converter.convert(nengo_model, "nengo", "pynn")
    assert isinstance(pynn_code, str)
    assert "sim.Population" in pynn_code
    assert "sim.Projection" in pynn_code
    assert "pre" in pynn_code
    assert "post" in pynn_code


def test_nengo_to_brian2(nengo_model: nengo.Network, converter: ModelConverter) -> None:
    brian2_code = converter.convert(nengo_model, "nengo", "brian2")
    assert isinstance(brian2_code, str)
    assert "NeuronGroup" in brian2_code
    assert "Synapses" in brian2_code
    assert "pre" in brian2_code
    assert "post" in brian2_code


def test_nengo_to_nengo_code(
    nengo_model: nengo.Network, converter: ModelConverter
) -> None:
    nengo_code = converter.convert(nengo_model, "nengo", "nengo")
    assert isinstance(nengo_code, str)
    assert "nengo.Network" in nengo_code
    assert "nengo.Ensemble" in nengo_code
    assert "pre" in nengo_code
    assert "post" in nengo_code


def test_validation_warning(
    nengo_model: nengo.Network, converter: ModelConverter
) -> None:
    # Test with a dummy network
    with nengo.Network() as net:
        pass

    # Validation should add a warning but not necessarily raise an exception
    converter.convert(net, "nengo", "lava")
    assert any("Validation check failed" in w for w in converter.warnings)


def test_importers_basic(converter: ModelConverter) -> None:
    # Create a mock NIR graph manually to test exporters from NIR
    nodes = {
        "pre": nir.LIF(
            tau=np.array([0.02]),
            v_threshold=np.array([1.0]),
            v_leak=np.array([0.0]),
            r=np.array([1.0]),
        ),
        "post": nir.LIF(
            tau=np.array([0.02]),
            v_threshold=np.array([1.0]),
            v_leak=np.array([0.0]),
            r=np.array([1.0]),
        ),
        "conn": nir.Linear(weight=np.array([[0.5]])),
    }
    edges = [("pre", "conn"), ("conn", "post")]
    graph = nir.NIRGraph(nodes=nodes, edges=edges)

    # Test Brian2 from NIR
    b2_code = converter.frameworks["brian2"].from_nir(graph)
    assert "NeuronGroup(1" in b2_code
    assert "Synapses" in b2_code

    # Test Lava from NIR
    lava_code = converter.frameworks["lava"].from_nir(graph)
    assert "LIF(shape=(1,)" in lava_code
    assert "Dense" in lava_code


def test_structural_validation(converter: ModelConverter) -> None:
    # Graph with zero neurons
    graph = nir.NIRGraph(nodes={"c": nir.Linear(weight=np.eye(1))}, edges=[])
    assert converter.validate_conversion(None, None, graph) is False
    assert any("contains no LIF nodes" in w for w in converter.warnings)

    # Graph with zero weights
    nodes = {
        "n": nir.LIF(
            tau=np.array([0.02]),
            v_threshold=np.array([1.0]),
            v_leak=np.array([0.0]),
            r=np.array([1.0]),
        ),
        "w": nir.Linear(weight=np.zeros((1, 1))),
    }
    graph = nir.NIRGraph(nodes=nodes, edges=[])
    converter.validate_conversion(None, None, graph)
    assert any("all-zero weights" in w for w in converter.warnings)
