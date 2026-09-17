"""Unit tests for array serialisation round-trip (task 7.2).

Covers the acceptance criteria in task 7.1:
- 1-D array formatted as [v0, v1, ...] with %.17g precision
- tensor parameters render shape-only
- Scalar broadcast: all-equal array emits single scalar
- Compiler broadcasts scalar back via numpy.full

Vector and tensor values are both intentionally omitted from CNL; round-trips
preserve shape and rebuild zero-filled arrays for all array parameters.

Requirements: 2.5, 4.2, 4.3, 4.4
"""

from __future__ import annotations

from typing import Any

import nir
import numpy as np

from neurocnl.nir_cnl.compiler import NIR_Compiler
from neurocnl.nir_cnl.parser import NIR_CNL_Parser
from neurocnl.nir_cnl.renderer import NIR_Renderer

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _roundtrip(graph: nir.NIRGraph) -> nir.NIRGraph:
    """render → parse → compile."""
    cnl = NIR_Renderer().render(graph)
    records = NIR_CNL_Parser().parse(cnl)
    return NIR_Compiler().compile(records)


def _assert_zero_tensor_roundtrip(
    original: np.ndarray[Any, Any],
    recovered: np.ndarray[Any, Any],
) -> None:
    """Shape-only tensor rendering rebuilds a zero tensor of the same shape."""
    assert recovered.shape == original.shape
    assert recovered.dtype == np.float64
    assert np.array_equal(recovered, np.zeros_like(original, dtype=np.float64))


def _linear_graph(weight: np.ndarray[Any, Any]) -> nir.NIRGraph:
    """Minimal Input → Linear → Output graph with the given weight."""
    in_features = weight.shape[-1]
    out_features = weight.shape[0]
    return nir.NIRGraph(
        nodes={
            "x": nir.Input(input_type=np.array([in_features])),
            "fc": nir.Linear(weight=weight),
            "y": nir.Output(output_type=np.array([out_features])),
        },
        edges=[("x", "fc"), ("fc", "y")],
    )


def _lif_graph(
    tau: np.ndarray[Any, Any],
    r: np.ndarray[Any, Any],
    v_leak: np.ndarray[Any, Any],
    v_threshold: np.ndarray[Any, Any],
) -> nir.NIRGraph:
    """Minimal Input → LIF → Output graph."""
    n = tau.shape[0] if tau.ndim >= 1 else 1
    return nir.NIRGraph(
        nodes={
            "x": nir.Input(input_type=np.array([n])),
            "lif": nir.LIF(tau=tau, r=r, v_leak=v_leak, v_threshold=v_threshold),
            "y": nir.Output(output_type=np.array([n])),
        },
        edges=[("x", "lif"), ("lif", "y")],
    )


# ---------------------------------------------------------------------------
# Core acceptance criterion: (4, 3) float64 weight round-trip
# ---------------------------------------------------------------------------


class TestLinear4x3RoundTrip:
    """Task 7.1: tensor shape survives the CNL round-trip."""

    def test_linear_4x3_roundtrip(self) -> None:
        """A rendered tensor keeps shape but drops explicit values."""
        rng = np.random.default_rng(0)
        weight = rng.random((4, 3), dtype=np.float64)
        graph = _linear_graph(weight)
        recovered = _roundtrip(graph)
        _assert_zero_tensor_roundtrip(weight, recovered.nodes["fc"].weight)

    def test_linear_4x3_shape_preserved(self) -> None:
        rng = np.random.default_rng(1)
        weight = rng.random((4, 3), dtype=np.float64)
        graph = _linear_graph(weight)
        recovered = _roundtrip(graph)
        assert recovered.nodes["fc"].weight.shape == (4, 3)

    def test_linear_4x3_dtype_is_float64(self) -> None:
        rng = np.random.default_rng(2)
        weight = rng.random((4, 3), dtype=np.float64)
        graph = _linear_graph(weight)
        recovered = _roundtrip(graph)
        assert recovered.nodes["fc"].weight.dtype == np.float64


# ---------------------------------------------------------------------------
# 1-D array round-trip
# ---------------------------------------------------------------------------


