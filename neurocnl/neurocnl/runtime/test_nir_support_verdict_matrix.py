"""Tests for neurocnl.runtime.nir_support — verdict-matrix classification.

Split from ``test_nir_support.py``: the backend-agnostic verdict table,
``classify_nir_graph``/``get_supported_node_types``/``list_supported_backends``
tests, and the no-fallthrough structural check. These parametrize a single
shared assertion across every registered backend (they are not
backend-specific — see ``test_nir_support_capability_properties.py`` and
``test_nir_support_converter_regression.py`` for the property-based and
per-converter suites split out alongside this one).
"""

from __future__ import annotations

import nir
import numpy as np
import pytest

from neurocnl.runtime.nir_support import (
    SupportClassification,
    classify_nir_graph,
    get_supported_node_types,
    list_supported_backends,
)

# ---------------------------------------------------------------------------
# Complete primitive set — all NIR primitives that must have explicit verdicts
# (intentionally duplicated from nir_support.py so tests are self-contained)
# ---------------------------------------------------------------------------

COMPLETE_PRIMITIVE_SET: frozenset[str] = frozenset(
    {
        "Input",
        "Output",
        "Linear",
        "Affine",
        "Conv2d",
        "Flatten",
        "IF",
        "LIF",
        "CubaLIF",
        "LI",
        "AvgPool2d",
        "SumPool2d",
        "Delay",
        "Scale",
        "Threshold",
        "Sigmoid",
        "I",  # Integrator
        "CubaLI",
        # ── CNLStudio-internal node types (not standard NIR primitives) ──────────
        "Synaptic",  # cnl.Synaptic — snnTorch snn.Synaptic with dual time constants
        "RSynaptic",  # cnl.RSynaptic — snnTorch snn.RSynaptic with built-in recurrence
        "RLeaky",  # cnl.RLeaky — snnTorch snn.RLeaky (recurrent LIF, (spk,mem) state)
        "Leaky",  # cnl.Leaky — snnTorch snn.Leaky with explicit beta, init_hidden=False
        "BatchNorm1d",  # cnl.BatchNorm1d — nn.BatchNorm1d, stateless
        "Dropout",  # cnl.Dropout — nn.Dropout, stateless
    }
)

# ---------------------------------------------------------------------------
# Expected verdicts per backend — Wave 1 exploration reference table
# ---------------------------------------------------------------------------

