import pytest
from nmtk_sdk import CustomNode, param, port


class _ValidNode(CustomNode):
    name = "Valid Neuron"
    category = "neurons"
    canvases = ["model", "training"]
    frameworks = ["nengo"]

    @param(type="float", default=0.02, unit="s", label="Tau m")
    def tau_m(self): ...

    @port(direction="input", label="Spikes in")
    def spikes_in(self): ...

    def to_nengo(self, params: dict) -> object:
        return object()


def test_required_attrs_present():
    assert _ValidNode.name == "Valid Neuron"
    assert _ValidNode.category == "neurons"
    assert _ValidNode.canvases == ["model", "training"]
    assert _ValidNode.frameworks == ["nengo"]


def test_param_metadata_attached():
    meta = _ValidNode.tau_m._param_meta
    assert meta["type"] == "float"
    assert meta["default"] == 0.02
    assert meta["unit"] == "s"
    assert meta["label"] == "Tau m"
    assert meta["name"] == "tau_m"


def test_port_metadata_attached():
    meta = _ValidNode.spikes_in._port_meta
    assert meta["direction"] == "input"
    assert meta["label"] == "Spikes in"
    assert meta["id"] == "spikes_in"


def test_missing_name_raises():
    with pytest.raises(TypeError, match="name"):

        class BadNode(CustomNode):
            category = "neurons"
            canvases = ["model"]
            frameworks = ["nengo"]


def test_missing_canvases_raises():
    with pytest.raises(TypeError, match="canvases"):

        class BadNode(CustomNode):
            name = "Bad"
            category = "neurons"
            frameworks = ["nengo"]


def test_to_framework_not_implemented_raises():
    node = _ValidNode()
    with pytest.raises(NotImplementedError):
        node.to_norse({})