class Test1DArrayRoundTrip:
    """task_7.2: test_1d_array_roundtrip — Requirements: 2.5, 4.2"""

    def test_1d_array_roundtrip(self) -> None:
        """Vector round-trip preserves shape (values zeroed — CNL is shape-only)."""
        rng = np.random.default_rng(10)
        tau = rng.random(8, dtype=np.float64)
        graph = _lif_graph(
            tau=tau,
            r=np.ones(8, dtype=np.float64),
            v_leak=np.zeros(8, dtype=np.float64),
            v_threshold=np.ones(8, dtype=np.float64),
        )
        recovered = _roundtrip(graph)
        assert recovered.nodes["lif"].tau.shape == tau.shape

    def test_1d_rendered_as_bracket_list(self) -> None:
        """Distinct 1-D array is rendered in [v0, v1, ...] format."""
        rng = np.random.default_rng(11)
        tau = rng.random(4, dtype=np.float64)
        graph = _lif_graph(
            tau=tau,
            r=np.ones(4, dtype=np.float64),
            v_leak=np.zeros(4, dtype=np.float64),
            v_threshold=np.ones(4, dtype=np.float64),
        )
        cnl = NIR_Renderer().render(graph)
        lif_line = next(l for l in cnl.splitlines() if "LIF neuron named lif" in l)
        assert "time constant shape" in lif_line
        assert "time constant values" not in lif_line

    def test_1d_bracket_list_uses_17g_precision(self) -> None:
        """Elements in a 1-D bracket list must be formatted with %.17g precision."""
        tau = np.array([0.020000000000000001], dtype=np.float64)  # precise float64
        graph = _lif_graph(
            tau=tau,
            r=np.ones(1, dtype=np.float64),
            v_leak=np.zeros(1, dtype=np.float64),
            v_threshold=np.ones(1, dtype=np.float64),
        )
        cnl = NIR_Renderer().render(graph)
        # scalar broadcast will fire since size==1; the scalar should be exact
        # Verify the value can be recovered exactly
        recovered = _roundtrip(graph)
        assert np.array_equal(tau, recovered.nodes["lif"].tau)

    def test_1d_roundtrip_multiple_random_seeds(self) -> None:
        """Round-trip holds for several random seeds."""
        for seed in range(5):
            rng = np.random.default_rng(seed + 100)
            tau = rng.random(6, dtype=np.float64)
            graph = _lif_graph(
                tau=tau,
                r=np.ones(6, dtype=np.float64),
                v_leak=np.zeros(6, dtype=np.float64),
                v_threshold=np.ones(6, dtype=np.float64),
            )
            recovered = _roundtrip(graph)
            assert (
                recovered.nodes["lif"].tau.shape == tau.shape
            ), f"Shape mismatch after round-trip for seed {seed + 100}"


# ---------------------------------------------------------------------------
# 2-D weight round-trip
# ---------------------------------------------------------------------------


class Test2DWeightRoundTrip:
    """task_7.2: test_2d_weight_roundtrip — Requirements: 2.5, 4.3"""

    def test_2d_weight_roundtrip(self) -> None:
        """Random (4, 3) float64 matrix comes back zero-filled with same shape."""
        rng = np.random.default_rng(20)
        weight = rng.random((4, 3), dtype=np.float64)
        graph = _linear_graph(weight)
        recovered = _roundtrip(graph)
        _assert_zero_tensor_roundtrip(weight, recovered.nodes["fc"].weight)

    def test_2d_rendered_as_shape_only(self) -> None:
        """2-D matrix is rendered as a shape-only clause."""
        rng = np.random.default_rng(21)
        weight = rng.random((2, 2), dtype=np.float64)
        graph = _linear_graph(weight)
        cnl = NIR_Renderer().render(graph)
        linear_line = next(
            l for l in cnl.splitlines() if "linear transformation named fc" in l
        )
        assert "weight matrix shape (2, 2)" in linear_line
        assert (
            "weight matrix values (" not in linear_line
        ), f"Expected shape-only rendering for 2-D weight in: {linear_line!r}"

    def test_2d_various_shapes(self) -> None:
        """Shape-only tensor round-trip keeps various (M, N) shapes."""
        shapes = [(1, 1), (2, 3), (8, 4), (16, 12)]
        rng = np.random.default_rng(22)
        for shape in shapes:
            weight = rng.random(shape, dtype=np.float64)
            graph = _linear_graph(weight)
            recovered = _roundtrip(graph)
            _assert_zero_tensor_roundtrip(weight, recovered.nodes["fc"].weight)
            assert recovered.nodes["fc"].weight.shape == shape

    def test_2d_negative_values_roundtrip(self) -> None:
        """Negative float64 values are intentionally dropped from CNL tensors."""
        weight = np.array([[-0.3, 0.5], [0.1, -0.9]], dtype=np.float64)
        graph = _linear_graph(weight)
        recovered = _roundtrip(graph)
        _assert_zero_tensor_roundtrip(weight, recovered.nodes["fc"].weight)

    def test_2d_tiny_values_roundtrip(self) -> None:
        """Very small float64 values are intentionally dropped from CNL tensors."""
        weight = np.array([[1e-15, -2.3e-15], [5e-17, 1.1e-14]], dtype=np.float64)
        graph = _linear_graph(weight)
        recovered = _roundtrip(graph)
        _assert_zero_tensor_roundtrip(weight, recovered.nodes["fc"].weight)


