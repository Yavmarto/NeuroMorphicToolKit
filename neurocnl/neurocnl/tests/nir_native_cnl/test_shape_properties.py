"""Shape literal and auto-bias derivation property tests.

Properties implemented here:

* **Property 9** — Shape literal compiles to ``numpy.zeros(shape, dtype=float)``.
  Shape-only clauses produce Dummy_Arrays; invalid shapes raise
  ``invalid_shape`` (Requirements 2.4, 2.5, 2.7, 2.8, 4.3, 4.9, 11.1, 11.7).
* **Property 10** — Auto-bias derivation for Affine and Conv2d. Weight-only
  clauses produce zero bias vectors; explicit bias always wins
  (Requirements 11.2–11.5).
"""

from __future__ import annotations

import numpy as np
import pytest
from hypothesis import given, settings
from hypothesis import strategies as st

from neurocnl.nir_cnl.compiler import NIR_Compiler
from neurocnl.nir_cnl.errors import ParseError
from neurocnl.nir_cnl.ir_types import (
    ArraySpec,
    ArrayValues,
    EvaluationConfigRecord,
    ExportConfigRecord,
    NetworkContainer,
    NIREdgeRecord,
    NIRNodeRecord,
    TrainingConfigRecord,
)
from neurocnl.nir_cnl.parser import NIR_CNL_Parser

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


_CompilerRecord = (
    NIRNodeRecord
    | NIREdgeRecord
    | NetworkContainer
    | TrainingConfigRecord
    | EvaluationConfigRecord
    | ExportConfigRecord
)


def _io_records(in_name: str, out_name: str) -> list[_CompilerRecord]:
    """Return a minimal Input + Output + edge record list."""
    return [
        NIRNodeRecord(
            name=in_name,
            primitive="Input",
            params={"input_type": (1,)},
            metadata={},
            line=1,
        ),
        NIRNodeRecord(
            name=out_name,
            primitive="Output",
            params={"output_type": (1,)},
            metadata={},
            line=1,
        ),
        NIREdgeRecord(src=in_name, target=out_name, line=1),
    ]


# ---------------------------------------------------------------------------
# Property 9: Shape literal compiles to numpy.zeros(shape, dtype=float)
# ---------------------------------------------------------------------------


# Strategy: rank 1–4, each dim in [1, 4096], but small for speed.
_shape_strategy = st.lists(
    st.integers(min_value=1, max_value=8),
    min_size=1,
    max_size=4,
).map(tuple)


# Feature: nir-native-cnl, Property 9: Shape literal compiles to numpy.zeros(shape, dtype=float)
@given(shape=_shape_strategy)
@settings(max_examples=100, deadline=None)
def test_property_9_shape_literal_compiles_to_zeros(shape: tuple[int, ...]) -> None:
    """A shape-only clause produces ``numpy.zeros(shape, dtype=float)``.

    **Validates: Requirements 2.4, 2.5, 2.7, 2.8, 4.3, 4.9, 11.1, 11.7**
    """
    # Use Scale (scale is a vector) to test shape-only compilation.
    records: list[_CompilerRecord] = [
        NIRNodeRecord(
            name="s1",
            primitive="Scale",
            params={"scale": ArraySpec(shape=shape)},
            metadata={},
            line=1,
        ),
    ] + _io_records("inp", "outp")

    graph = NIR_Compiler().compile(records)
    scale_node = graph.nodes["s1"]
    result = scale_node.scale

    expected = np.zeros(shape, dtype=float)
    assert (
        result.shape == expected.shape
    ), f"Shape mismatch: got {result.shape!r}, expected {expected.shape!r}"
    assert np.array_equal(
        result, expected
    ), f"Value mismatch: got {result!r}, expected all-zeros array of shape {shape!r}"


@given(shape=_shape_strategy)
@settings(max_examples=100, deadline=None)
def test_property_9_shape_values_round_trips(shape: tuple[int, ...]) -> None:
    """A shape+values clause materialises to the correct array.

    **Validates: Requirements 2.5, 5.13, 11.1**
    """
    import math

    n = math.prod(shape) if shape else 1
    vals = tuple(float(i) * 0.1 for i in range(n))

    records: list[_CompilerRecord] = [
        NIRNodeRecord(
            name="s1",
            primitive="Scale",
            params={"scale": ArrayValues(shape=shape, values=vals)},
            metadata={},
            line=1,
        ),
    ] + _io_records("inp", "outp")

    graph = NIR_Compiler().compile(records)
    scale_node = graph.nodes["s1"]
    result = scale_node.scale.astype(np.float64)
    expected = np.asarray(vals, dtype=np.float64).reshape(shape)
    assert np.array_equal(
        result, expected
    ), f"Values mismatch: got {result!r}, expected {expected!r}"


@given(
    # Negative or zero dimensions are invalid.
    dim=st.one_of(
        st.integers(max_value=0),  # non-positive
        st.integers(min_value=4097),  # too large
    )
)
@settings(max_examples=100, deadline=None)
def test_property_9_invalid_shape_raises_parse_error(dim: int) -> None:
    """An invalid dimension value in a shape literal raises ``invalid_shape``.

    **Validates: Requirements 4.3, 4.9, 11.7**
    """
    cnl = (
        f"Define an input port named inp with shape (1,).\n"
        f"Define an output port named out with shape (1,).\n"
        f"Define a scale transformation named s1 with scale factor shape ({dim},).\n"
    )
    with pytest.raises(ParseError) as exc_info:
        NIR_CNL_Parser().parse(cnl)
    codes = {d.code for d in exc_info.value.errors}
    assert (
        "invalid_shape" in codes
    ), f"Expected invalid_shape for dim={dim}, got codes={codes}"


