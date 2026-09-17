"""Tests for NIR-native CNL generation from canvas graphs.

Replaces the former test_graph_to_cnl.py tests for the deleted biological
graph_to_cnl service. NIR-type canvas nodes are serialised via NIR_Renderer.
"""

import nir
import numpy as np

from neurocnl.pipeline import generate_cnl_from_nir


def _make_lif_graph() -> nir.NIRGraph:
    """Build a minimal Input → LIF → Output graph for round-trip tests."""
    # Shape (2,): each LIF parameter must have matching size for type inference
    return nir.NIRGraph(
        nodes={
            "x": nir.Input(input_type={"input": np.array([2])}),
            "lif0": nir.LIF(
                tau=np.full(2, 0.02, dtype=np.float64),
                r=np.full(2, 1.0, dtype=np.float64),
                v_leak=np.full(2, 0.0, dtype=np.float64),
                v_threshold=np.full(2, 1.0, dtype=np.float64),
            ),
            "y": nir.Output(output_type={"output": np.array([2])}),
        },
        edges=[("x", "lif0"), ("lif0", "y")],
    )


def test_generate_cnl_from_nir_produces_nir_native_cnl() -> None:
    """generate_cnl_from_nir should produce NIR-native CNL containing LIF keyword."""
    graph = _make_lif_graph()
    cnl = generate_cnl_from_nir(graph)
    assert "leaky integrate-and-fire" in cnl.lower() or "LIF" in cnl
    # Must not contain biological vocabulary
    for token in ("MUST", "threshold_firing", "refractory_period"):
        assert token not in cnl


def test_generate_cnl_from_nir_nodes_before_edges() -> None:
    """All node sentences must appear before any connection sentence."""
    graph = _make_lif_graph()
    cnl = generate_cnl_from_nir(graph)
    lines = [
        line.strip()
        for line in cnl.splitlines()
        if line.strip() and not line.startswith("#")
    ]
    # "Define" lines are node declarations; "connects to" lines are edges
    define_indices = [i for i, line in enumerate(lines) if line.startswith("Define")]
    connect_indices = [i for i, line in enumerate(lines) if "connects to" in line]
    if define_indices and connect_indices:
        assert max(define_indices) < min(connect_indices)
