"""Sinabs simulator adapter for the shared CNL → NIR → Simulator contract."""

from __future__ import annotations

import time
from collections import defaultdict
from dataclasses import dataclass, field
from typing import Any

import nir

from neurocnl.runtime.lava_simulator import _infer_output_population
from neurocnl.runtime.nir_topology import classify_topology
from neurocnl.runtime.stimulus import ValidatedStimulus


@dataclass(slots=True)
class SinabsSimulatorResult:
    spikes: dict[str, dict[str, list[int]]] = field(default_factory=dict)
    voltages: dict[str, dict[str, list[float]]] = field(default_factory=dict)
    execution_time_ms: float = 0.0
    runtime_mode: str = "in_process_sinabs_sim"
    warnings: list[str] = field(default_factory=list)


class SinabsDispatchError(RuntimeError):
    def __init__(self, *diagnostics: str) -> None:
        self.diagnostics: list[str] = list(diagnostics)
        super().__init__("; ".join(diagnostics))


def _import_sinabs_stack() -> tuple[Any, Any, Any, Any]:
    import sinabs.nir as sinabs_nir
    import torch
    from sinabs.activation import MembraneReset
    from sinabs.network import Network as SinabsNetwork

    return torch, sinabs_nir, MembraneReset, SinabsNetwork


def _input_tensor(
    stimulus: ValidatedStimulus,
    timesteps: int,
    torch: Any,
) -> Any:
    tensor = torch.zeros((1, timesteps, stimulus.neuron_count), dtype=torch.float32)
    for neuron_idx, times in stimulus.spikes.items():
        if neuron_idx >= stimulus.neuron_count:
            continue
        for t in times:
            if 0 <= t < timesteps:
                tensor[0, t, neuron_idx] = 1.0
    return tensor


class SinabsSimulatorAdapter:
    """Run a sequential NIR graph through ``sinabs.nir.from_nir``."""

    def run(
        self,
        graph: nir.NIRGraph,
        stimulus: ValidatedStimulus,
        *,
        timesteps: int,
        seed: int,
    ) -> SinabsSimulatorResult:
        if classify_topology(graph) == "branching":
            raise SinabsDispatchError(
                "Branching NIR graphs are not supported by the Sinabs simulator. "
                "Use a sequential feedforward network."
            )

        torch, sinabs_nir, membrane_reset, sinabs_network_cls = _import_sinabs_stack()
        torch.manual_seed(seed)
        warnings: list[str] = []

        try:
            spiking_model = sinabs_nir.from_nir(graph, num_timesteps=timesteps)
        except Exception as exc:  # noqa: BLE001
            raise SinabsDispatchError(
                f"Failed to convert NIR graph to Sinabs model: {exc}"
            ) from exc

        for module in spiking_model.modules():
            if hasattr(module, "reset_fn"):
                module.reset_fn = membrane_reset()

        network = sinabs_network_cls(
            spiking_model=spiking_model, num_timesteps=timesteps
        )
        output_pop_name = _infer_output_population(graph)
        input_tensor = _input_tensor(stimulus, timesteps, torch)

        spike_record: dict[int, list[int]] = defaultdict(list)
        t_start = time.monotonic()
        with torch.no_grad():
            if hasattr(network, "reset_states"):
                network.reset_states()
            output = network(input_tensor)
            if isinstance(output, tuple):
                output = output[0]
            if output.dim() == 2:
                output = output.unsqueeze(0)
            if output.dim() == 3 and output.shape[0] == timesteps:
                output = output.transpose(0, 1)
            for t_idx in range(min(timesteps, int(output.shape[1]))):
                step = output[0, t_idx]
                fired = torch.where(step > 0)[0]
                for neuron_idx in fired.tolist():
                    spike_record[int(neuron_idx)].append(t_idx)

        spikes = {
            output_pop_name: {
                str(idx): times for idx, times in sorted(spike_record.items())
            }
        }
        return SinabsSimulatorResult(
            spikes=spikes,
            voltages={},
            execution_time_ms=(time.monotonic() - t_start) * 1000.0,
            warnings=warnings,
        )