EXPECTED_VERDICTS: dict[str, dict[str, str]] = {
    "sc_neurocore_sim": {
        "Input": "exact",
        "Output": "exact",
        "Linear": "exact",
        "Affine": "exact",
        "Conv2d": "unsupported",
        "Flatten": "unsupported",
        "IF": "exact",
        "LIF": "exact",
        "CubaLIF": "approximate",
        "LI": "unsupported",
        "I": "unsupported",
        "AvgPool2d": "unsupported",
        "SumPool2d": "unsupported",
        "Delay": "approximate",
        "Scale": "unsupported",
        "Threshold": "unsupported",
        "Sigmoid": "unsupported",
        "CubaLI": "unsupported",
        "Synaptic": "unsupported",
        "RSynaptic": "unsupported",
        "RLeaky": "unsupported",
        "Leaky": "unsupported",
        "BatchNorm1d": "unsupported",
        "Dropout": "unsupported",
    },
    "lava_sim": {
        "Input": "exact",
        "Output": "exact",
        "Linear": "exact",
        "Affine": "approximate",
        "Conv2d": "unsupported",
        "Flatten": "unsupported",
        "IF": "unsupported",
        "LIF": "exact",
        "CubaLIF": "approximate",
        "LI": "unsupported",
        "I": "unsupported",
        "AvgPool2d": "unsupported",
        "SumPool2d": "unsupported",
        "Delay": "approximate",
        "Scale": "unsupported",
        "Threshold": "unsupported",
        "Sigmoid": "unsupported",
        "CubaLI": "unsupported",
        "Synaptic": "unsupported",
        "RSynaptic": "unsupported",
    },
    "snntorch_sim": {
        "Input": "exact",
        "Output": "exact",
        "Linear": "exact",
        "Affine": "exact",
        "Conv2d": "exact",
        "Flatten": "exact",
        "IF": "exact",
        "LIF": "exact",
        "CubaLIF": "approximate",
        "LI": "unsupported",
        "I": "unsupported",
        "AvgPool2d": "exact",
        "SumPool2d": "exact",  # kept in sync with nir_support.py — see comment there
        "Delay": "approximate",
        "Scale": "unsupported",
        "Threshold": "unsupported",
        "Sigmoid": "unsupported",
        "CubaLI": "unsupported",
        "Synaptic": "exact",
        "RSynaptic": "exact",
    },
    "brian2": {
        "Input": "exact",
        "Output": "exact",
        "Linear": "exact",
        "Affine": "unsupported",
        "Conv2d": "unsupported",
        "Flatten": "unsupported",
        "IF": "unsupported",
        "LIF": "approximate",
        "CubaLIF": "unsupported",
        "LI": "unsupported",
        "I": "unsupported",
        "AvgPool2d": "unsupported",
        "SumPool2d": "unsupported",
        "Delay": "unsupported",
        "Scale": "unsupported",
        "Threshold": "unsupported",
        "Sigmoid": "unsupported",
        "CubaLI": "unsupported",
        "Synaptic": "unsupported",
        "RSynaptic": "unsupported",
        "RLeaky": "unsupported",
        "Leaky": "unsupported",
        "BatchNorm1d": "unsupported",
        "Dropout": "unsupported",
    },
    "pynn": {
        "Input": "exact",
        "Output": "exact",
        "Linear": "exact",
        "Affine": "unsupported",
        "Conv2d": "unsupported",
        "Flatten": "unsupported",
        "IF": "unsupported",
        "LIF": "approximate",
        "CubaLIF": "unsupported",
        "LI": "unsupported",
        "I": "unsupported",
        "AvgPool2d": "unsupported",
        "SumPool2d": "unsupported",
        "Delay": "unsupported",
        "Scale": "unsupported",
        "Threshold": "unsupported",
        "Sigmoid": "unsupported",
        "CubaLI": "unsupported",
        "Synaptic": "unsupported",
        "RSynaptic": "unsupported",
        "RLeaky": "unsupported",
        "Leaky": "unsupported",
        "BatchNorm1d": "unsupported",
        "Dropout": "unsupported",
    },
    "lava": {
        "Input": "exact",
        "Output": "exact",
        "Linear": "exact",
        "Affine": "unsupported",
        "Conv2d": "unsupported",
        "Flatten": "unsupported",
        "IF": "unsupported",
        "LIF": "approximate",
        "CubaLIF": "unsupported",
        "LI": "unsupported",
        "I": "unsupported",
        "AvgPool2d": "unsupported",
        "SumPool2d": "unsupported",
        "Delay": "unsupported",
        "Scale": "unsupported",
        "Threshold": "unsupported",
        "Sigmoid": "unsupported",
        "CubaLI": "unsupported",
        "Synaptic": "unsupported",
        "RSynaptic": "unsupported",
        "RLeaky": "unsupported",
        "Leaky": "unsupported",
        "BatchNorm1d": "unsupported",
        "Dropout": "unsupported",
    },
    "rockpool": {
        "Input": "exact",
        "Output": "exact",
        "Linear": "exact",
        "Affine": "unsupported",
        "Conv2d": "unsupported",
        "Flatten": "unsupported",
        "IF": "unsupported",
        "LIF": "approximate",
        "CubaLIF": "approximate",
        "LI": "unsupported",
        "I": "unsupported",
        "AvgPool2d": "unsupported",
        "SumPool2d": "unsupported",
        "Delay": "unsupported",
        "Scale": "unsupported",
        "Threshold": "unsupported",
        "Sigmoid": "unsupported",
        "CubaLI": "unsupported",
        "Synaptic": "unsupported",
        "RSynaptic": "unsupported",
        "RLeaky": "unsupported",
        "Leaky": "unsupported",
        "BatchNorm1d": "unsupported",
        "Dropout": "unsupported",
    },
    "sinabs": {
        "Input": "exact",
        "Output": "exact",
        "Linear": "exact",
        "Affine": "exact",
        "Conv2d": "unsupported",
        "Flatten": "unsupported",
        "IF": "approximate",
        "LIF": "approximate",
        "CubaLIF": "unsupported",
        "LI": "unsupported",
        "I": "unsupported",
        "AvgPool2d": "unsupported",
        "SumPool2d": "unsupported",
        "Delay": "unsupported",
        "Scale": "unsupported",
        "Threshold": "unsupported",
        "Sigmoid": "unsupported",
        "CubaLI": "unsupported",
        "Synaptic": "unsupported",
        "RSynaptic": "unsupported",
        "RLeaky": "unsupported",
        "Leaky": "unsupported",
        "BatchNorm1d": "unsupported",
        "Dropout": "unsupported",
    },
    "nengo": {
        "Input": "exact",
        "Output": "exact",
        "Linear": "exact",
        "Affine": "exact",
        "Conv2d": "unsupported",
        "Flatten": "unsupported",
        "IF": "unsupported",
        "LIF": "approximate",
        "CubaLIF": "approximate",
        "LI": "unsupported",
        "I": "unsupported",
        "AvgPool2d": "unsupported",
        "SumPool2d": "unsupported",
        "Delay": "unsupported",
        "Scale": "unsupported",
        "Threshold": "unsupported",
        "Sigmoid": "unsupported",
        "CubaLI": "unsupported",
        "Synaptic": "unsupported",
        "RSynaptic": "unsupported",
        "RLeaky": "unsupported",
        "Leaky": "unsupported",
        "BatchNorm1d": "unsupported",
        "Dropout": "unsupported",
    },
    "akida": {
        "Input": "exact",
        "Output": "exact",
        "Linear": "approximate",
        "Affine": "approximate",
        "Conv2d": "approximate",
        "Flatten": "exact",
        "IF": "unsupported",
        "LIF": "unsupported",
        "CubaLIF": "unsupported",
        "LI": "unsupported",
        "I": "unsupported",
        "AvgPool2d": "approximate",
        "SumPool2d": "unsupported",
        "Delay": "unsupported",
        "Scale": "unsupported",
        "Threshold": "unsupported",
        "Sigmoid": "unsupported",
        "CubaLI": "unsupported",
        "Synaptic": "unsupported",
        "RSynaptic": "unsupported",
        "RLeaky": "unsupported",
        "Leaky": "unsupported",
        "BatchNorm1d": "unsupported",
        "Dropout": "unsupported",
    },
    "sc_neurocore_fpga": {
        "Input": "exact",
        "Output": "exact",
        "Linear": "exact",
        "Affine": "exact",
        "Conv2d": "unsupported",
        "Flatten": "unsupported",
        "IF": "exact",
        "LIF": "exact",
        "CubaLIF": "approximate",
        "LI": "unsupported",
        "I": "unsupported",
        "AvgPool2d": "unsupported",
        "SumPool2d": "unsupported",
        "Delay": "approximate",
        "Scale": "unsupported",
        "Threshold": "unsupported",
        "Sigmoid": "unsupported",
        "CubaLI": "unsupported",
        "Synaptic": "unsupported",
        "RSynaptic": "unsupported",
        "RLeaky": "unsupported",
        "Leaky": "unsupported",
        "BatchNorm1d": "unsupported",
        "Dropout": "unsupported",
    },
}

