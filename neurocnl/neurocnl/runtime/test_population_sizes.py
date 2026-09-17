"""Tests for LIF population width reconciliation from Linear weights."""

from __future__ import annotations

import nir
import numpy as np

from neurocnl.runtime.population_sizes import (
    lif_population_size,
    reconcile_population_sizes_from_linear_weights,
)


def _scalar_lif(**kwargs: object) -> nir.LIF:
    defaults = {
        "tau": np.float64(0.01),
        "r": np.float64(1.0),
        "v_leak": np.float64(0.0),
        "v_threshold": np.float64(0.5),
    }
    defaults.update(kwargs)
    return nir.LIF(**defaults)


def test_lif_population_size_reads_scalar_tau_as_one() -> None:
    assert lif_population_size(_scalar_lif()) == 1


def test_reconcile_widens_scalar_lif_from_linear_weights() -> None:
    graph = nir.NIRGraph(
        nodes={
            "input": nir.Input(input_type={"input": np.array([1])}),
            "sensor": _scalar_lif(),
            "w_sensor_interneuron": nir.Linear(weight=np.ones((30, 1), dtype=float)),
            "interneuron": _scalar_lif(),
            "output": nir.Output(output_type={"output": np.array([30])}),
        },
        edges=[
            ("input", "sensor"),
            ("sensor", "w_sensor_interneuron"),
            ("w_sensor_interneuron", "interneuron"),
            ("interneuron", "output"),
        ],
        type_check=False,
    )
    sizes = {
        "sensor": lif_population_size(graph.nodes["sensor"]),
        "interneuron": lif_population_size(graph.nodes["interneuron"]),
    }
    reconciled = reconcile_population_sizes_from_linear_weights(graph, sizes)
    assert reconciled["sensor"] == 1
    assert reconciled["interneuron"] == 30
