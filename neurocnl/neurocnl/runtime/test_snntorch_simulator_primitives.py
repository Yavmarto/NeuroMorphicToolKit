"""Wave 1 exploration tests for snnTorch adapter — new NIR node types.

These tests are written AGAINST THE UNFIXED CODE and are expected to FAIL.
Failure of these tests is the success condition for this Wave 1 task (1.3).

- ``test_new_node_type_no_skip_warning`` — verifies the adapter emits no
  ``"not supported"`` / ``"skipped"`` warnings for the five new node types.
  MUST FAIL until Wave 2 adds the elif branches in ``_simulate()``.

- ``test_new_node_type_not_classified_as_unsupported`` — verifies the
  classifier returns a non-"unsupported" level for graphs containing each
  new node type.
  MUST FAIL until Wave 2 expands ``_BACKEND_NIR_SUPPORT``.

Validates: Requirements 2.1, 2.2, 2.3, 2.4, 2.5, 2.7, 6.3, 6.4
"""

from __future__ import annotations

import nir
import numpy as np
import pytest

try:
    from hypothesis import given, settings
    from hypothesis import strategies as st

    HAS_HYPOTHESIS = True
except ImportError:
    HAS_HYPOTHESIS = False

from neurocnl.runtime.nir_support import classify_nir_graph
from neurocnl.runtime.snntorch_simulator import SnnTorchSimulatorAdapter
from neurocnl.runtime.stimulus import ValidatedStimulus

# ---------------------------------------------------------------------------
# Node constructors for the five new primitives
# Exact constructors as specified in design doc §"File 2"
# ---------------------------------------------------------------------------

NEW_SNNTORCH_NODES: dict[str, object] = {
    "Affine": lambda: nir.Affine(
        weight=np.eye(4, dtype=np.float32),
        bias=np.zeros(4, dtype=np.float32),
    ),
    "Conv2d": lambda: nir.Conv2d(
        input_shape=(4, 4),
        weight=np.zeros((2, 1, 3, 3), dtype=np.float32),
        stride=np.array([1, 1]),
        padding=np.array([1, 1]),
        dilation=np.array([1, 1]),
        groups=1,
        bias=np.zeros(2, dtype=np.float32),
    ),
    "Flatten": lambda: nir.Flatten(
        start_dim=1,
        end_dim=-1,
        input_type={"input": np.zeros(4)},
    ),
    "IF": lambda: nir.IF(
        r=np.array(1.0),
        v_threshold=np.array(1.0),
    ),
    "AvgPool2d": lambda: nir.AvgPool2d(
        kernel_size=np.array([2, 2]),
        stride=np.array([2, 2]),
        padding=np.array([0, 0]),
    ),
}


# ---------------------------------------------------------------------------
# Graph and stimulus helpers
# ---------------------------------------------------------------------------


def _make_graph_with_node(name: str, node: nir.NIRNode, in_size: int) -> nir.NIRGraph:
    """Wrap a single NIR node in ``Input → node → LIF → Output`` topology.

    The ``in_size`` parameter drives both the Input shape and the bridge
    Linear weight dimension so the graph is internally consistent.

    Parameters
    ----------
    name : str
        Name for the wrapped node in the graph.
    node : nir.NIRNode
        The node under test.
    in_size : int
        Leading input dimension for the Input and Linear nodes.
    """
    lif_size = in_size  # output of the node feeds into a square LIF

    lif_node = nir.LIF(
        tau=np.full(lif_size, 2.0, dtype=np.float32),
        r=np.ones(lif_size, dtype=np.float32),
        v_leak=np.zeros(lif_size, dtype=np.float32),
        v_threshold=np.ones(lif_size, dtype=np.float32),
    )
    input_node = nir.Input(input_type={"input": np.zeros(in_size)})
    output_node = nir.Output(output_type={"output": np.zeros(lif_size)})

    return nir.NIRGraph(
        nodes={
            "input": input_node,
            name: node,
            "lif": lif_node,
            "output": output_node,
        },
        edges=[
            ("input", name),
            (name, "lif"),
            ("lif", "output"),
        ],
        type_check=False,
    )


def _make_minimal_stimulus(graph: nir.NIRGraph, timesteps: int) -> ValidatedStimulus:
    """Build a ValidatedStimulus with one spike at t=0 on neuron 0.

    Parameters
    ----------
    graph : nir.NIRGraph
        The graph whose first Input node will receive the stimulus.
    timesteps : int
        Total simulation timesteps (unused — stimulus specifies only t=0).
    """
    # Find the name of the first Input node (alphabetical to be deterministic)
    input_name = sorted(
        name for name, node in graph.nodes.items() if isinstance(node, nir.Input)
    )[0]

    # Infer neuron count from the Input node's input_type
    input_node = graph.nodes[input_name]
    input_type = input_node.input_type
    if isinstance(input_type, dict) and input_type:
        shape = next(iter(input_type.values()))
        neuron_count = (
            int(np.asarray(shape).flat[0]) if np.asarray(shape).size > 0 else 1
        )
    else:
        neuron_count = 1

    return ValidatedStimulus(
        population=input_name,
        neuron_count=neuron_count,
        spikes={0: [0]},  # one spike at t=0 on neuron 0
    )