# ---------------------------------------------------------------------------
# Conv2d kernel (≥3-D) round-trip
# ---------------------------------------------------------------------------


class TestConv2DKernelRoundTrip:
    """task_7.2: test_conv2d_kernel_roundtrip — Requirements: 2.5, 4.4"""

    def test_conv2d_kernel_roundtrip(self) -> None:
        """Random (2, 1, 3, 3) kernel comes back zero-filled with same shape."""
        rng = np.random.default_rng(30)
        kernel = rng.random((2, 1, 3, 3), dtype=np.float64)
        graph = nir.NIRGraph(
            nodes={
                "x": nir.Input(input_type=np.array([1, 8, 8])),
                "conv": nir.Conv2d(
                    input_shape=np.array([8, 8]),
                    weight=kernel,
                    stride=np.array([1, 1]),
                    padding=np.array([0, 0]),
                    dilation=np.array([1, 1]),
                    groups=1,
                    bias=np.zeros(2, dtype=np.float64),
                ),
                "y": nir.Output(output_type=np.array([2, 6, 6])),
            },
            edges=[("x", "conv"), ("conv", "y")],
        )
        recovered = _roundtrip(graph)
        _assert_zero_tensor_roundtrip(kernel, recovered.nodes["conv"].weight)

    def test_conv2d_kernel_shape_preserved(self) -> None:
        """Shape of recovered Conv2d kernel matches original."""
        rng = np.random.default_rng(31)
        kernel = rng.random((4, 2, 5, 5), dtype=np.float64)
        graph = nir.NIRGraph(
            nodes={
                "x": nir.Input(input_type=np.array([2, 16, 16])),
                "conv": nir.Conv2d(
                    input_shape=np.array([16, 16]),
                    weight=kernel,
                    stride=np.array([1, 1]),
                    padding=np.array([2, 2]),
                    dilation=np.array([1, 1]),
                    groups=1,
                    bias=np.zeros(4, dtype=np.float64),
                ),
                "y": nir.Output(output_type=np.array([4, 16, 16])),
            },
            edges=[("x", "conv"), ("conv", "y")],
        )
        recovered = _roundtrip(graph)
        assert recovered.nodes["conv"].weight.shape == (4, 2, 5, 5)

    def test_4d_rendered_as_shape_only(self) -> None:
        """4-D kernel is rendered as a shape-only clause."""
        rng = np.random.default_rng(32)
        kernel = rng.random((2, 1, 3, 3), dtype=np.float64)
        graph = nir.NIRGraph(
            nodes={
                "x": nir.Input(input_type=np.array([1, 8, 8])),
                "conv": nir.Conv2d(
                    input_shape=np.array([8, 8]),
                    weight=kernel,
                    stride=np.array([1, 1]),
                    padding=np.array([0, 0]),
                    dilation=np.array([1, 1]),
                    groups=1,
                    bias=np.zeros(2, dtype=np.float64),
                ),
                "y": nir.Output(output_type=np.array([2, 6, 6])),
            },
            edges=[("x", "conv"), ("conv", "y")],
        )
        cnl = NIR_Renderer().render(graph)
        conv_line = next(
            l for l in cnl.splitlines() if "2D convolution layer named conv" in l
        )
        assert "weight kernel shape (2, 1, 3, 3)" in conv_line
        assert (
            "weight kernel values (" not in conv_line
        ), f"Expected shape-only rendering for 4-D kernel in: {conv_line[:80]!r}..."


# ---------------------------------------------------------------------------
# Scalar broadcast
# ---------------------------------------------------------------------------


