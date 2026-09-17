"""Sinabs SNN code exporter.

Generates PyTorch and sinabs code for deployment.
"""

import warnings
from typing import Any

import nir

from neurocnl.converter.sinabs_io import SinabsIO
from neurocnl.ir.types import NetworkIR


def export_sinabs(network: nir.NIRGraph | NetworkIR, **kwargs: Any) -> str:
    """Generate sinabs python script or directly convert model for deployment.

    If an NIR graph is provided, it falls back to the deprecated NIR generation path.
    If a NetworkIR is provided, it returns the generated python script string representing the model
    (Note: currently returning the script for NIR, but for NeuroCNL direct translation, we generate the actual model logic script or object).
    """
    converter = SinabsIO()

    if isinstance(network, nir.NIRGraph):
        warnings.warn(
            "Exporting sinabs via NIRGraph is deprecated. Please pass a NetworkIR instead for direct conversion.",
            DeprecationWarning,
            stacklevel=2,
        )
        return converter.from_nir(network, **kwargs)
    elif isinstance(network, NetworkIR):
        # We can construct the model directly. To maintain string return type for "export",
        # we generate a python code representation similar to what we did for NIR, but based on IR.
        # Alternatively, returning the actual Python code string here.
        # The prompt says: "NIR path in sinabs_exporter.py is preserved as a fallback but marked deprecated."
        # We need a proper code generation from NetworkIR
        dt = 1.0
        for td in network.timing_declarations:
            if td.kind == "timestep" and td.value is not None:
                dt = td.value
                break

        lines = [
            '"""Sinabs Process definitions — auto-generated directly from NeuroCNL IR."""',
            "",
            "from collections import OrderedDict",
            "import inspect",
            "import numpy as np",
            "import torch",
            "import torch.nn as nn",
            "import sinabs.layers as sl",
            "from sinabs.network import Network as SinabsNetwork",
            "",
            f"DT = {dt}",
            "",
            "def get_kwargs(layer_cls, base_kwargs):",
            "    sig = inspect.signature(layer_cls.__init__)",
            "    if 'dt' in sig.parameters:",
            "        base_kwargs['dt'] = DT",
            "    return base_kwargs",
            "",
            "def build_model():",
            "    layers = OrderedDict()",
        ]

        if not network.connections:
            for pop_name, pop in network.populations.items():
                tau = pop.membrane_time_constant or 10.0
                if pop.population_type == "iaf":
                    lines.append(
                        f"    layers['{pop_name}'] = sl.IAF(**get_kwargs(sl.IAF, {{}}))"
                    )
                elif pop.population_type == "expleak":
                    lines.append(
                        f"    layers['{pop_name}'] = sl.ExpLeak(**get_kwargs(sl.ExpLeak, {{'tau_mem': {tau}}}))"
                    )
                else:
                    lines.append(
                        f"    layers['{pop_name}'] = sl.LIF(**get_kwargs(sl.LIF, {{'tau_mem': {tau}}}))"
                    )
        else:
            from collections import defaultdict

            source_to_conns: dict[str, list[Any]] = defaultdict(list)
            for conn in network.connections:
                source_to_conns[conn.source].append(conn)

            # Reconstruct topological ordering based on connections, very simplistically
            targets = {conn.target for conn in network.connections}
            sources = {conn.source for conn in network.connections}
            start_nodes = sources - targets
            start_node = (
                list(start_nodes)[0]
                if start_nodes
                else (list(sources)[0] if sources else None)
            )

            current_node = start_node
            added_pops: set[str] = set()
            while current_node is not None:
                if current_node not in added_pops:
                    current_pop = network.populations.get(current_node)
                    if current_pop:
                        tau = current_pop.membrane_time_constant or 10.0
                        if current_pop.population_type == "iaf":
                            lines.append(
                                f"    layers['{current_node}'] = sl.IAF(**get_kwargs(sl.IAF, {{}}))"
                            )
                        elif current_pop.population_type == "expleak":
                            lines.append(
                                f"    layers['{current_node}'] = sl.ExpLeak(**get_kwargs(sl.ExpLeak, {{'tau_mem': {tau}}}))"
                            )
                        else:
                            lines.append(
                                f"    layers['{current_node}'] = sl.LIF(**get_kwargs(sl.LIF, {{'tau_mem': {tau}}}))"
                            )
                        added_pops.add(current_node)

                conns = source_to_conns.get(current_node)
                if conns:
                    if len(conns) > 1:
                        raise NotImplementedError(
                            f"Branching topology at '{current_node}' is not supported by sinabs. "
                            "Sinabs requires strictly sequential (single-path) networks."
                        )
                    conn = conns[0]
                    in_f = (
                        network.populations[conn.source].size
                        if network.populations.get(conn.source)
                        and network.populations[conn.source].size
                        else 1
                    )
                    out_f = (
                        network.populations[conn.target].size
                        if network.populations.get(conn.target)
                        and network.populations[conn.target].size
                        else 1
                    )
                    conn_name = f"conn_{current_node}_{conn.target}"

                    lines.append(
                        f"    layers['{conn_name}'] = nn.Linear(in_features={in_f}, out_features={out_f}, bias=False)"
                    )
                    if conn.weight is not None:
                        lines.append("    with torch.no_grad():")
                        lines.append(
                            f"        weight_tensor = torch.tensor({conn.weight}, dtype=torch.float32)"
                        )
                        lines.append(
                            f"        if weight_tensor.shape == layers['{conn_name}'].weight.shape:"
                        )
                        lines.append(
                            f"            layers['{conn_name}'].weight.copy_(weight_tensor)"
                        )
                        lines.append("        elif weight_tensor.numel() == 1:")
                        lines.append(
                            f"            layers['{conn_name}'].weight.fill_(weight_tensor.item())"
                        )
                        lines.append("        else:")
                        lines.append(
                            f"            layers['{conn_name}'].weight.copy_(weight_tensor.view_as(layers['{conn_name}'].weight))"
                        )
                    current_node = conn.target
                else:
                    current_node = None

        lines.extend(
            [
                "",
                "    model = nn.Sequential(layers)",
                "    return SinabsNetwork(model)",
            ]
        )

        return "\n".join(lines)
    else:
        raise TypeError("network must be of type NIRGraph or NetworkIR.")
