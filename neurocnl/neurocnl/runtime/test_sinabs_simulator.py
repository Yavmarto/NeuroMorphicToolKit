"""Smoke tests for the Sinabs simulator adapter."""

from __future__ import annotations

import nir
import numpy as np
import pytest

from neurocnl.runtime.sinabs_simulator import SinabsSimulatorAdapter
from neurocnl.runtime.stimulus import ValidatedStimulus


def _sequential_graph() -> nir.NIRGraph:
    return nir.NIRGraph(
        nodes={
            "input": nir.Input(input_type={"input": np.array([2])}),
            "fc": nir.Linear(weight=np.full((3, 2), 0.5)),
            "lif": nir.LIF(
                tau=np.full(3, 10.0),
                r=np.ones(3),
                v_leak=np.zeros(3),
                v_threshold=np.ones(3),
            ),
            "output": nir.Output(output_type={"output": np.array([3])}),
        },
        edges=[("input", "fc"), ("fc", "lif"), ("lif", "output")],
        type_check=False,
    )


def test_sinabs_simulator_runs_sequential_graph() -> None:
    pytest.importorskip("sinabs")
    pytest.importorskip("torch")
    graph = _sequential_graph()
    stimulus = ValidatedStimulus(
        population="input",
        neuron_count=2,
        spikes={0: [0, 1], 1: [1, 2]},
    )
    result = SinabsSimulatorAdapter().run(
        graph,
        stimulus,
        timesteps=5,
        seed=1,
    )
    assert "lif" in result.spikes
    assert result.runtime_mode == "in_process_sinabs_sim"