# ---------------------------------------------------------------------------
# Test 1: no "not supported" / "skipped" warning emitted by the adapter
# Validates: Requirements 2.1, 2.2, 2.3, 2.4, 2.5, 2.7, 6.3
# ---------------------------------------------------------------------------


@pytest.mark.parametrize("node_type_name", list(NEW_SNNTORCH_NODES))
def test_new_node_type_no_skip_warning(node_type_name: str) -> None:
    """Running a graph with the new node type must not emit a skip/unsupported warning.

    Wave 1 exploration test — MUST FAIL against unfixed code.
    The adapter's ``else:`` catch-all emits ``"not supported"``/``"skipped"``
    warnings for unrecognised NIR nodes.  Once the Wave 2 elif branches are
    added, this test will pass.

    Validates: Requirements 2.1, 2.2, 2.3, 2.4, 2.5, 2.7, 6.3
    """
    torch = pytest.importorskip("torch")  # noqa: F841 — skip if no torch
    pytest.importorskip("snntorch")

    node = NEW_SNNTORCH_NODES[node_type_name]()  # type: ignore[operator]
    graph = _make_graph_with_node(node_type_name, node, in_size=4)
    stimulus = _make_minimal_stimulus(graph, timesteps=5)

    result = SnnTorchSimulatorAdapter().run(
        graph=graph,
        stimulus=stimulus,
        timesteps=5,
        seed=0,
    )

    skip_warnings = [
        w
        for w in result.warnings
        if "not supported" in w.lower() or "skipped" in w.lower()
    ]
    assert (
        skip_warnings == []
    ), f"Adapter emitted skip/unsupported warning(s) for nir.{node_type_name}: {skip_warnings}"


# ---------------------------------------------------------------------------
# Test 2: graph containing new node type must not be classified as unsupported
# Validates: Requirements 2.1, 2.2, 2.3, 2.4, 2.5, 6.4
# ---------------------------------------------------------------------------


@pytest.mark.parametrize("node_type_name", list(NEW_SNNTORCH_NODES))
def test_new_node_type_not_classified_as_unsupported(node_type_name: str) -> None:
    """classify_nir_graph must not return level='unsupported' for the new types.

    Wave 1 exploration test — MUST FAIL against unfixed code.
    The current ``_BACKEND_NIR_SUPPORT`` table lacks entries for the five new
    node types, so they fall through to the ``"unsupported"`` default.  Once
    Wave 2 adds explicit ``"exact"`` entries, this test will pass.

    Validates: Requirements 2.1, 2.2, 2.3, 2.4, 2.5, 6.4
    """
    node = NEW_SNNTORCH_NODES[node_type_name]()  # type: ignore[operator]
    graph = _make_graph_with_node(node_type_name, node, in_size=4)

    result = classify_nir_graph(graph, "snntorch_sim")

    assert result.level != "unsupported", (
        f"classify_nir_graph returned level='unsupported' for a graph containing "
        f"nir.{node_type_name}.  "
        f"unsupported_nodes={result.unsupported_nodes!r}, "
        f"diagnostics={result.diagnostics!r}"
    )


# ---------------------------------------------------------------------------
# Test 3 (Task 1.4): Lava early-rejection guard — unsupported NIR node types
# Validates: Requirements 3.3, 6.5
# ---------------------------------------------------------------------------


def test_lava_early_rejection_names_unsupported_types() -> None:
    """LavaSimulatorAdapter._run_in_process must raise LavaDispatchError for Conv2d.

    Wave 1 exploration test — MUST FAIL against unfixed code.
    No guard exists yet: ``_run_in_process`` will attempt Lava process
    construction rather than raising ``LavaDispatchError`` immediately.
    Once the Wave 2 guard is added, ``LavaDispatchError`` will be raised
    before any Lava process is constructed and this test will pass.

    Validates: Requirements 3.3, 6.5
    """
    pytest.importorskip("lava")

    from neurocnl.runtime.lava_simulator import LavaDispatchError, LavaSimulatorAdapter

    # Build a minimal NIR graph containing nir.Conv2d (unsupported by lava-nc)
    conv_node = nir.Conv2d(
        input_shape=(6, 6),
        weight=np.ones((1, 1, 3, 3), dtype=np.float32),
        stride=np.array([1, 1]),
        padding=np.array([0, 0]),
        dilation=np.array([1, 1]),
        groups=1,
        bias=np.zeros(1, dtype=np.float32),
    )

    graph = nir.NIRGraph(
        nodes={
            "input": nir.Input(input_type={"input": np.zeros(1)}),
            "conv": conv_node,
            "output": nir.Output(output_type={"output": np.zeros(1)}),
        },
        edges=[
            ("input", "conv"),
            ("conv", "output"),
        ],
        type_check=False,
    )

    stimulus = _make_minimal_stimulus(graph, timesteps=5)
    with pytest.raises(LavaDispatchError) as exc_info:
        LavaSimulatorAdapter()._run_in_process(graph, stimulus, timesteps=5, seed=0)

    error_message = str(exc_info.value)
    assert "Conv2d" in error_message, (
        f"LavaDispatchError was raised but 'Conv2d' does not appear in the message. "
        f"Got: {error_message!r}"
    )


