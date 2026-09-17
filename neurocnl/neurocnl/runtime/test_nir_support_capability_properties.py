"""Property-based capability-classification tests for neurocnl.runtime.nir_support.

Split from ``test_nir_support.py``: builds minimal NIR graphs from arbitrary
node-type combinations (via Hypothesis where available) and checks the
exact/approximate/unsupported partition properties of ``classify_nir_graph``.
Shares ``COMPLETE_PRIMITIVE_SET``/``EXPECTED_VERDICTS`` with
``test_nir_support_verdict_matrix.py``.
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

from neurocnl.runtime.nir_support import classify_nir_graph, get_supported_node_types

from .test_nir_support_verdict_matrix import COMPLETE_PRIMITIVE_SET, EXPECTED_VERDICTS

# ---------------------------------------------------------------------------
# _build_minimal_graph_from_types helper
# ---------------------------------------------------------------------------


def _make_nir_node(type_name: str) -> nir.NIRNode | None:
    """Create a minimal valid nir node instance for the given type name.

    Returns None if the node cannot be constructed (skipped in graph builder).
    """
    try:
        if type_name == "Input":
            return nir.Input(input_type={"input": np.zeros(2)})
        elif type_name == "Output":
            return nir.Output(output_type={"output": np.zeros(2)})
        elif type_name == "Linear":
            return nir.Linear(weight=np.eye(2))
        elif type_name == "Affine":
            return nir.Affine(weight=np.eye(2), bias=np.zeros(2))
        elif type_name == "LIF":
            return nir.LIF(
                tau=np.array([2.0, 2.0]),
                r=np.ones(2),
                v_leak=np.zeros(2),
                v_threshold=np.ones(2),
            )
        elif type_name == "CubaLIF":
            return nir.CubaLIF(
                tau_mem=np.array([2.0, 2.0]),
                tau_syn=np.array([1.0, 1.0]),
                r=np.ones(2),
                v_leak=np.zeros(2),
                v_threshold=np.ones(2),
                w_in=np.ones(2),
            )
        elif type_name == "Delay":
            return nir.Delay(delay=np.ones(2))
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
        elif type_name == "IF":
            return nir.IF(
                r=np.ones(2),
                v_threshold=np.ones(2),
            )
        elif type_name == "Conv2d":
            return nir.Conv2d(
                input_shape=(4, 4),
                weight=np.zeros((2, 1, 3, 3), dtype=np.float32),
                stride=np.array([1, 1]),
                padding=np.array([1, 1]),
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
            # Attempt generic construction via getattr
            cls = getattr(nir, type_name, None)
            if cls is None:
                return None
            return cls()
    except Exception:
        return None


def _build_minimal_graph_from_types(node_types: list[str]) -> nir.NIRGraph:
    """Construct a nir.NIRGraph containing exactly the requested node type names.

    Bridges the requested nodes between nir.Input and nir.Output. Any node
    type that cannot be constructed is silently omitted so the graph remains
    valid. Input and Output are always injected as boundary nodes.
    """
    nodes: dict[str, nir.NIRNode] = {}
    edges: list[tuple[str, str]] = []

    # Always include Input and Output boundary nodes
    nodes["_input"] = nir.Input(input_type={"input": np.zeros(2)})
    nodes["_output"] = nir.Output(output_type={"output": np.zeros(2)})

    inner_keys: list[str] = []
    for type_name in node_types:
        # Skip boundary types — we already added them
        if type_name in ("Input", "Output"):
            continue
        node = _make_nir_node(type_name)
        if node is not None:
            key = type_name.lower()
            # Avoid duplicate keys from repeated type names
            if key in nodes:
                key = f"{key}_{len(inner_keys)}"
            nodes[key] = node
            inner_keys.append(key)

    # Wire: _input → inner[0] → inner[1] → ... → _output
    if inner_keys:
        edges.append(("_input", inner_keys[0]))
        for i in range(len(inner_keys) - 1):
            edges.append((inner_keys[i], inner_keys[i + 1]))
        edges.append((inner_keys[-1], "_output"))
    else:
        edges.append(("_input", "_output"))

    return nir.NIRGraph(nodes=nodes, edges=edges, type_check=False)


# ---------------------------------------------------------------------------
# Property 2: exact-only graph classifies as exact
# Feature: nir-simulator-support-matrix, Property 2
# Validates: Requirements 5.1
# ---------------------------------------------------------------------------

_EXACT_SNN_TYPES = sorted(
    [
        p
        for p, v in EXPECTED_VERDICTS["snntorch_sim"].items()
        if v == "exact"
        and p not in ("Input", "Output")  # exclude mandatory boundary nodes
    ]
)

# Pre-filter to only include types that can actually be constructed as nir nodes.
# This avoids test skew when the installed nir package lacks a class (e.g. nir.Sigmoid).
_CONSTRUCTIBLE_EXACT_SNN_TYPES = sorted(
    t for t in _EXACT_SNN_TYPES if _make_nir_node(t) is not None
)

_APPROX_SNN_TYPES = sorted(
    [p for p, v in EXPECTED_VERDICTS["snntorch_sim"].items() if v == "approximate"]
)
_CONSTRUCTIBLE_APPROX_SNN_TYPES = sorted(
    t for t in _APPROX_SNN_TYPES if _make_nir_node(t) is not None
)

_UNSUPPORTED_SNN_TYPES = sorted(
    [p for p, v in EXPECTED_VERDICTS["snntorch_sim"].items() if v == "unsupported"]
)
# Only include types that can be constructed so the graph actually contains them.
# Sigmoid is excluded because nir.Sigmoid does not exist in the installed nir package.
_CONSTRUCTIBLE_UNSUPPORTED_SNN_TYPES = sorted(
    t for t in _UNSUPPORTED_SNN_TYPES if _make_nir_node(t) is not None
)


@pytest.mark.skipif(not HAS_HYPOTHESIS, reason="hypothesis not installed")
@given(
    node_types=st.lists(
        st.sampled_from(_CONSTRUCTIBLE_EXACT_SNN_TYPES),
        min_size=1,
        max_size=6,
        unique=True,
    )
)
@settings(max_examples=100)
def test_exact_only_graph_classifies_exact(node_types: list[str]) -> None:
    """A graph composed only of exact-verdict snntorch_sim node types must classify as exact.

    # Feature: nir-simulator-support-matrix, Property 2
    # Validates: Requirements 5.1
    """
    graph = _build_minimal_graph_from_types(node_types)
    result = classify_nir_graph(graph, "snntorch_sim")
    assert result.level == "exact", (
        f"Expected level='exact' for node_types={node_types!r}, "
        f"got level={result.level!r}, "
        f"unsupported_nodes={result.unsupported_nodes!r}, "
        f"approximate_nodes={result.approximate_nodes!r}"
    )
    assert result.unsupported_nodes == []
    assert result.approximate_nodes == []


# ---------------------------------------------------------------------------
# Property 3: approximate-present graph classifies as approximate
# Validates: Requirements 5.2
# ---------------------------------------------------------------------------


@pytest.mark.skipif(not HAS_HYPOTHESIS, reason="hypothesis not installed")
@given(
    approx_types=st.lists(
        st.sampled_from(_CONSTRUCTIBLE_APPROX_SNN_TYPES),
        min_size=1,
        max_size=2,
        unique=True,
    )
)
@settings(max_examples=50)
def test_approximate_present_graph_classifies_approximate(
    approx_types: list[str],
) -> None:
    """A graph with approximate nodes (and no unsupported) must classify as approximate.

    # Validates: Requirements 5.2
    """
    # Combine approximate types with some exact types (LIF is always exact)
    all_types = approx_types + ["LIF"]
    graph = _build_minimal_graph_from_types(all_types)
    result = classify_nir_graph(graph, "snntorch_sim")
    assert result.level == "approximate", (
        f"Expected level='approximate' for approx_types={approx_types!r}, "
        f"got level={result.level!r}, "
        f"unsupported_nodes={result.unsupported_nodes!r}"
    )


# ---------------------------------------------------------------------------
# Property 4: unsupported-present graph classifies as unsupported
# Validates: Requirements 5.3, 5.6
# ---------------------------------------------------------------------------


@pytest.mark.skipif(not HAS_HYPOTHESIS, reason="hypothesis not installed")
@given(
    unsupported_types=st.lists(
        st.sampled_from(_CONSTRUCTIBLE_UNSUPPORTED_SNN_TYPES),
        min_size=1,
        max_size=4,
        unique=True,
    )
)
@settings(max_examples=50)
def test_unsupported_present_graph_classifies_unsupported(
    unsupported_types: list[str],
) -> None:
    """A graph containing any unsupported node type must classify as unsupported with diagnostics.

    # Validates: Requirements 5.3, 5.6
    """
    graph = _build_minimal_graph_from_types(unsupported_types)
    result = classify_nir_graph(graph, "snntorch_sim")
    assert result.level == "unsupported", (
        f"Expected level='unsupported' for unsupported_types={unsupported_types!r}, "
        f"got level={result.level!r}"
    )
    assert (
        len(result.diagnostics) > 0
    ), f"Expected non-empty diagnostics for unsupported_types={unsupported_types!r}"


# ---------------------------------------------------------------------------
# Property 5: unsupported nodes all named in diagnostics
# Validates: Requirements 5.4, 5.6
# ---------------------------------------------------------------------------


@pytest.mark.skipif(not HAS_HYPOTHESIS, reason="hypothesis not installed")
@given(
    unsupported_types=st.lists(
        st.sampled_from(_CONSTRUCTIBLE_UNSUPPORTED_SNN_TYPES),
        min_size=1,
        max_size=3,
        unique=True,
    )
)
@settings(max_examples=50)
def test_unsupported_nodes_all_named_in_diagnostics(
    unsupported_types: list[str],
) -> None:
    """Every unsupported_node listed in the classification must appear in at least one diagnostic.

    # Validates: Requirements 5.4, 5.6
    """
    graph = _build_minimal_graph_from_types(unsupported_types)
    result = classify_nir_graph(graph, "snntorch_sim")
    for node_type in result.unsupported_nodes:
        assert any(node_type in msg for msg in result.diagnostics), (
            f"Node type {node_type!r} is in unsupported_nodes but not named in any diagnostic. "
            f"diagnostics={result.diagnostics!r}"
        )


# ---------------------------------------------------------------------------
# Property 7: capabilities union equals COMPLETE_PRIMITIVE_SET
# Validates: Requirements 4.1, 4.2, 4.3, 4.4
# ---------------------------------------------------------------------------


def test_capabilities_lists_partition_complete_primitive_set() -> None:
    """For both backends, exact | approximate | unsupported == COMPLETE_PRIMITIVE_SET.

    # Validates: Requirements 4.1, 4.2, 4.3, 4.4
    """
    for backend in EXPECTED_VERDICTS:
        table = get_supported_node_types(backend)
        exact_set = frozenset(k for k, v in table.items() if v == "exact")
        approx_set = frozenset(k for k, v in table.items() if v == "approximate")
        unsupported_set = frozenset(k for k, v in table.items() if v == "unsupported")
        union = exact_set | approx_set | unsupported_set
        assert union == COMPLETE_PRIMITIVE_SET, (
            f"Backend {backend!r}: union of verdict sets {sorted(union)} "
            f"!= COMPLETE_PRIMITIVE_SET {sorted(COMPLETE_PRIMITIVE_SET)}"
        )
