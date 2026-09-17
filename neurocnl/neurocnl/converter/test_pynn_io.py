"""Tests for PyNNIO.from_nir() — no test file previously existed for this converter."""

from __future__ import annotations

import nir
import numpy as np
import pytest

from neurocnl.converter.pynn_io import PyNNIO


def _lif_graph() -> nir.NIRGraph:
    n = 2
    return nir.NIRGraph(
        nodes={
            "input": nir.Input(input_type={"input": np.array([n])}),
            "fc": nir.Linear(weight=np.eye(n)),
            "lif": nir.LIF(
                tau=np.full(n, 0.02),
                r=np.ones(n),
                v_leak=np.zeros(n),
                v_threshold=np.ones(n),
            ),
            "output": nir.Output(output_type={"output": np.array([n])}),
        },
        edges=[("input", "fc"), ("fc", "lif"), ("lif", "output")],
        type_check=False,
    )


def test_lif_graph_produces_pynn_population_code() -> None:
    code = PyNNIO().from_nir(_lif_graph())
    assert "sim.Population(" in code
    assert "sim.IF_curr_exp(" in code


def test_unsupported_node_type_raises() -> None:
    """Unrecognized NIR node types must raise loudly, not silently skip."""
    graph = nir.NIRGraph(
        nodes={
            "input": nir.Input(input_type={"input": np.array([2])}),
            "flat": nir.Flatten(
                input_type={"input": np.array([2])},
                start_dim=1,
                end_dim=-1,
            ),
            "output": nir.Output(output_type={"output": np.array([2])}),
        },
        edges=[("input", "flat"), ("flat", "output")],
        type_check=False,
    )
    with pytest.raises(NotImplementedError, match="not supported in PyNNIO"):
        PyNNIO().from_nir(graph)


def test_input_output_only_graph_does_not_raise() -> None:
    graph = nir.NIRGraph(
        nodes={
            "input": nir.Input(input_type={"input": np.array([2])}),
            "output": nir.Output(output_type={"output": np.array([2])}),
        },
        edges=[("input", "output")],
        type_check=False,
    )
    PyNNIO().from_nir(graph)  # must not raise