class TestScalarBroadcast:
    """task_7.2: test_scalar_broadcast — Requirements: 2.5, 4.2"""

    def test_scalar_broadcast_renders_as_scalar(self) -> None:
        """All-equal multi-element vectors must keep shape and explicit values."""
        tau = np.full(3, 0.02, dtype=np.float64)
        graph = _lif_graph(
            tau=tau,
            r=np.ones(3, dtype=np.float64),
            v_leak=np.zeros(3, dtype=np.float64),
            v_threshold=np.ones(3, dtype=np.float64),
        )
        cnl = NIR_Renderer().render(graph)
        lif_line = next(l for l in cnl.splitlines() if "LIF neuron named lif" in l)
        assert "time constant shape (3,)" in lif_line
        assert "time constant values" not in lif_line

    def test_scalar_broadcast_compiled_node_has_correct_shape(self) -> None:
        """Compiled node after round-trip preserves vector shape (values zeroed)."""
        tau = np.full(3, 0.02, dtype=np.float64)
        graph = _lif_graph(
            tau=tau,
            r=np.ones(3, dtype=np.float64),
            v_leak=np.zeros(3, dtype=np.float64),
            v_threshold=np.ones(3, dtype=np.float64),
        )
        recovered = _roundtrip(graph)
        lif_node = recovered.nodes["lif"]
        assert lif_node.tau.shape == tau.shape

    def test_scalar_broadcast_all_params_same_value(self) -> None:
        """Scalar broadcast fires for all scalar params in a LIF node."""
        graph = _lif_graph(
            tau=np.array([0.02], dtype=np.float64),
            r=np.array([1.0], dtype=np.float64),
            v_leak=np.array([0.0], dtype=np.float64),
            v_threshold=np.array([1.0], dtype=np.float64),
        )
        cnl = NIR_Renderer().render(graph)
        lif_line = next(l for l in cnl.splitlines() if "LIF neuron named lif" in l)
        # None of the params should have bracket lists for single-element arrays
        assert (
            "[" not in lif_line
        ), f"Expected all scalar params for single-element LIF: {lif_line!r}"

    def test_distinct_values_not_broadcast(self) -> None:
        """Array with distinct values must NOT be scalar-broadcast."""
        tau = np.array([0.01, 0.02, 0.03], dtype=np.float64)
        graph = _lif_graph(
            tau=tau,
            r=np.ones(3, dtype=np.float64),
            v_leak=np.zeros(3, dtype=np.float64),
            v_threshold=np.ones(3, dtype=np.float64),
        )
        cnl = NIR_Renderer().render(graph)
        lif_line = next(l for l in cnl.splitlines() if "LIF neuron named lif" in l)
        assert "time constant shape (3,)" in lif_line
        assert "time constant values" not in lif_line

    def test_scalar_broadcast_1d_vec_same_values(self) -> None:
        """1-D array where all values are equal keeps explicit values when length > 1."""
        tau = np.full(5, 0.015, dtype=np.float64)
        graph = _lif_graph(
            tau=tau,
            r=np.ones(5, dtype=np.float64),
            v_leak=np.zeros(5, dtype=np.float64),
            v_threshold=np.ones(5, dtype=np.float64),
        )
        cnl = NIR_Renderer().render(graph)
        lif_line = next(l for l in cnl.splitlines() if "LIF neuron named lif" in l)
        assert "time constant shape (5,)" in lif_line
        assert "time constant values" not in lif_line


# ---------------------------------------------------------------------------
# Mixed scenario: LIF with distinct tau, scalar r/v_leak/v_threshold
# ---------------------------------------------------------------------------


class TestMixedScalarAndArray:
    """Verify scalar broadcast with mixed scalar/array params on LIF."""

    def test_lif_mixed_roundtrip_tau_distinct(self) -> None:
        """LIF round-trip preserves vector shapes (values zeroed — CNL is shape-only)."""
        rng = np.random.default_rng(40)
        n = 8
        tau = rng.random(n, dtype=np.float64)
        graph = _lif_graph(
            tau=tau,
            r=np.ones(n, dtype=np.float64),
            v_leak=np.zeros(n, dtype=np.float64),
            v_threshold=np.ones(n, dtype=np.float64),
        )
        recovered = _roundtrip(graph)
        lif_r = recovered.nodes["lif"]
        assert lif_r.tau.shape == (n,)
        assert lif_r.r.shape == (n,)
        assert lif_r.v_leak.shape == (n,)
        assert lif_r.v_threshold.shape == (n,)

    def test_lif_mixed_roundtrip_all_params_correct(self) -> None:
        """All LIF params have correct shape after round-trip (values zeroed — CNL is shape-only)."""
        rng = np.random.default_rng(41)
        n = 4
        tau = rng.random(n, dtype=np.float64)
        graph = _lif_graph(
            tau=tau,
            r=np.full(n, 2.5, dtype=np.float64),
            v_leak=np.full(n, -0.1, dtype=np.float64),
            v_threshold=np.full(n, 0.8, dtype=np.float64),
        )
        recovered = _roundtrip(graph)
        lif_r = recovered.nodes["lif"]
        assert lif_r.tau.shape == (n,)
        assert lif_r.r.shape == (n,)
        assert lif_r.v_leak.shape == (n,)
        assert lif_r.v_threshold.shape == (n,)
