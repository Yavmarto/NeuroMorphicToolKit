"""Smoke tests for the Nengo simulator adapter."""

from __future__ import annotations

import nir
import numpy as np
import pytest

from neurocnl.runtime.nengo_simulator import NengoSimulatorAdapter
from neurocnl.runtime.stimulus import ValidatedStimulus


def _simple_graph() -> nir.NIRGraph:
    return nir.NIRGraph(
        nodes={
            "input": nir.Input(input_type={"input": np.array([2])}),
            "fc": nir.Linear(weight=np.ones((3, 2))),
            "cuba": nir.CubaLIF(
                tau_syn=np.array([0.01, 0.01, 0.01]),
                tau_mem=np.array([0.02, 0.02, 0.02]),
                r=np.array([1.0, 1.0, 1.0]),
                v_leak=np.array([0.0, 0.0, 0.0]),
                v_threshold=np.array([0.5, 0.5, 0.5]),
                w_in=np.array([1.0, 1.0, 1.0]),
            ),
            "output": nir.Output(output_type={"output": np.array([3])}),
        },
        edges=[("input", "fc"), ("fc", "cuba"), ("cuba", "output")],
        type_check=False,
    )


def test_nengo_simulator_returns_spike_payload() -> None:
    pytest.importorskip("nengo")
    graph = _simple_graph()
    stimulus = ValidatedStimulus(
        population="input",
        neuron_count=2,
        spikes={0: [0, 1, 2], 1: [0, 1, 2]},
    )
    result = NengoSimulatorAdapter().run(
        graph,
        stimulus,
        timesteps=20,
        seed=1,
        dt_ms=0.1,
    )
    assert "cuba" in result.spikes
    assert isinstance(result.spikes["cuba"], dict)
