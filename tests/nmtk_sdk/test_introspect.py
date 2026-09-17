from typing import ClassVar

from neurosim.contracts.design_contracts import ComponentBlock

from nmtk_sdk import CustomNode, param, port
from nmtk_sdk.introspect import introspect_node


class _SampleNode(CustomNode):
    name = "Sample Neuron"
    category = "neurons"
    canvases: ClassVar[list[str]] = ["model", "training"]
    frameworks: ClassVar[list[str]] = ["nengo"]
    description = "A test neuron"
    author = "test_user"
    version = "1.2.0"

    @param(type="float", default=0.02, unit="s", label="Tau m", min=0.001, max=1.0)
    def tau_m(self): ...

    @param(type="int", default=10, label="Size")
    def size(self): ...

    @port(direction="input", label="Spikes in")
    def spikes_in(self): ...

    @port(direction="output", label="Spikes out")
    def spikes_out(self): ...

    def to_nengo(self, params): ...


def test_returns_component_block():
    cb = introspect_node(_SampleNode)
    assert isinstance(cb, ComponentBlock)


def test_is_custom_true():
    cb = introspect_node(_SampleNode)
    assert cb.is_custom is True


def test_metadata():
    cb = introspect_node(_SampleNode)
    assert cb.name == "Sample Neuron"
    assert cb.category == "neurons"
    assert cb.description == "A test neuron"
    assert cb.canvas_contexts == ["model", "training"]
    assert cb.supported_frameworks == ["nengo"]
    assert cb.author == "test_user"
    assert cb.version == "1.2.0"


def test_parameters():
    cb = introspect_node(_SampleNode)
    names = [p.name for p in cb.parameters]
    assert "tau_m" in names
    assert "size" in names
    tau = next(p for p in cb.parameters if p.name == "tau_m")
    assert tau.type == "float"
    assert tau.default == 0.02
    assert tau.unit == "s"
    assert tau.min == 0.001


def test_ports():
    cb = introspect_node(_SampleNode)
    ids = [p.id for p in cb.ports]
    assert "spikes_in" in ids
    assert "spikes_out" in ids
    inp = next(p for p in cb.ports if p.id == "spikes_in")
    assert inp.direction == "input"


def test_id_stable_across_calls():
    assert introspect_node(_SampleNode).id == introspect_node(_SampleNode).id


def test_id_contains_author_and_slug():
    cb = introspect_node(_SampleNode)
    assert "test_user" in cb.id
    assert "sample_neuron" in cb.id


def test_cnl_template_empty():
    cb = introspect_node(_SampleNode)
    assert cb.cnl_template == ""


def test_source_path_stored():
    cb = introspect_node(_SampleNode, source_path="/tmp/my_node.py")
    assert cb.source_path == "/tmp/my_node.py"
    assert cb.source_filename == "my_node.py"
    assert cb.source_available is True
    assert "source_path" not in cb.model_dump()


def test_declared_identity_and_base_metadata_are_preserved():
    class StableNode(_SampleNode):
        node_id = "custom_stable_a1b2c3d4"
        base_component_id = "lif_population"
        base_nir_type = "nir.LIF"

    cb = introspect_node(StableNode)

    assert cb.id == "custom_stable_a1b2c3d4"
    assert cb.base_component_id == "lif_population"
    assert cb.base_nir_type == "nir.LIF"


def test_pipeline_base_metadata_is_preserved():
    class PipelineNode(_SampleNode):
        node_id = "custom_adam_a1b2c3d4"
        base_pipeline_type = "adamOptimiser"

    cb = introspect_node(PipelineNode)

    assert cb.base_pipeline_type == "adamOptimiser"
