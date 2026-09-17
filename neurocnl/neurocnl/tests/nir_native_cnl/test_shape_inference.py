"""Characterization tests for extracted compiler shape inference."""

import nir
import numpy as np

from neurocnl.nir_cnl import compiler
from neurocnl.nir_cnl.ir_types import NIREdgeRecord
from neurocnl.nir_cnl.shape_inference import (
    infer_known_shapes,
    pair,
    shape_tuple,
)


def test_compiler_keeps_shape_inference_compatibility_aliases() -> None:
    assert compiler._shape_tuple is shape_tuple
    assert compiler._pair is pair
    assert compiler._infer_known_shapes is infer_known_shapes


def test_shape_normalization_handles_port_dicts_and_scalar_pairs() -> None:
    assert shape_tuple({"input": np.asarray([2, 3])}) == (2, 3)
    assert shape_tuple({}) is None
    assert pair(np.asarray([4]), (1, 1)) == (4, 4)


def test_known_shapes_propagate_through_shape_preserving_node() -> None:
    nodes = {
        "input": nir.Input(input_type={"input": np.asarray([3])}),
        "output": nir.Output(output_type={"output": np.asarray([3])}),
    }
    edges = [NIREdgeRecord(src="input", target="output", line=1)]

    assert infer_known_shapes(nodes, edges) == {"input": (3,), "output": (3,)}
