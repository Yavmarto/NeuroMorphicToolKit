"""Per-Primitive snapshot tests for the NIR-Native CNL renderer.

For each of the 18 documented Primitives, this module builds one
canonical instance with deterministic parameter values and asserts
that :class:`NIR_Renderer` emits the canonical sentence form documented
in ``.kiro/specs/nir-native-cnl/design.md`` § "Parameter-Phrase Mapping
Table".

These are *example tests* (not property tests). They pin the
renderer's surface text per Requirement 2.1 / 3.4 and serve as a
quick-feedback regression for any grammar-table edit that changes a
canonical phrase.

_Validates: Requirements 2.1, 3.4_
"""

from __future__ import annotations

import nir
import numpy as np

from neurocnl.nir_cnl.renderer import NIR_Renderer


def _render_only_node(node_name: str, node: nir.NIRNode) -> str:
    """Render a graph containing only *node*, return the matching sentence.

    The renderer always emits the network header
    ``Define a network named graph.`` plus zero or more comment lines
    after the node sentence; this helper extracts the single
    ``Define ... named <name> ...`` line and returns it as a string.
    """
    graph = nir.NIRGraph(nodes={node_name: node}, edges=[], type_check=False)
    text = NIR_Renderer().render(graph)
    for line in text.splitlines():
        if line.startswith("Define ") and f"named {node_name}" in line:
            return line
    raise AssertionError(f"No 'Define ... named {node_name}' line found in:\n{text}")


# ---------------------------------------------------------------------------
# Per-Primitive snapshot tests
# ---------------------------------------------------------------------------


def test_render_input() -> None:
    sentence = _render_only_node("in1", nir.Input(input_type=np.array([1, 28, 28])))
    assert sentence == "Define an input port named in1 with shape (1, 28, 28)."


def test_render_output() -> None:
    sentence = _render_only_node("out1", nir.Output(output_type=np.array([10])))
    assert sentence == "Define an output port named out1 with shape (10,)."


def test_render_if() -> None:
    sentence = _render_only_node(
        "if1", nir.IF(r=np.array([1.0]), v_threshold=np.array([1.0]))
    )
    assert sentence == (
        "Define an IF neuron named if1 with resistance 1.0 and firing threshold 1.0."
    )


def test_render_lif() -> None:
    sentence = _render_only_node(
        "lif1",
        nir.LIF(
            tau=np.array([0.02]),
            r=np.array([1.0]),
            v_leak=np.array([0.0]),
            v_threshold=np.array([1.0]),
        ),
    )
    assert sentence == (
        "Define a LIF neuron named lif1 "
        "with time constant 0.02, resistance 1.0, leak voltage 0.0, "
        "and firing threshold 1.0."
    )


def test_render_li() -> None:
    sentence = _render_only_node(
        "li1",
        nir.LI(
            tau=np.array([0.02]),
            r=np.array([1.0]),
            v_leak=np.array([0.0]),
        ),
    )
    assert sentence == (
        "Define a LI neuron named li1 "
        "with time constant 0.02, resistance 1.0, and leak voltage 0.0."
    )


def test_render_cubalif() -> None:
    sentence = _render_only_node(
        "cuba1",
        nir.CubaLIF(
            tau_syn=np.array([0.005]),
            tau_mem=np.array([0.02]),
            r=np.array([1.0]),
            v_leak=np.array([0.0]),
            v_threshold=np.array([1.0]),
            w_in=np.array([1.0]),
        ),
    )
    assert sentence == (
        "Define a CubaLIF neuron named cuba1 "
        "with synaptic time constant 0.005, membrane time constant 0.02, "
        "resistance 1.0, leak voltage 0.0, firing threshold 1.0, "
        "and input weight 1.0."
    )


def test_render_cubali() -> None:
    sentence = _render_only_node(
        "cubali1",
        nir.CubaLI(
            tau_syn=np.array([0.005]),
            tau_mem=np.array([0.02]),
            r=np.array([1.0]),
            v_leak=np.array([0.0]),
            w_in=np.array([1.0]),
        ),
    )
    assert sentence == (
        "Define a CubaLI neuron named cubali1 "
        "with synaptic time constant 0.005, membrane time constant 0.02, "
        "resistance 1.0, leak voltage 0.0, and input weight 1.0."
    )


def test_render_i() -> None:
    sentence = _render_only_node("i1", nir.I(r=np.array([1.0])))
    assert sentence == "Define an I neuron named i1 with resistance 1.0."


def test_render_linear() -> None:
    weight = np.array([[0.5, 0.7, 0.1], [0.9, -0.2, 0.4]])
    sentence = _render_only_node("fc1", nir.Linear(weight=weight))
    assert sentence == (
        "Define a linear transformation named fc1 with weight matrix shape (2, 3)."
    )


