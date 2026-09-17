"""Tests for Brian2 simulator adapter dispatch helpers."""

from unittest.mock import patch

import nir
import numpy as np

from neurocnl.runtime.brian2_simulator import Brian2SimulatorAdapter
from neurocnl.runtime.stimulus import ValidatedStimulus


def test_brian2_simulator_remote_wraps_flat_spikes() -> None:
    graph = nir.NIRGraph(
        nodes={
            "input": nir.LIF(
                tau=np.array([0.01]),
                v_threshold=np.array([1.0]),
                v_leak=np.array([0.0]),
                r=np.array([1.0]),
            ),
            "output": nir.LIF(
                tau=np.array([0.02]),
                v_threshold=np.array([1.0]),
                v_leak=np.array([0.0]),
                r=np.array([1.0]),
            ),
        },
        edges=[("input", "output")],
    )

    with (
        patch(
            "neurocnl.runtime.brian2_simulator._is_brian2_available",
            return_value=False,
        ),
        patch(
            "neurocnl.converter.brian2_io.Brian2IO.compile_and_run_remote",
            return_value={
                "compile": {"session_id": "sess-1"},
                "run": {"spikes": {"0": [0, 2]}, "execution_time_ms": 3.0},
            },
        ),
    ):
        result = Brian2SimulatorAdapter().run(
            graph,
            stimulus=ValidatedStimulus(
                population="input",
                neuron_count=1,
                spikes={},
            ),
            timesteps=4,
            seed=0,
            worker_url="http://brian2-backend:8013",
        )

    assert result.runtime_mode == "remote_brian2_sim_worker"
    assert result.spikes["output"]["0"] == [0, 2]