# ---------------------------------------------------------------------------
# Parametrized verdict test
# Validates: Requirements 1.1, 1.2, 6.1
# ---------------------------------------------------------------------------

_VERDICT_PARAMS = [
    (backend, primitive, verdict)
    for backend, sub in EXPECTED_VERDICTS.items()
    for primitive, verdict in sub.items()
]


@pytest.mark.parametrize("backend,primitive,expected", _VERDICT_PARAMS)
def test_verdict_for_primitive(backend: str, primitive: str, expected: str) -> None:
    """Assert get_supported_node_types(backend)[primitive] == expected.

    Wave 1 exploration test — run against UNFIXED code.
    The 5 snnTorch new-type rows (Affine, Conv2d, Flatten, IF, AvgPool2d)
    MUST fail before the implementation is applied (Wave 2).

    Validates: Requirements 1.1, 1.2, 6.1
    """
    table = get_supported_node_types(backend)
    actual = table.get(primitive)
    assert actual == expected, (
        f"[{backend}] {primitive}: expected {expected!r}, got {actual!r}. "
        f"Full table keys: {sorted(table)}"
    )


# ---------------------------------------------------------------------------
# Helpers to build minimal NIR graphs
# ---------------------------------------------------------------------------


def _make_exact_graph() -> nir.NIRGraph:
    """A small LIF graph that both simulators support exactly."""
    n = 2
    input_node = nir.Input(input_type=np.array([n]))
    lif = nir.LIF(
        tau=np.array([0.02] * n),
        r=np.array([1.0] * n),
        v_leak=np.array([0.0] * n),
        v_threshold=np.array([1.0] * n),
    )
    output_node = nir.Output(output_type=np.array([n]))
    weight = nir.Linear(weight=np.eye(n))
    return nir.NIRGraph(
        nodes={
            "input": input_node,
            "lif": lif,
            "weight": weight,
            "output": output_node,
        },
        edges=[("input", "weight"), ("weight", "lif"), ("lif", "output")],
    )


def _make_approximate_graph() -> nir.NIRGraph:
    """A graph that includes a Delay node (approximate for both backends)."""
    n = 2
    input_node = nir.Input(input_type=np.array([n]))
    delay = nir.Delay(delay=np.array([0.001] * n))
    lif = nir.LIF(
        tau=np.array([0.02] * n),
        r=np.array([1.0] * n),
        v_leak=np.array([0.0] * n),
        v_threshold=np.array([1.0] * n),
    )
    output_node = nir.Output(output_type=np.array([n]))
    return nir.NIRGraph(
        nodes={"input": input_node, "delay": delay, "lif": lif, "output": output_node},
        edges=[("input", "delay"), ("delay", "lif"), ("lif", "output")],
    )