def test_render_affine() -> None:
    weight = np.array([[0.5, 0.7, 0.1], [0.9, -0.2, 0.4]])
    bias = np.array([0.0, 0.0])
    sentence = _render_only_node("aff1", nir.Affine(weight=weight, bias=bias))
    # Vector-kind params with more than one element render shape-only — exact
    # values are dropped to keep CNL compact (see _emit_param_clauses' "vector"
    # branch), same policy as tensor-kind params like the weight matrix above.
    assert sentence == (
        "Define an affine transformation named aff1 "
        "with weight matrix shape (2, 3) and bias vector shape (2,)."
    )


def test_render_scale() -> None:
    sentence = _render_only_node("s1", nir.Scale(scale=np.array([2.5])))
    assert sentence == "Define a scale transformation named s1 with scale factor 2.5."


def test_render_conv1d() -> None:
    weight = np.zeros((1, 1, 1), dtype=np.float64)
    weight[0, 0, 0] = 1.0
    bias = np.array([0.0])
    sentence = _render_only_node(
        "c1",
        nir.Conv1d(
            input_shape=4,
            weight=weight,
            stride=1,
            padding=0,
            dilation=1,
            groups=1,
            bias=bias,
        ),
    )
    assert sentence.startswith(
        "Define a 1D convolution layer named c1 "
        "with weight kernel shape (1, 1, 1), "
        "bias vector 0.0, stride (1,), padding (0,), "
        "dilation (1,), groups 1, and input length 4."
    )


def test_render_conv2d() -> None:
    weight = np.zeros((1, 1, 1, 1), dtype=np.float64)
    weight[0, 0, 0, 0] = 1.0
    bias = np.array([0.0])
    sentence = _render_only_node(
        "c2",
        nir.Conv2d(
            input_shape=(4, 4),
            weight=weight,
            stride=(1, 1),
            padding=(0, 0),
            dilation=(1, 1),
            groups=1,
            bias=bias,
        ),
    )
    assert "2D convolution layer named c2" in sentence
    assert "weight kernel shape (1, 1, 1, 1)" in sentence
    assert "stride (1, 1)" in sentence
    assert "input height and width (4, 4)" in sentence


def test_render_avgpool2d() -> None:
    sentence = _render_only_node(
        "avgp1",
        nir.AvgPool2d(
            kernel_size=np.asarray([2, 2], dtype=int),
            stride=np.asarray([2, 2], dtype=int),
            padding=np.asarray([0, 0], dtype=int),
        ),
    )
    assert sentence == (
        "Define a 2D average pooling layer named avgp1 "
        "with kernel size (2, 2), stride (2, 2), and padding (0, 0)."
    )


def test_render_sumpool2d() -> None:
    sentence = _render_only_node(
        "sump1",
        nir.SumPool2d(
            kernel_size=np.asarray([2, 2], dtype=int),
            stride=np.asarray([2, 2], dtype=int),
            padding=np.asarray([0, 0], dtype=int),
        ),
    )
    assert sentence == (
        "Define a 2D sum pooling layer named sump1 "
        "with kernel size (2, 2), stride (2, 2), and padding (0, 0)."
    )


def test_render_flatten() -> None:
    sentence = _render_only_node(
        "fl1",
        nir.Flatten(
            input_type={"input": np.asarray([4], dtype=int)},
            start_dim=0,
            end_dim=-1,
        ),
    )
    assert "Define a flatten layer named fl1 with start dimension 0" in sentence


def test_render_delay() -> None:
    sentence = _render_only_node("d1", nir.Delay(delay=np.array([0.001])))
    assert sentence == "Define a delay element named d1 with delay value 0.001."


def test_render_threshold() -> None:
    sentence = _render_only_node("th1", nir.Threshold(threshold=np.array([0.5])))
    assert sentence == "Define a threshold element named th1 with threshold value 0.5."


# ---------------------------------------------------------------------------
# CNL-Studio-internal snnTorch neuron extensions
#
# Regression coverage for the bug where these four types had full
# ``notebook.py`` codegen support but no grammar-table entry: the
# renderer silently commented them (and every edge touching them) out
# of the CNL text instead of rendering a real sentence, so a canvas-
# built network re-parsed from that text lost its neuron layers
# entirely. See ``current tasks/2026-07-15/`` for the full writeup.
# ---------------------------------------------------------------------------


def test_render_synaptic() -> None:
    from neurocnl.runtime.cnl_nodes import Synaptic as CnlSynaptic

    sentence = _render_only_node(
        "syn1",
        CnlSynaptic(n_neurons=40, alpha=0.9, beta=0.8, threshold=1.0),
    )
    assert sentence == (
        "Define a Synaptic neuron named syn1 with neuron count 40, "
        "synaptic decay 0.9, membrane decay 0.8, and firing threshold 1.0."
    )


