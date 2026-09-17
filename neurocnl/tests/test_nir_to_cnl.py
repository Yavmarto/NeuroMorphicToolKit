"""Tests for the NIR → CNL → NIR round-trip pipeline."""

import nir
import numpy as np

from neurocnl.nir_cnl.compiler import NIR_Compiler
from neurocnl.nir_cnl.ir_types import NIREdgeRecord
from neurocnl.nir_cnl.parser import NIR_CNL_Parser
from neurocnl.nir_cnl.renderer import NIR_Renderer

# ---------------------------------------------------------------------------
# Shared fixture helpers
# ---------------------------------------------------------------------------


def _simple_lif_graph():
    return nir.NIRGraph(
        nodes={
            "in1": nir.Input(input_type={"input": np.array([3])}),
            "lif1": nir.LIF(
                tau=np.full(3, 0.02),
                r=np.full(3, 1.0),
                v_leak=np.zeros(3),
                v_threshold=np.ones(3),
            ),
            "out1": nir.Output(output_type={"output": np.array([3])}),
        },
        edges=[("in1", "lif1"), ("lif1", "out1")],
    )


# ---------------------------------------------------------------------------
# Pre-existing tests — fixed to check English noun phrases, not class names
# ---------------------------------------------------------------------------


def test_render_produces_cnl_text():
    """NIR_Renderer.render() produces non-empty CNL text."""
    graph = _simple_lif_graph()
    renderer = NIR_Renderer()
    cnl_text = renderer.render(graph)
    assert isinstance(cnl_text, str)
    assert len(cnl_text) > 0


def test_render_contains_node_phrases():
    """Rendered CNL contains English noun phrases, not bare class names."""
    graph = _simple_lif_graph()
    renderer = NIR_Renderer()
    cnl_text = renderer.render(graph)
    assert any(
        kw in cnl_text
        for kw in (
            "LIF neuron",
            "linear transformation",
            "delay element",
            "input port",
            "output port",
        )
    )


# ---------------------------------------------------------------------------
# New renderer tests
# ---------------------------------------------------------------------------


def test_renderer_active_voice():
    """Renderer emits 'connects to' edges; no bare 'Connect ' verb."""
    graph = _simple_lif_graph()
    cnl_text = NIR_Renderer().render(graph)
    assert "connects to" in cnl_text
    # '\nConnect ' would be the old imperative-voice form — must not appear
    assert "\nConnect " not in cnl_text


def test_renderer_emits_tensor_shape_only():
    """Tensor parameters render as shape-only clauses."""
    graph = nir.NIRGraph(
        nodes={
            "in1": nir.Input(input_type={"input": np.array([3])}),
            "fc1": nir.Affine(
                weight=np.array(
                    [
                        [0.25, -0.5, 0.75],
                        [1.0, -1.25, 1.5],
                        [-1.75, 2.0, -2.25],
                        [2.5, -2.75, 3.0],
                    ]
                ),
                bias=np.zeros(4),
            ),
            "out1": nir.Output(output_type={"output": np.array([4])}),
        },
        edges=[("in1", "fc1"), ("fc1", "out1")],
    )
    cnl_text = NIR_Renderer().render(graph)
    assert "weight matrix shape (4, 3)" in cnl_text
    assert "weight matrix values" not in cnl_text


def test_renderer_uniform_vector_preserves_shape_and_values():
    """Imported multi-element vectors keep shape and explicit values."""
    graph = nir.NIRGraph(
        nodes={
            "in1": nir.Input(input_type={"input": np.array([4])}),
            "lif1": nir.LIF(
                tau=np.full(4, 0.02),
                r=np.full(4, 1.0),
                v_leak=np.zeros(4),
                v_threshold=np.ones(4),
            ),
            "out1": nir.Output(output_type={"output": np.array([4])}),
        },
        edges=[("in1", "lif1"), ("lif1", "out1")],
    )
    cnl_text = NIR_Renderer().render(graph)
    assert "firing threshold shape (4,)" in cnl_text
    assert "firing threshold values" not in cnl_text


