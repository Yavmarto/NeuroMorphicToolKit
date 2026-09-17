"""SynSense sinabs importer/exporter for NIR.

Maps sinabs sequential models to NIR nodes and NIR graphs to sinabs.
"""

from __future__ import annotations

from collections import OrderedDict, defaultdict, deque
from importlib import import_module
from typing import Any

import nir
import numpy as np

try:
    import sinabs.layers as sl
    from sinabs.network import Network as SinabsNetwork

    HAS_SINABS = True
except ImportError:
    HAS_SINABS = False

from neurocnl.ir.types import ConnectionIR, NetworkIR, PopulationIR
from neurocnl.lif_semantics import resolve_dt
from neurocnl.runtime.nir_topology import classify_topology, linearize


def _require_torch() -> tuple[Any, Any]:
    """Import torch lazily so optional extras do not break unrelated paths."""
    torch = import_module("torch")
    nn = import_module("torch.nn")
    return torch, nn


def _topological_population_order(
    network_ir: NetworkIR,
) -> tuple[list[str], dict[str, list[ConnectionIR]], list[str], list[str]]:
    """Return deterministic population order plus adjacency metadata."""
    population_names = sorted(network_ir.populations.keys())
    outgoing: dict[str, list[ConnectionIR]] = {name: [] for name in population_names}
    incoming_count: dict[str, int] = dict.fromkeys(population_names, 0)

    for conn in network_ir.connections:
        outgoing.setdefault(conn.source, []).append(conn)
        incoming_count.setdefault(conn.source, 0)
        incoming_count[conn.target] = incoming_count.get(conn.target, 0) + 1

    for conn_list in outgoing.values():
        conn_list.sort(key=lambda conn: (conn.target, repr(conn.weight)))

    queue = deque(sorted(name for name, count in incoming_count.items() if count == 0))
    ordered: list[str] = []
    remaining = dict(incoming_count)

    while queue:
        node = queue.popleft()
        ordered.append(node)
        for conn in outgoing.get(node, []):
            remaining[conn.target] -= 1
            if remaining[conn.target] == 0:
                queue.append(conn.target)

    if len(ordered) != len(incoming_count):
        raise NotImplementedError("Recurrent sinabs topologies are not supported.")

    sinks = sorted(name for name in incoming_count if not outgoing.get(name))
    roots = sorted(name for name, count in incoming_count.items() if count == 0)
    return ordered, outgoing, roots, sinks


def _population_layer(pop: PopulationIR, sl_module: Any, dt: float, inspect_module: Any) -> Any:
    tau_mem = pop.membrane_time_constant or 10.0

    def get_kwargs(layer_cls: Any, base_kwargs: dict[str, Any]) -> dict[str, Any]:
        sig = inspect_module.signature(layer_cls.__init__)
        if "dt" in sig.parameters:
            base_kwargs["dt"] = dt
        return base_kwargs

    if pop.population_type == "iaf":
        return sl_module.IAF(**get_kwargs(sl_module.IAF, {}))
    if pop.population_type == "expleak":
        return sl_module.ExpLeak(**get_kwargs(sl_module.ExpLeak, {"tau_mem": tau_mem}))
    return sl_module.LIF(**get_kwargs(sl_module.LIF, {"tau_mem": tau_mem}))


def _connection_linear_layer(
    conn: ConnectionIR,
    network_ir: NetworkIR,
    nn_module: Any,
    torch_module: Any,
) -> Any:
    out_features = (
        network_ir.populations[conn.target].size
        if network_ir.populations.get(conn.target) and network_ir.populations[conn.target].size
        else 1
    )
    in_features = (
        network_ir.populations[conn.source].size
        if network_ir.populations.get(conn.source) and network_ir.populations[conn.source].size
        else 1
    )
    linear_layer = nn_module.Linear(in_features=in_features, out_features=out_features, bias=False)

    if conn.weight is not None:
        with torch_module.no_grad():
            if isinstance(conn.weight, list | np.ndarray):
                weight_tensor = torch_module.tensor(conn.weight, dtype=torch_module.float32)
                if weight_tensor.shape == linear_layer.weight.shape:
                    linear_layer.weight.copy_(weight_tensor)
                elif weight_tensor.numel() == 1:
                    linear_layer.weight.fill_(weight_tensor.item())
                else:
                    linear_layer.weight.copy_(weight_tensor.view_as(linear_layer.weight))
            else:
                linear_layer.weight.fill_(conn.weight)

    return linear_layer


