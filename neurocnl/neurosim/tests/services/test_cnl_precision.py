"""Tests for NIR-native CNL float64 precision in render → parse → compile round-trips.

The former biological graph_to_cnl precision tests have been migrated to the
NIR-native round-trip path using NIR_Renderer and NIR_CNL_Parser.
"""

import nir
import numpy as np
import pytest

from neurocnl.nir_cnl.compiler import NIR_Compiler
from neurocnl.nir_cnl.parser import NIR_CNL_Parser
from neurocnl.nir_cnl.renderer import NIR_Renderer


def _roundtrip(nir_graph: nir.NIRGraph) -> nir.NIRGraph:
    renderer = NIR_Renderer()
    parser = NIR_CNL_Parser()
    compiler = NIR_Compiler()
    cnl = renderer.render(nir_graph)
    records = parser.parse(cnl)
    return compiler.compile(records)


def test_lif_scalar_roundtrip_preserves_float64_precision() -> None:
    """LIF scalar params should survive render → parse → compile exactly."""
    tau_val = 0.019999999999999997  # high-precision float64
    graph = nir.NIRGraph(
        nodes={
            "x": nir.Input(input_type={"input": np.array([1])}),
            "lif0": nir.LIF(
                tau=np.array([tau_val], dtype=np.float64),
                r=np.array([1.0], dtype=np.float64),
                v_leak=np.array([0.0], dtype=np.float64),
                v_threshold=np.array([1.0], dtype=np.float64),
            ),
            "y": nir.Output(output_type={"output": np.array([1])}),
        },
        edges=[("x", "lif0"), ("lif0", "y")],
    )

    recovered = _roundtrip(graph)
    assert recovered.nodes["lif0"].tau == pytest.approx(tau_val, rel=1e-15)


def test_linear_weight_matrix_roundtrip_preserves_shape_only() -> None:
    """Weight matrices render back as zero-filled tensors with the same shape."""
    weights = np.array([[1.5e-3, -2.7e-4], [0.12345678901234567, 9.87e-9]])
    graph = nir.NIRGraph(
        nodes={
            "x": nir.Input(input_type={"input": np.array([2])}),
            "fc": nir.Linear(weight=weights),
            "y": nir.Output(output_type={"output": np.array([2])}),
        },
        edges=[("x", "fc"), ("fc", "y")],
    )

    recovered = _roundtrip(graph)
    assert recovered.nodes["fc"].weight.shape == weights.shape
    assert np.array_equal(recovered.nodes["fc"].weight, np.zeros_like(weights))


def test_scalar_broadcast_roundtrip() -> None:
    """Scalar-broadcast arrays should round-trip to the correct scalar value."""
    tau_arr = np.full(4, 0.02, dtype=np.float64)
    graph = nir.NIRGraph(
        nodes={
            "x": nir.Input(input_type={"input": np.array([4])}),
            "lif0": nir.LIF(
                tau=tau_arr,
                r=np.full(4, 1.0, dtype=np.float64),
                v_leak=np.full(4, 0.0, dtype=np.float64),
                v_threshold=np.full(4, 1.0, dtype=np.float64),
            ),
            "y": nir.Output(output_type={"output": np.array([4])}),
        },
        edges=[("x", "lif0"), ("lif0", "y")],
    )

    cnl = NIR_Renderer().render(graph)
    # When all elements are equal the renderer should emit a scalar broadcast
    assert "0.02" in cnl

    recovered = _roundtrip(graph)
    # After compilation tau may be a scalar or 1D array depending on broadcast
    node = recovered.nodes["lif0"]
    tau = node.tau
    if hasattr(tau, "__iter__"):
        assert all(abs(v - 0.02) < 1e-15 for v in np.asarray(tau).flat)
    else:
        assert abs(float(tau) - 0.02) < 1e-15