def _make_unsupported_graph() -> nir.NIRGraph:
    """A graph that contains an LI node (unsupported by both simulators)."""
    n = 2
    input_node = nir.Input(input_type=np.array([n]))
    li = nir.LI(
        tau=np.array([0.02] * n),
        r=np.array([1.0] * n),
        v_leak=np.array([0.0] * n),
    )
    output_node = nir.Output(output_type=np.array([n]))
    return nir.NIRGraph(
        nodes={"input": input_node, "li": li, "output": output_node},
        edges=[("input", "li"), ("li", "output")],
    )


# ---------------------------------------------------------------------------
# classify_nir_graph
# ---------------------------------------------------------------------------


@pytest.mark.parametrize("backend", ["lava_sim", "snntorch_sim"])
def test_exact_graph_classified_as_exact(backend: str) -> None:
    graph = _make_exact_graph()
    result = classify_nir_graph(graph, backend)
    assert isinstance(result, SupportClassification)
    assert result.level == "exact"
    assert not result.unsupported_nodes
    assert not result.approximate_nodes
    assert not result.diagnostics


@pytest.mark.parametrize("backend", ["lava_sim", "snntorch_sim"])
def test_delay_graph_classified_as_approximate(backend: str) -> None:
    graph = _make_approximate_graph()
    result = classify_nir_graph(graph, backend)
    assert result.level == "approximate"
    assert "Delay" in result.approximate_nodes
    assert not result.unsupported_nodes
    assert len(result.diagnostics) >= 1
    assert any("approximate" in msg.lower() for msg in result.diagnostics)


@pytest.mark.parametrize("backend", ["lava_sim", "snntorch_sim"])
def test_unsupported_graph_classified_as_unsupported(backend: str) -> None:
    graph = _make_unsupported_graph()
    result = classify_nir_graph(graph, backend)
    assert result.level == "unsupported"
    assert len(result.unsupported_nodes) >= 1
    assert len(result.diagnostics) >= 1
    assert any(
        "unsupported" in msg.lower() or "not supported" in msg.lower()
        for msg in result.diagnostics
    )


def test_unsupported_nodes_listed_in_diagnostics() -> None:
    """Diagnostics must name the unsupported node types so users know what to fix."""
    graph = _make_unsupported_graph()
    result = classify_nir_graph(graph, "lava_sim")
    assert result.unsupported_nodes
    for node_type in result.unsupported_nodes:
        assert any(node_type in msg for msg in result.diagnostics)


def test_unknown_backend_raises_value_error() -> None:
    graph = _make_exact_graph()
    with pytest.raises(ValueError, match="Unknown simulator backend"):
        classify_nir_graph(graph, "does_not_exist")


# ---------------------------------------------------------------------------
# list_supported_backends / get_supported_node_types
# ---------------------------------------------------------------------------


def test_list_supported_backends_returns_both() -> None:
    backends = list_supported_backends()
    assert "lava_sim" in backends
    assert "snntorch_sim" in backends


def test_get_supported_node_types_lava() -> None:
    table = get_supported_node_types("lava_sim")
    assert table.get("Input") == "exact"
    assert table.get("LIF") == "exact"
    assert table.get("Linear") == "exact"
    assert table.get("Delay") == "approximate"


def test_get_supported_node_types_snntorch() -> None:
    table = get_supported_node_types("snntorch_sim")
    assert table.get("CubaLIF") == "approximate"


def test_get_supported_node_types_unknown_raises() -> None:
    with pytest.raises(ValueError, match="Unknown simulator backend"):
        get_supported_node_types("unknown_backend")


# ---------------------------------------------------------------------------
# No-fallthrough structural test (Wave 1 exploration — must FAIL against
# unfixed code because the current table has only 6 entries per backend and
# 12 primitives are absent).
# Requirements: 1.1, 1.2, 6.2
# ---------------------------------------------------------------------------


def test_no_fallthrough_all_primitives() -> None:
    """Every member of COMPLETE_PRIMITIVE_SET must be an explicit key in
    get_supported_node_types(backend) for BOTH backends.

    The test uses ``primitive in table`` (key membership) rather than
    ``table.get(primitive)`` so that primitives reaching their verdict only
    via the classifier's ``.get(type_name, "unsupported")`` default — i.e.
    primitives that are *absent* from the table — cause a failure here.

    This test is written against unfixed code and MUST fail until task 2.1
    expands _BACKEND_NIR_SUPPORT to all 18 primitives.
    """
    backends = list(EXPECTED_VERDICTS)
    missing: list[str] = []

    for backend in backends:
        table = get_supported_node_types(backend)
        for primitive in sorted(COMPLETE_PRIMITIVE_SET):
            if primitive not in table:
                missing.append(f"{backend}: {primitive!r} absent from table")

    assert not missing, (
        f"{len(missing)} primitive(s) are missing explicit keys in the backend "
        f"support table:\n" + "\n".join(f"  • {m}" for m in missing)
    )