def test_render_rsynaptic() -> None:
    from neurocnl.runtime.cnl_nodes import RSynaptic as CnlRSynaptic

    sentence = _render_only_node(
        "rsyn1",
        CnlRSynaptic(n_neurons=16, alpha=0.9, beta=0.8, threshold=2.0),
    )
    assert sentence == (
        "Define a RSynaptic neuron named rsyn1 with neuron count 16, "
        "synaptic decay 0.9, membrane decay 0.8, and firing threshold 2.0."
    )


def test_render_leaky() -> None:
    from neurocnl.runtime.cnl_nodes import Leaky as CnlLeaky

    sentence = _render_only_node(
        "leaky1",
        CnlLeaky(n_neurons=10, beta=0.9, threshold=1.0),
    )
    assert sentence == (
        "Define a Leaky neuron named leaky1 with neuron count 10, "
        "membrane decay 0.9, and firing threshold 1.0."
    )


def test_render_rleaky() -> None:
    from neurocnl.runtime.cnl_nodes import RLeaky as CnlRLeaky

    sentence = _render_only_node(
        "rleaky1",
        CnlRLeaky(n_neurons=10, beta=0.9, threshold=1.0),
    )
    assert sentence == (
        "Define a RLeaky neuron named rleaky1 with neuron count 10, "
        "membrane decay 0.9, and firing threshold 1.0."
    )


def test_render_synaptic_family_never_marked_unsupported() -> None:
    """The exact regression this fix closes: a graph containing all four
    types must not fall back to the "unsupported node type" comment
    form for any of them, and every edge between them must survive."""
    from neurocnl._nir_compat import make_nir_graph
    from neurocnl.runtime.cnl_nodes import Leaky as CnlLeaky
    from neurocnl.runtime.cnl_nodes import RLeaky as CnlRLeaky
    from neurocnl.runtime.cnl_nodes import RSynaptic as CnlRSynaptic
    from neurocnl.runtime.cnl_nodes import Synaptic as CnlSynaptic

    graph = make_nir_graph(
        nodes={
            "in1": nir.Input(input_type={"input": np.array([4])}),
            "syn": CnlSynaptic(n_neurons=4, alpha=0.9, beta=0.8, threshold=1.0),
            "rsyn": CnlRSynaptic(n_neurons=4, alpha=0.9, beta=0.8, threshold=1.0),
            "leaky": CnlLeaky(n_neurons=4, beta=0.8, threshold=1.0),
            "rleaky": CnlRLeaky(n_neurons=4, beta=0.8, threshold=1.0),
            "out1": nir.Output(output_type={"output": np.array([4])}),
        },
        edges=[
            ("in1", "syn"),
            ("syn", "rsyn"),
            ("rsyn", "leaky"),
            ("leaky", "rleaky"),
            ("rleaky", "out1"),
        ],
    )
    text = NIR_Renderer().render(graph)
    assert "unsupported" not in text, text


def test_synaptic_family_round_trips_through_compile_to_nir() -> None:
    """Regression for the actual failure mode: a canvas-built network with
    these neuron types must survive a full render -> re-parse round trip
    with the same node/edge count and types, not silently collapse to a
    disconnected graph (which is what produced generated training
    notebooks whose ``forward()`` never called any layer, and so trained
    against a tensor with no ``grad_fn``)."""
    from neurocnl._nir_compat import make_nir_graph
    from neurocnl.compile import compile_to_nir
    from neurocnl.runtime.cnl_nodes import Synaptic as CnlSynaptic

    graph_in = make_nir_graph(
        nodes={
            "in1": nir.Input(input_type={"input": np.array([12])}),
            "fc1": nir.Linear(weight=np.ones((40, 12), dtype=np.float32)),
            "syn1": CnlSynaptic(n_neurons=40, alpha=0.9, beta=0.8, threshold=1.0),
            "fc2": nir.Linear(weight=np.ones((7, 40), dtype=np.float32)),
            "syn2": CnlSynaptic(n_neurons=7, alpha=0.9, beta=0.8, threshold=1.0),
            "out1": nir.Output(output_type={"output": np.array([7])}),
        },
        edges=[
            ("in1", "fc1"),
            ("fc1", "syn1"),
            ("syn1", "fc2"),
            ("fc2", "syn2"),
            ("syn2", "out1"),
        ],
    )
    text = NIR_Renderer().render(graph_in)
    assert "unsupported" not in text, text

    graph_out = compile_to_nir(text)
    assert len(graph_out.nodes) == len(graph_in.nodes) == 6
    assert len(graph_out.edges) == len(graph_in.edges) == 5
    assert type(graph_out.nodes["syn1"]).__name__ == "Synaptic"
    assert type(graph_out.nodes["syn2"]).__name__ == "Synaptic"
