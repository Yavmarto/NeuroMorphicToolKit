"""Rockpool converter without NIR routing.

Provides direct `to_neurocnl` and `from_neurocnl` implementations for SynSense Rockpool.
"""

from importlib.util import find_spec
from typing import Any

import nir
import numpy as np

from neurocnl.ir.types import NetworkIR
from neurocnl.runtime.nir_topology import linearize

ROCKPOOL_AVAILABLE = find_spec("rockpool") is not None


class RockpoolIO:
    """Direct conversion between NeuroCNL IR and Rockpool Sequential."""

    def from_neurocnl(self, network_ir: NetworkIR, **kwargs: Any) -> Any:
        """Convert a sequential NeuroCNL NetworkIR directly to a Rockpool model."""
        if not ROCKPOOL_AVAILABLE:
            raise ImportError("rockpool is required for this operation.")

        import rockpool.nn.modules as rpm
        from rockpool.nn.combinators import Sequential

        dt = kwargs.get("dt", 0.001)
        for declaration in network_ir.timing_declarations:
            if declaration.kind == "timestep" and declaration.value is not None:
                dt = declaration.value
                break

        if not network_ir.populations:
            return Sequential()

        connected = set()
        in_edges: dict[str, list[str]] = {name: [] for name in network_ir.populations}
        out_edges: dict[str, list[str]] = {name: [] for name in network_ir.populations}
        connection_by_edge: dict[tuple[str, str], Any] = {}

        for connection in network_ir.connections:
            connected.add(connection.source)
            connected.add(connection.target)
            out_edges.setdefault(connection.source, []).append(connection.target)
            in_edges.setdefault(connection.target, []).append(connection.source)
            connection_by_edge[(connection.source, connection.target)] = connection

        for name, targets in out_edges.items():
            if len(targets) > 1:
                raise NotImplementedError(
                    f"Branching topology at '{name}' is not supported by direct Rockpool conversion."
                )
        for name, sources in in_edges.items():
            if len(sources) > 1:
                raise NotImplementedError(
                    f"Merging topology at '{name}' is not supported by direct Rockpool conversion."
                )

        ordered_names: list[str] = []
        if connected:
            roots = [name for name in connected if not in_edges.get(name)]
            current = roots[0] if roots else next(iter(connected))
            visited: set[str] = set()
            while current not in visited:
                ordered_names.append(current)
                visited.add(current)
                next_nodes = out_edges.get(current, [])
                if not next_nodes:
                    break
                current = next_nodes[0]
        else:
            ordered_names = list(network_ir.populations)

        modules: list[Any] = []
        previous_name: str | None = None
        for name in ordered_names:
            population = network_ir.populations[name]
            if previous_name is not None:
                connection = connection_by_edge[(previous_name, name)]
                source = network_ir.populations[previous_name]
                target = population
                source_size = source.size or source.dimensions or 1
                target_size = target.size or target.dimensions or 1
                weight = float(connection.weight or 1.0)
                linear = rpm.Linear(
                    shape=(source_size, target_size),
                    weight=np.full((source_size, target_size), weight),
                )
                modules.append(linear)

            modules.append(_population_to_module(population, rpm, dt))
            previous_name = name

        return Sequential(*modules)

    def from_nir(self, graph: nir.NIRGraph, **kwargs: Any) -> Any:
        """Convert an NIR graph to a Rockpool model."""
        import torch
        from rockpool.nn.combinators import Sequential
        from rockpool.nn.modules import ExpSynTorch, LIFTorch, LinearTorch

        # linearize() raises ValueError for branching/merging graphs or a
        # missing/duplicate Input node, and excludes Input/Output boundary
        # nodes plus any self-loop's recurrent-partner node from its result.
        ordered_names = linearize(graph)

        rockpool_modules = []
        dt = kwargs.get("dt", 0.001)

        for name in ordered_names:
            node = graph.nodes[name]
            if isinstance(node, nir.Linear):
                weight = node.weight.T  # rockpool expects (in_features, out_features)
                mod = LinearTorch(
                    shape=weight.shape, weight=torch.tensor(weight, dtype=torch.float32)
                )
                rockpool_modules.append(mod)
            elif isinstance(node, nir.LIF):
                # Map parameters
                tau_mem = torch.tensor(node.tau, dtype=torch.float32)
                threshold = torch.tensor(node.v_threshold, dtype=torch.float32)
                bias = torch.tensor(node.v_leak, dtype=torch.float32)

                # Check shape
                if len(tau_mem.shape) == 0:
                    tau_mem = tau_mem.unsqueeze(0)
                    threshold = threshold.unsqueeze(0)
                    bias = bias.unsqueeze(0)

                mod = LIFTorch(
                    shape=(tau_mem.shape[0],),
                    tau_mem=tau_mem,
                    threshold=threshold,
                    bias=bias,
                    dt=dt,
                )
                rockpool_modules.append(mod)
            elif isinstance(node, nir.CubaLIF):
                # Map to ExpSynTorch + LIFTorch sequence if it has both dynamics
                # Check if it was purely our mock ExpSyn filter (threshold=1e9)
                tau_syn = torch.tensor(node.tau_syn, dtype=torch.float32)
                if len(tau_syn.shape) == 0:
                    tau_syn = tau_syn.unsqueeze(0)

                syn_mod = ExpSynTorch(shape=(tau_syn.shape[0],), tau=tau_syn, dt=dt)
                rockpool_modules.append(syn_mod)

                # Only add LIF if threshold is reasonable
                if torch.any(torch.tensor(node.v_threshold) < 1e8):
                    tau_mem = torch.tensor(node.tau_mem, dtype=torch.float32)
                    threshold = torch.tensor(node.v_threshold, dtype=torch.float32)
                    bias = torch.tensor(node.v_leak, dtype=torch.float32)

                    if len(tau_mem.shape) == 0:
                        tau_mem = tau_mem.unsqueeze(0)
                        threshold = threshold.unsqueeze(0)
                        bias = bias.unsqueeze(0)

                    lif_mod = LIFTorch(
                        shape=(tau_mem.shape[0],),
                        tau_mem=tau_mem,
                        threshold=threshold,
                        bias=bias,
                        dt=dt,
                    )
                    rockpool_modules.append(lif_mod)
            else:
                raise ValueError(f"Unsupported NIR node for Rockpool: {type(node)}")

        return Sequential(*rockpool_modules)


def _population_to_module(population: Any, rpm: Any, dt: float) -> Any:
    size = population.size or population.dimensions or 1
    tau_mem = float(population.membrane_time_constant or 0.02)
    threshold = float(population.threshold or 1.0)
    population_type = population.population_type or "lif"

    if population_type in {"lif", "iaf"}:
        module = rpm.LIF(size)
        module.tau_mem = np.full((size,), tau_mem)
        module.threshold = np.full((size,), threshold)
        module.dt = dt
        return module

    if population_type in {"expsyn", "exp_syn", "exp_syn_lif"}:
        module = rpm.ExpSyn(size)
        module.tau_mem = np.full((size,), tau_mem)
        module.tau_syn = np.full(
            (size,),
            float(population.attributes.get("synapse_time_constant", tau_mem)),
        )
        module.threshold = np.full((size,), threshold)
        module.dt = dt
        return module

    raise NotImplementedError(
        f"Population type '{population_type}' is not supported by direct Rockpool conversion."
    )