# ---------------------------------------------------------------------------
# Constants for Lava PBT (Property 8)
# ---------------------------------------------------------------------------

LAVA_UNSUPPORTED = sorted(
    [
        p
        for p, v in {
            "Affine": "unsupported",
            "Conv2d": "unsupported",
            "Flatten": "unsupported",
            "IF": "unsupported",
            "LI": "unsupported",
            "I": "unsupported",
            "AvgPool2d": "unsupported",
            "SumPool2d": "unsupported",
            "Scale": "unsupported",
            "Threshold": "unsupported",
            "Sigmoid": "unsupported",
            "CubaLI": "unsupported",
        }.items()
        if v == "unsupported"
    ]
)


def _make_unsupported_lava_node(type_name: str) -> nir.NIRNode | None:
    """Create a minimal valid nir node for a lava-unsupported type name.

    Returns None if the node cannot be constructed (caller should skip).
    The guard in LavaSimulatorAdapter fires on type(node).__name__, so we
    only need a valid instance — it doesn't need to be runnable.
    """
    try:
        if type_name == "Affine":
            return nir.Affine(weight=np.eye(2), bias=np.zeros(2))
        elif type_name == "Conv2d":
            return nir.Conv2d(
                input_shape=(4, 4),
                weight=np.zeros((2, 1, 3, 3), dtype=np.float32),
                stride=np.array([1, 1]),
                padding=np.array([0, 0]),
                dilation=np.array([1, 1]),
                groups=1,
                bias=np.zeros(2, dtype=np.float32),
            )
        elif type_name == "Flatten":
            return nir.Flatten(
                start_dim=1,
                end_dim=-1,
                input_type={"input": np.zeros(2)},
            )
        elif type_name == "IF":
            return nir.IF(
                r=np.ones(2),
                v_threshold=np.ones(2),
            )
        elif type_name == "LI":
            return nir.LI(
                tau=np.array([2.0, 2.0]),
                r=np.ones(2),
                v_leak=np.zeros(2),
            )
        elif type_name == "I":
            return nir.I(
                r=np.ones(2),
            )
        elif type_name == "AvgPool2d":
            return nir.AvgPool2d(
                kernel_size=np.array([2, 2]),
                stride=np.array([2, 2]),
                padding=np.array([0, 0]),
            )
        elif type_name == "SumPool2d":
            return nir.SumPool2d(
                kernel_size=np.array([2, 2]),
                stride=np.array([2, 2]),
                padding=np.array([0, 0]),
            )
        elif type_name == "Scale":
            return nir.Scale(scale=np.ones(2))
        elif type_name == "Threshold":
            return nir.Threshold(
                threshold=np.ones(2),
            )
        elif type_name == "Sigmoid":
            cls = getattr(nir, "Sigmoid", None)
            if cls is None:
                return None
            return cls()
        elif type_name == "CubaLI":
            return nir.CubaLI(
                tau_syn=np.array([1.0, 1.0]),
                tau_mem=np.array([2.0, 2.0]),
                r=np.ones(2),
                v_leak=np.zeros(2),
            )
        else:
            return None
    except Exception:
        return None


# ---------------------------------------------------------------------------
# Property 8: Lava early-rejection for any unsupported type
# Validates: Requirements 3.3
# ---------------------------------------------------------------------------


@pytest.mark.skipif(not HAS_HYPOTHESIS, reason="hypothesis not installed")
@given(
    unsupported_types=st.lists(
        st.sampled_from(LAVA_UNSUPPORTED),
        min_size=1,
        max_size=3,
        unique=True,
    )
)
@settings(max_examples=50)
def test_lava_early_rejection_any_unsupported_type(
    unsupported_types: list[str],
) -> None:
    """LavaSimulatorAdapter._run_in_process raises LavaDispatchError for any unsupported type.

    # Validates: Requirements 3.3
    """
    pytest.importorskip("lava")
    from neurocnl.runtime.lava_simulator import LavaDispatchError, LavaSimulatorAdapter

    # Use the first unsupported type as the representative node in the graph
    node_type_name = unsupported_types[0]
    node = _make_unsupported_lava_node(node_type_name)
    if node is None:
        return  # skip if we can't construct the node

    graph = nir.NIRGraph(
        nodes={
            "input": nir.Input(input_type={"input": np.zeros(1)}),
            node_type_name.lower(): node,
            "output": nir.Output(output_type={"output": np.zeros(1)}),
        },
        edges=[
            ("input", node_type_name.lower()),
            (node_type_name.lower(), "output"),
        ],
        type_check=False,
    )

    stimulus = _make_minimal_stimulus(graph, timesteps=5)
    with pytest.raises(LavaDispatchError) as exc_info:
        LavaSimulatorAdapter()._run_in_process(graph, stimulus, timesteps=5, seed=0)

    assert node_type_name in str(
        exc_info.value
    ), f"LavaDispatchError raised but {node_type_name!r} not found in message: {exc_info.value!r}"