# ---------------------------------------------------------------------------
# Property 10: Auto-bias derivation for Affine and Conv2d
# ---------------------------------------------------------------------------


# Feature: nir-native-cnl, Property 10: Auto-bias derivation for Affine and Conv2d
@given(
    rows=st.integers(min_value=1, max_value=4),
    cols=st.integers(min_value=1, max_value=4),
)
@settings(max_examples=100, deadline=None)
def test_property_10_affine_auto_bias_when_no_bias_clause(rows: int, cols: int) -> None:
    """Affine with weight-only clause auto-derives zero bias of length out_channels.

    **Validates: Requirements 11.2, 11.3, 11.4**
    """
    records: list[_CompilerRecord] = [
        NIRNodeRecord(
            name="aff1",
            primitive="Affine",
            params={
                "weight": ArraySpec(shape=(rows, cols)),
                # no bias clause
            },
            metadata={},
            line=1,
        ),
    ] + _io_records("inp", "outp")

    graph = NIR_Compiler().compile(records)
    aff_node = graph.nodes["aff1"]
    bias = aff_node.bias
    expected_bias = np.zeros((rows,), dtype=float)
    assert bias.shape == (
        rows,
    ), f"Auto-derived bias shape {bias.shape!r} != expected ({rows},)"
    assert np.array_equal(
        bias.astype(np.float64), expected_bias
    ), f"Auto-derived bias {bias!r} is not all-zeros"


@given(
    rows=st.integers(min_value=1, max_value=4),
    cols=st.integers(min_value=1, max_value=4),
)
@settings(max_examples=100, deadline=None)
def test_property_10_affine_explicit_bias_wins(rows: int, cols: int) -> None:
    """Affine with both weight and bias uses the explicit bias, not auto-derivation.

    **Validates: Requirements 11.2, 11.4, 11.5**
    """
    explicit_bias_vals = tuple(float(i + 1) for i in range(rows))
    records: list[_CompilerRecord] = [
        NIRNodeRecord(
            name="aff1",
            primitive="Affine",
            params={
                "weight": ArraySpec(shape=(rows, cols)),
                "bias": ArrayValues(shape=(rows,), values=explicit_bias_vals),
            },
            metadata={},
            line=1,
        ),
    ] + _io_records("inp", "outp")

    graph = NIR_Compiler().compile(records)
    aff_node = graph.nodes["aff1"]
    bias = aff_node.bias.astype(np.float64)
    expected = np.asarray(explicit_bias_vals, dtype=np.float64)
    assert np.array_equal(
        bias, expected
    ), f"Explicit bias {bias!r} does not match expected {expected!r}"


@given(
    out_ch=st.integers(min_value=1, max_value=4),
    in_ch=st.integers(min_value=1, max_value=4),
    kH=st.integers(min_value=1, max_value=3),
    kW=st.integers(min_value=1, max_value=3),
)
@settings(max_examples=100, deadline=None)
def test_property_10_conv2d_auto_bias_when_no_bias_clause(
    out_ch: int, in_ch: int, kH: int, kW: int
) -> None:
    """Conv2d with weight-only clause auto-derives zero bias of length out_channels.

    **Validates: Requirements 11.2, 11.3, 11.4**
    """
    records: list[_CompilerRecord] = [
        NIRNodeRecord(
            name="c2",
            primitive="Conv2d",
            params={
                "weight": ArraySpec(shape=(out_ch, in_ch, kH, kW)),
                # no bias clause
                "stride": (1, 1),
                "padding": (0, 0),
                "dilation": (1, 1),
                "groups": 1,
                "input_shape": (4, 4),
            },
            metadata={},
            line=1,
        ),
    ] + _io_records("inp", "outp")

    graph = NIR_Compiler().compile(records)
    conv_node = graph.nodes["c2"]
    bias = conv_node.bias
    expected_bias = np.zeros((out_ch,), dtype=float)
    assert bias.shape == (
        out_ch,
    ), f"Auto-derived Conv2d bias shape {bias.shape!r} != expected ({out_ch},)"
    assert np.array_equal(
        bias.astype(np.float64), expected_bias
    ), f"Auto-derived Conv2d bias {bias!r} is not all-zeros"


@given(
    out_ch=st.integers(min_value=1, max_value=4),
    in_ch=st.integers(min_value=1, max_value=4),
    kH=st.integers(min_value=1, max_value=3),
    kW=st.integers(min_value=1, max_value=3),
)
@settings(max_examples=100, deadline=None)
def test_property_10_conv2d_explicit_bias_wins(
    out_ch: int, in_ch: int, kH: int, kW: int
) -> None:
    """Conv2d with both weight and bias uses the explicit bias, not auto-derivation.

    **Validates: Requirements 11.2, 11.4, 11.5**
    """
    explicit_bias_vals = tuple(float(i + 1) for i in range(out_ch))
    records: list[_CompilerRecord] = [
        NIRNodeRecord(
            name="c2",
            primitive="Conv2d",
            params={
                "weight": ArraySpec(shape=(out_ch, in_ch, kH, kW)),
                "bias": ArrayValues(shape=(out_ch,), values=explicit_bias_vals),
                "stride": (1, 1),
                "padding": (0, 0),
                "dilation": (1, 1),
                "groups": 1,
                "input_shape": (4, 4),
            },
            metadata={},
            line=1,
        ),
    ] + _io_records("inp", "outp")

    graph = NIR_Compiler().compile(records)
    conv_node = graph.nodes["c2"]
    bias = conv_node.bias.astype(np.float64)
    expected = np.asarray(explicit_bias_vals, dtype=np.float64)
    assert np.array_equal(
        bias, expected
    ), f"Explicit Conv2d bias {bias!r} does not match expected {expected!r}"