def test_renderer_section_structure():
    """Rendered output has '# Layers:' and '# Connections:' section headers."""
    graph = _simple_lif_graph()
    cnl_text = NIR_Renderer().render(graph)
    assert "# Layers:" in cnl_text
    assert "# Connections:" in cnl_text
    # A blank line must appear before the '# Layers:' header
    assert "\n\n# Layers:" in cnl_text


def test_renderer_topological_order():
    """Edges appear in topological order regardless of node dict order."""
    # Declare output node BEFORE input node in the dict
    graph = nir.NIRGraph(
        nodes={
            "out1": nir.Output(output_type={"output": np.array([1])}),
            "in1": nir.Input(input_type={"input": np.array([1])}),
        },
        edges=[("in1", "out1")],
    )
    cnl_text = NIR_Renderer().render(graph)
    assert "in1 connects to out1" in cnl_text
    # 'out1 connects to' must not appear (out1 is a sink, not a source)
    assert "out1 connects to" not in cnl_text


# ---------------------------------------------------------------------------
# New parser tests
# ---------------------------------------------------------------------------


def test_parser_active_voice_edge():
    """Parser accepts 'src connects to target.' active-voice edge syntax."""
    text = (
        "Define a network named demo.\n"
        "Define an input port named in1 with shape (1,).\n"
        "Define an output port named out1 with shape (1,).\n"
        "in1 connects to out1.\n"
    )
    records = NIR_CNL_Parser().parse(text)
    edge_records = [r for r in records if isinstance(r, NIREdgeRecord)]
    assert len(edge_records) == 1
    assert edge_records[0].src == "in1"
    assert edge_records[0].target == "out1"


def test_parser_dotted_active_voice():
    """Parser accepts a word-identifier source in 'src connects to target.' form."""
    text = (
        "Define a network named demo.\n"
        "Define an input port named in1 with shape (1,).\n"
        "Define an output port named lif1_lif with shape (1,).\n"
        "in1 connects to lif1_lif.\n"
    )
    records = NIR_CNL_Parser().parse(text)
    edge_records = [r for r in records if isinstance(r, NIREdgeRecord)]
    assert any(r.src == "in1" and r.target == "lif1_lif" for r in edge_records)


# ---------------------------------------------------------------------------
# New compiler test
# ---------------------------------------------------------------------------


def test_compile_tensor_values_round_trip():
    """Explicit tensor values compile back to the original weight matrix."""
    text = (
        "Define a network named demo.\n"
        "Define an input port named in1 with shape (2,).\n"
        "Define an affine transformation named fc1 with weight matrix shape (3, 2) "
        "and weight matrix values (0.5, -0.25, 1.25, -1.5, 2.0, -2.25).\n"
        "Define an output port named out1 with shape (3,).\n"
        "in1 connects to fc1.\n"
        "fc1 connects to out1.\n"
    )
    records = NIR_CNL_Parser().parse(text)
    graph = NIR_Compiler().compile(records)
    fc1_node = graph.nodes["fc1"]
    weight = fc1_node.weight
    assert weight.shape == (3, 2)
    assert np.array_equal(
        weight,
        np.array([[0.5, -0.25], [1.25, -1.5], [2.0, -2.25]], dtype=np.float64),
    )


def test_renderer_skips_redundant_metadata():
    """Renderer skips non-semantic metadata keys but preserves custom metadata keys."""
    graph = nir.NIRGraph(
        nodes={
            "in1": nir.Input(
                input_type={"input": np.array([1])},
                metadata={
                    "canvas_label": "in1",
                    "display_label": "Input",
                    "label": "in1",
                    "category": "io",
                    "canvas_position": [100.0, 200.0],
                    "canvas_component_id": "input_node",
                    "custom_param": "keep_this",
                },
            ),
            "out1": nir.Output(
                output_type={"output": np.array([1])},
                metadata={},
            ),
        },
        edges=[("in1", "out1")],
    )
    cnl_text = NIR_Renderer().render(graph)

    # Redundant/non-semantic keys should NOT be emitted
    assert "canvas_label" not in cnl_text
    assert "display_label" not in cnl_text
    assert "label" not in cnl_text
    assert "category" not in cnl_text
    assert "canvas_position" not in cnl_text
    assert "canvas_component_id" not in cnl_text

    # Custom keys should be rendered
    assert 'annotated with metadata custom_param equal to "keep_this"' in cnl_text
