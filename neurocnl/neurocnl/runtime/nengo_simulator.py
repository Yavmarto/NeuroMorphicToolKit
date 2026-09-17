"""Nengo simulator adapter for the shared CNL → NIR → Simulator contract."""

from __future__ import annotations

import time
from collections import defaultdict
from dataclasses import dataclass, field
from typing import Any

import nir
import numpy as np

from neurocnl.converter.nengo_io import NengoIO
from neurocnl.runtime.lava_simulator import _infer_output_population
from neurocnl.runtime.stimulus import ValidatedStimulus

_DEFAULT_DT_SECONDS = 1e-4


@dataclass(slots=True)
class NengoSimulatorResult:
    spikes: dict[str, dict[str, list[int]]] = field(default_factory=dict)
    voltages: dict[str, dict[str, list[float]]] = field(default_factory=dict)
    execution_time_ms: float = 0.0
    runtime_mode: str = "in_process_nengo_sim"
    warnings: list[str] = field(default_factory=list)


class NengoDispatchError(RuntimeError):
    def __init__(self, *diagnostics: str) -> None:
        self.diagnostics: list[str] = list(diagnostics)
        super().__init__("; ".join(diagnostics))


def _import_nengo() -> Any:
    import nengo

    return nengo


def _stimulus_vector(
    stimulus: ValidatedStimulus,
    timestep: int,
    size: int,
) -> list[float]:
    values = [0.0] * size
    for neuron_idx, times in stimulus.spikes.items():
        if neuron_idx < size and timestep in times:
            values[neuron_idx] = 1.0
    return values


class NengoSimulatorAdapter:
    """Compile NIR to a live Nengo network and run a deterministic timestep loop."""

    def run(
        self,
        graph: nir.NIRGraph,
        stimulus: ValidatedStimulus,
        *,
        timesteps: int,
        seed: int,
        dt_ms: float = 1.0,
    ) -> NengoSimulatorResult:
        nengo = _import_nengo()
        dt_seconds = max(dt_ms / 1000.0, _DEFAULT_DT_SECONDS)
        warnings: list[str] = []

        try:
            code = NengoIO().from_nir(graph, dt=dt_seconds)
        except ValueError as exc:
            raise NengoDispatchError(str(exc)) from exc

        namespace: dict[str, Any] = {}
        try:
            exec(compile(code, "<nengo_sim_net>", "exec"), namespace)
        except Exception as exc:  # noqa: BLE001
            raise NengoDispatchError(f"Failed to build Nengo network: {exc}") from exc

        model = namespace.get("model")
        if model is None:
            raise NengoDispatchError("Generated Nengo code did not define `model`.")

        input_node = namespace.get(stimulus.population)
        if input_node is None:
            raise NengoDispatchError(
                f"Stimulus population {stimulus.population!r} was not found in the Nengo network."
            )

        output_pop_name = _infer_output_population(graph)
        output_neurons = namespace.get(output_pop_name)
        if output_neurons is None:
            for name, node in reversed(list(graph.nodes.items())):
                if isinstance(node, nir.LIF | nir.CubaLIF) and name in namespace:
                    output_pop_name = name
                    output_neurons = namespace[name]
                    break
        if output_neurons is None:
            raise NengoDispatchError(
                "The compiled NIR graph has no LIF population the Nengo adapter can probe."
            )

        with model:
            stim_node = nengo.Node(
                lambda t, _stim=stimulus, _size=stimulus.neuron_count: _stimulus_vector(
                    _stim, int(round(t / dt_seconds)), _size
                )
            )
            nengo.Connection(stim_node, input_node, synapse=None)
            spike_probe = nengo.Probe(output_neurons, synapse=None)
            voltage_probe = nengo.Probe(output_neurons, "voltage", synapse=None)

        spike_record: dict[int, list[int]] = defaultdict(list)
        voltage_record: dict[int, list[float]] = defaultdict(list)
        t_start = time.monotonic()
        with nengo.Simulator(
            model, dt=dt_seconds, progress_bar=False, seed=seed
        ) as sim:
            sim.run(timesteps * dt_seconds)
            raw_spikes = sim.data[spike_probe]
            raw_voltage = sim.data[voltage_probe]
            for t_idx in range(min(timesteps, raw_spikes.shape[0])):
                fired = np.where(raw_spikes[t_idx] > 0)[0]
                for neuron_idx in fired:
                    spike_record[int(neuron_idx)].append(t_idx)
                for neuron_idx in range(raw_voltage.shape[1]):
                    voltage_record[int(neuron_idx)].append(
                        float(raw_voltage[t_idx, neuron_idx])
                    )

        spikes = {
            output_pop_name: {
                str(idx): times for idx, times in sorted(spike_record.items())
            }
        }
        voltages = {
            output_pop_name: {
                str(idx): values for idx, values in sorted(voltage_record.items())
            }
        }
        return NengoSimulatorResult(
            spikes=spikes,
            voltages=voltages,
            execution_time_ms=(time.monotonic() - t_start) * 1000.0,
            warnings=warnings,
        )