class SinabsIO:
    """Sinabs framework handler for direct and NIR conversion."""

    def to_nir(self, model: Any, **kwargs: Any) -> nir.NIRGraph:
        """Convert a sinabs PyTorch model to NIR."""
        import sinabs.layers as sl
        import sinabs.network
        import torch.nn as nn

        nodes: dict[str, nir.NIRNode] = {}
        edges: list[tuple[str, str]] = []

        # If it's a sinabs Network, we typically want to extract its underlying sequential model
        if isinstance(model, sinabs.network.Network):
            # Try to get the sequential layer if there is one
            target_model = model.spiking_model
        else:
            target_model = model

        if not isinstance(target_model, nn.Sequential):
            # Try to trace children
            layers = list(target_model.children())
        else:
            layers = list(target_model)

        prev_node_name = None

        for i, layer in enumerate(layers):
            node_name = f"layer_{i}"
            node: nir.NIRNode | None = None

            if isinstance(layer, nn.Linear):
                weight = layer.weight.detach().numpy()
                bias = layer.bias.detach().numpy() if layer.bias is not None else None
                if bias is not None:
                    node = nir.Affine(weight=weight, bias=bias)
                else:
                    node = nir.Linear(weight=weight)
            elif isinstance(layer, sl.LIF):
                # Assuming simple LIF mapping
                # sinabs LIF: tau_mem, v_threshold, v_reset (implicit/explicit)
                # NIR LIF: tau, r, v_leak, v_threshold
                tau_mem = (
                    layer.tau_mem.detach().numpy()
                    if hasattr(layer.tau_mem, "detach")
                    else np.array(
                        [
                            (
                                layer.tau_mem.item()
                                if hasattr(layer.tau_mem, "item")
                                else layer.tau_mem
                            )
                        ]
                    )
                )
                v_threshold = (
                    np.array(
                        [
                            (
                                layer.v_threshold.item()
                                if hasattr(layer.v_threshold, "item")
                                else layer.v_threshold
                            )
                        ]
                    )
                    if hasattr(layer, "v_threshold")
                    else np.array([1.0])
                )
                # Force shapes to be consistent (1D array of same size)
                tau_mem = np.atleast_1d(tau_mem)
                v_threshold = np.atleast_1d(v_threshold)
                # Ensure they have same length by broadcasting if necessary
                max_len = max(len(tau_mem), len(v_threshold))
                tau_mem = np.broadcast_to(tau_mem, max_len)
                v_threshold = np.broadcast_to(v_threshold, max_len)

                # Provide reasonable defaults for the rest
                r = np.ones_like(tau_mem)
                v_leak = np.zeros_like(tau_mem)
                node = nir.LIF(tau=tau_mem, r=r, v_leak=v_leak, v_threshold=v_threshold)
            elif isinstance(layer, sl.IAF):
                # sinabs IAF: doesn't have tau_mem, has v_threshold
                v_threshold = (
                    np.array(
                        [
                            (
                                layer.v_threshold.item()
                                if hasattr(layer.v_threshold, "item")
                                else layer.v_threshold
                            )
                        ]
                    )
                    if hasattr(layer, "v_threshold")
                    else np.array([1.0])
                )
                v_threshold = np.atleast_1d(v_threshold)
                r = np.ones_like(v_threshold)
                node = nir.IF(r=r, v_threshold=v_threshold)
            else:
                # Try to map fallback if needed
                pass

            if node is not None:
                nodes[node_name] = node
                if prev_node_name is not None:
                    edges.append((prev_node_name, node_name))
                prev_node_name = node_name

        return nir.NIRGraph(nodes=nodes, edges=edges)

    def from_nir(self, graph: nir.NIRGraph, **kwargs: Any) -> str:
        """Convert an NIR graph to sinabs model definitions (Python code).

        Only sequential (single-path) NIR graphs are supported. Branching graphs
        or unsupported node types raise ``NotImplementedError`` immediately.
        """
        # Validate topology (self-loop recurrence tolerated, branching/merging not)
        if classify_topology(graph) == "branching":
            raise NotImplementedError(
                "Branching/merging NIR graph is not supported by sinabs. "
                "Only sequential (single-path) topologies (optionally with a "
                "single self-loop recurrence) are supported."
            )

        try:
            ordered = linearize(graph)
        except ValueError as exc:
            raise NotImplementedError(str(exc)) from exc

        node_lines: list[str] = []

        def array_code(value: Any) -> str:
            array = np.asarray(value, dtype=np.float32)
            return f"np.array({array.tolist()!r}, dtype=np.float32)"

        def shape_type_code(value: Any) -> str:
            if not isinstance(value, dict):
                return repr(value)
            entries = ", ".join(f"{key!r}: {array_code(item)}" for key, item in value.items())
            return "{" + entries + "}"

        for node_name in ordered:
            node = graph.nodes[node_name]
            if isinstance(node, nir.Input):
                expression = f"nir.Input(input_type={shape_type_code(node.input_type)})"
            elif isinstance(node, nir.Output):
                expression = f"nir.Output(output_type={shape_type_code(node.output_type)})"
            elif isinstance(node, nir.Affine):
                expression = (
                    f"nir.Affine(weight={array_code(node.weight)}, bias={array_code(node.bias)})"
                )
            elif isinstance(node, nir.Linear):
                weight = np.asarray(node.weight, dtype=np.float32)
                expression = (
                    f"nir.Affine(weight={array_code(weight)}, "
                    f"bias={array_code(np.zeros(weight.shape[0], dtype=np.float32))})"
                )
            elif isinstance(node, nir.LIF):
                # Same discretization as neurocnl.lif_semantics (beta = 1 - dt/tau,
                # threshold divided by r*dt/tau), kept element-wise here because
                # sinabs emits per-neuron arrays while the shared helper reduces a
                # population to its mean. Only the dt resolution is shared, so the
                # default timestep cannot drift away from the rest of the codebase.
                tau = np.asarray(node.tau, dtype=np.float32)
                dt, _ = resolve_dt(node, graph)
                beta = np.asarray(
                    node.metadata.get("beta", np.where(tau > 0, 1.0 - (dt / tau), 0.0)),
                    dtype=np.float32,
                )
                beta = np.clip(beta, 1e-7, 1.0 - 1e-7)
                tau_steps = -1.0 / np.log(beta)
                threshold = np.asarray(node.v_threshold, dtype=np.float32)
                resistance = np.asarray(node.r, dtype=np.float32)
                input_scale = np.where(tau > 0, resistance * dt / tau, 1.0)
                threshold = np.where(
                    np.abs(input_scale - 1.0) > 1e-6,
                    threshold / input_scale,
                    threshold,
                )
                expression = (
                    f"nir.LIF(tau={array_code(tau_steps)}, "
                    f"r={array_code(np.ones_like(tau_steps))}, "
                    f"v_leak={array_code(np.zeros_like(tau_steps))}, "
                    f"v_threshold={array_code(threshold)})"
                )
            elif isinstance(node, nir.IF):
                expression = (
                    f"nir.IF(r={array_code(np.ones_like(node.r))}, "
                    f"v_threshold={array_code(node.v_threshold)})"
                )
            else:
                raise NotImplementedError(
                    f"NIR node type '{type(node).__name__}' (node '{node_name}') is not supported "
                    "in sinabs conversion. Supported types: Input, Output, Linear, Affine, LIF, IF."
                )
            node_lines.append(f"        {node_name!r}: {expression},")
        lines = [
            '"""Sinabs model definitions — auto-generated from NIR."""',
            "",
            "import numpy as np",
            "import torch",
            "import torch.nn as nn",
            "import nir",
            "import sinabs.nir as sinabs_nir",
            "from sinabs.activation import MembraneReset",
            "from sinabs.network import Network as SinabsNetwork",
            "",
            "class StudioSinabsInference(nn.Module):",
            '    """Studio adapter returning time-first spike-count compatible outputs."""',
            "",
            "    def __init__(self, network, num_timesteps=25):",
            "        super().__init__()",
            "        self.network = network",
            "        self.num_timesteps = num_timesteps",
            "        self._layer_rates = {}",
            "",
            "    def forward(self, x):",
            "        if hasattr(self.network, 'reset_states'):",
            "            self.network.reset_states()",
            "        if x.dim() == 2:",
            "            x = x.unsqueeze(1).expand(-1, self.num_timesteps, -1)",
            "        elif x.dim() >= 3 and x.shape[0] == self.num_timesteps:",
            "            x = x.swapaxes(0, 1)",
            "        if x.dim() < 3 or x.shape[1] != self.num_timesteps:",
            "            raise ValueError(f'Expected batch/time input with {self.num_timesteps} timesteps.')",
            "        batch_size = x.shape[0]",
            "        output = self.network(x.reshape(batch_size * self.num_timesteps, *x.shape[2:]))",
            "        if isinstance(output, tuple):",
            "            output = output[0]",
            "        output = output.reshape(batch_size, self.num_timesteps, *output.shape[1:]).swapaxes(0, 1)",
            "        self._layer_rates = {'sinabs_output': output.float().mean().item()}",
            "        return output, torch.zeros_like(output)",
            "",
            "def build_model(num_timesteps=25):",
            "    nir_graph = nir.NIRGraph(",
            "        nodes={",
        ]
        lines.extend(node_lines)
        lines.extend(
            [
                "        },",
                f"        edges={list(graph.edges)!r},",
                "        type_check=False,",
                "    )",
                "    spiking_model = sinabs_nir.from_nir(nir_graph, num_timesteps=num_timesteps)",
                "    for module in spiking_model.modules():",
                "        if hasattr(module, 'reset_fn'):",
                "            module.reset_fn = MembraneReset()",
                "    network = SinabsNetwork(spiking_model=spiking_model, num_timesteps=num_timesteps)",
                "    return StudioSinabsInference(network, num_timesteps=num_timesteps)",
            ]
        )
        lines.append("")
        lines.append("net = build_model()")
        return "\n".join(lines)

    def from_neurocnl(self, network_ir: NetworkIR) -> Any:
        """Convert a NeuroCNL IR to a sinabs Network directly.

        Args:
            network_ir: The parsed NetworkIR model.

        Returns:
            sinabs.network.Network: The constructed sinabs network.
        """
        if not HAS_SINABS:
            raise ImportError("sinabs is required for this operation.")
        torch, nn = _require_torch()
        import inspect

        dt = 1.0  # default timestep
        for td in network_ir.timing_declarations:
            if td.kind == "timestep" and td.value is not None:
                dt = td.value
                break

        if not network_ir.connections:
            layers = OrderedDict()
            # If no connections, just add the populations
            for pop_name, pop in network_ir.populations.items():
                layers[pop_name] = _population_layer(pop, sl, dt, inspect)
            return SinabsNetwork(spiking_model=nn.Sequential(layers))

        order, outgoing, roots, sinks = _topological_population_order(network_ir)
        incoming_counts: dict[str, int] = defaultdict(int)
        for conn in network_ir.connections:
            incoming_counts[conn.target] += 1

        has_branching = any(len(conns) > 1 for conns in outgoing.values())
        has_merging = any(count > 1 for count in incoming_counts.values())

        if not has_branching and not has_merging:
            layers = OrderedDict()
            for node in order:
                node_pop = network_ir.populations.get(node)
                if node_pop is not None:
                    layers[node] = _population_layer(node_pop, sl, dt, inspect)
                for conn in outgoing.get(node, []):
                    layers[f"conn_{node}_{conn.target}"] = _connection_linear_layer(
                        conn,
                        network_ir,
                        nn,
                        torch,
                    )
            return SinabsNetwork(spiking_model=nn.Sequential(layers))

        class SinabsDagModule(nn.Module):  # type: ignore[name-defined,misc]
            def __init__(self) -> None:
                super().__init__()
                self.population_layers = nn.ModuleDict(
                    {
                        name: _population_layer(network_ir.populations[name], sl, dt, inspect)
                        for name in order
                        if name in network_ir.populations
                    }
                )
                self.connection_layers = nn.ModuleDict(
                    {
                        f"{conn.source}__{conn.target}": _connection_linear_layer(
                            conn,
                            network_ir,
                            nn,
                            torch,
                        )
                        for conn in network_ir.connections
                    }
                )

            def forward(self, x: Any) -> Any:
                pending_inputs: dict[str, Any] = {}
                outputs: dict[str, Any] = {}

                for node in order:
                    node_input = pending_inputs.pop(node, None)
                    if node_input is None:
                        if node in roots:
                            node_input = x
                        else:
                            raise RuntimeError(f"Missing computed input for sinabs node '{node}'.")

                    outputs[node] = self.population_layers[node](node_input)

                    for conn in outgoing.get(node, []):
                        layer_name = f"{conn.source}__{conn.target}"
                        contribution = self.connection_layers[layer_name](outputs[node])
                        if conn.target in pending_inputs:
                            pending_inputs[conn.target] = pending_inputs[conn.target] + contribution
                        else:
                            pending_inputs[conn.target] = contribution

                if len(sinks) == 1:
                    return outputs[sinks[0]]
                return torch.cat([outputs[name] for name in sinks], dim=-1)

        return SinabsNetwork(spiking_model=SinabsDagModule())

    def to_neurocnl(self, sinabs_model: Any) -> NetworkIR:
        """Convert a sinabs Network back to NeuroCNL IR.

        Args:
            sinabs_model: sinabs.network.Network

        Returns:
            NetworkIR
        """
        if not HAS_SINABS:
            raise ImportError("sinabs is required for this operation.")
        _, nn = _require_torch()

        ir = NetworkIR()

        seq = getattr(sinabs_model, "spiking_model", None)
        if seq is None:
            seq = getattr(
                sinabs_model,
                "analog_model",
                getattr(sinabs_model, "sequence", sinabs_model),
            )
        if not hasattr(seq, "named_children") and hasattr(seq, "sequence"):
            seq = seq.sequence

        # We try to extract sequential layers and assign them
        prev_pop_name = None
        conn_weight = None
        pop_idx = 0

        # In a sequence, if it starts with nn.Linear, it maps an external input to the first pop.
        # We need to handle this by creating a generic input pop or just retaining the conn_weight.

        for name, layer in seq.named_children():
            if isinstance(layer, nn.Linear):
                if layer.weight.numel() == 1:
                    conn_weight = layer.weight.detach().item()
                else:
                    conn_weight = layer.weight.detach().cpu().numpy().tolist()

                # If prev_pop_name is None, it means Linear is the first layer.
                if prev_pop_name is None:
                    prev_pop_name = "input_0"
                    ir.populations[prev_pop_name] = PopulationIR(name=prev_pop_name, role="input")

            elif isinstance(layer, sl.LIF | sl.IAF | sl.ExpLeak):
                pop_name = f"pop_{pop_idx}"
                pop_idx += 1

                pop_type = "lif"
                if isinstance(layer, sl.IAF):
                    pop_type = "iaf"
                elif isinstance(layer, sl.ExpLeak):
                    pop_type = "expleak"

                ir.populations[pop_name] = PopulationIR(name=pop_name, population_type=pop_type)

                if prev_pop_name is not None and conn_weight is not None:
                    conn = ConnectionIR(source=prev_pop_name, target=pop_name, weight=conn_weight)
                    ir.connections.append(conn)
                    conn_weight = None

                prev_pop_name = pop_name

        return ir
