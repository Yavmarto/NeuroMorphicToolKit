"""Tests for widening CNL-compiled neuron parameters to their layer width."""

from __future__ import annotations

import io
from pathlib import Path
from typing import TYPE_CHECKING

import numpy as np
import pytest

if TYPE_CHECKING:
    import nir
else:
    nir = pytest.importorskip("nir")

from neurocnl.export.nir_shapes import broadcast_neuron_parameters, neuron_widths


def _mnist_graph_with_scalar_neurons() -> nir.NIRGraph:
    """A 784 → 256 → 10 chain exactly as the NIR Exporter writes it.

    Every LIF carries one-element parameter arrays because CNL states them once
    for the layer, which is the shape that makes NIR read the layer as a single
    neuron.
    """

    def lif() -> nir.LIF:
        one = np.array([1.0])
        return nir.LIF(
            tau=np.array([0.002]), r=one, v_leak=np.array([0.0]), v_threshold=one
        )

    nodes = {
        "nir.Input_1": nir.Input(input_type={"input": np.array([784])}),
        "nir.LIF_1": lif(),
        "nir.Linear_1": nir.Linear(weight=np.zeros((256, 784), dtype=np.float32)),
        "nir.LIF_2": lif(),
        "nir.Linear_2": nir.Linear(weight=np.zeros((10, 256), dtype=np.float32)),
        "nir.LIF_3": lif(),
        "nir.Output_1": nir.Output(output_type={"output": np.array([10])}),
    }
    edges = [
        ("nir.Input_1", "nir.LIF_1"),
        ("nir.LIF_1", "nir.Linear_1"),
        ("nir.Linear_1", "nir.LIF_2"),
        ("nir.LIF_2", "nir.Linear_2"),
        ("nir.Linear_2", "nir.LIF_3"),
        ("nir.LIF_3", "nir.Output_1"),
    ]
    return nir.NIRGraph(nodes=nodes, edges=edges, type_check=False)


def test_widths_come_from_ports_and_weight_matrices() -> None:
    """A neuron's own type is the value in question and must not seed itself."""
    widths = neuron_widths(_mnist_graph_with_scalar_neurons())

    assert widths["nir.LIF_1"] == 784
    assert widths["nir.LIF_2"] == 256
    assert widths["nir.LIF_3"] == 10


def test_broadcast_makes_a_cnl_compiled_graph_type_check() -> None:
    """The graph NIR previously refused with "Input.output: [[784]] -> LIF.input: [[1]]"."""
    graph = broadcast_neuron_parameters(_mnist_graph_with_scalar_neurons())

    # Constructing with type_check=True is the check that used to fail.
    nir.NIRGraph(nodes=graph.nodes, edges=graph.edges, type_check=True)
    assert graph.nodes["nir.LIF_1"].tau.shape == (784,)
    assert graph.nodes["nir.LIF_2"].v_threshold.shape == (256,)


def test_broadcast_repeats_the_value_rather_than_inventing_one() -> None:
    graph = broadcast_neuron_parameters(_mnist_graph_with_scalar_neurons())

    assert np.allclose(graph.nodes["nir.LIF_1"].tau, 0.002)
    assert np.allclose(graph.nodes["nir.LIF_3"].v_threshold, 1.0)


def test_already_wide_parameters_are_left_alone() -> None:
    graph = _mnist_graph_with_scalar_neurons()
    graph.nodes["nir.LIF_2"].tau = np.full((256,), 0.004)

    broadcast_neuron_parameters(graph)

    assert np.allclose(graph.nodes["nir.LIF_2"].tau, 0.004)


def test_written_graph_round_trips_through_nir_read(tmp_path: Path) -> None:
    """The end the artifact is actually consumed by: `nir.read` with type checks."""
    graph = broadcast_neuron_parameters(_mnist_graph_with_scalar_neurons())
    path = tmp_path / "model.nir"
    nir.write(str(path), graph)

    reloaded = nir.read(io.BytesIO(path.read_bytes()))

    assert reloaded.nodes["nir.LIF_1"].tau.shape == (784,)
