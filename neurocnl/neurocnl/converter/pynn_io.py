"""PyNN framework importer/exporter for NIR.

Maps PyNN populations and projections to NIR nodes and NIR graphs to PyNN code.
"""

from typing import Any

import nir
import numpy as np

from neurocnl.converter._diagnostics import raise_unsupported_node


class PyNNIO:
    """PyNN framework handler for NIR conversion."""

    def to_nir(self, model: Any, **kwargs: Any) -> nir.NIRGraph:
        """Convert a PyNN model (list of populations and projections) to NIR.

        Parameters
        ----------
        model : list or dict
            Expected as a list of PyNN populations and projections.
        """
        nodes: dict[str, nir.NIRNode] = {}
        edges: list[tuple[str, str]] = []

        # PyNN model passed as a list of populations and projections
        if not isinstance(model, list | tuple):
            model = [model]

        for obj in model:
            # Handle Populations
            if hasattr(obj, "label") and hasattr(obj, "size"):
                name = obj.label
                n = obj.size
                # Map PyNN cell type parameters to NIR LIF
                if hasattr(obj, "celltype"):
                    ct = obj.celltype
                    tau_m = getattr(ct, "tau_m", 20.0)  # ms
                    nodes[name] = nir.LIF(
                        tau=np.full(n, tau_m / 1000.0),
                        v_threshold=np.full(n, 1.0),  # Normalized threshold
                        v_leak=np.zeros(n),
                        r=np.ones(n),
                    )

            # Handle Projections
            if hasattr(obj, "pre") and hasattr(obj, "post"):
                pre_label = obj.pre.label
                post_label = obj.post.label

                # Get weight matrix (simplified)
                if hasattr(obj, "getWeights"):
                    weights = obj.getWeights()
                    # In NIR, Linear is usually a separate node
                    conn_name = f"conn_{pre_label}_{post_label}"
                    nodes[conn_name] = nir.Linear(weight=np.array(weights))
                    edges.append((pre_label, conn_name))
                    edges.append((conn_name, post_label))
                else:
                    # Direct edge
                    edges.append((pre_label, post_label))

        return nir.NIRGraph(nodes=nodes, edges=edges)

    def from_nir(self, graph: nir.NIRGraph, **kwargs: Any) -> str:
        """Convert an NIR graph to PyNN simulation code (Python string).

        Parameters
        ----------
        backend : str, optional
            The PyNN backend to use (default: 'spiNNaker').
        """
        backend = kwargs.get("backend", "spiNNaker")
        lines = [
            '"""PyNN code — auto-generated from NIR."""',
            "",
            f"import pyNN.{backend} as sim",
            "import numpy as np",
            "",
            "sim.setup(timestep=1.0)",
            "",
        ]

        _SUPPORTED = (nir.Input, nir.Output, nir.Linear, nir.LIF, nir.CubaLIF)
        node_vars = {}
        for name, node in graph.nodes.items():
            var_name = name.replace(" ", "_").replace("-", "_")
            node_vars[name] = var_name

            if isinstance(node, nir.LIF | nir.CubaLIF):
                n_neurons = node.tau.size if hasattr(node.tau, "size") else 1
                tau_m = float(node.tau.flat[0]) * 1000 if hasattr(node.tau, "flat") else 20.0
                lines.append(f"# NIR Node: {name} (LIF)")
                lines.append(f"{var_name} = sim.Population(")
                lines.append(f"    {n_neurons},")
                lines.append("    sim.IF_curr_exp(")
                lines.append(f"        tau_m={tau_m:.1f},")
                lines.append("        v_thresh=-50.0,")
                lines.append("        v_reset=-65.0,")
                lines.append("    ),")
                lines.append(f'    label="{name}",')
                lines.append(")")
                lines.append("")

            elif isinstance(node, nir.Linear):
                pass

            elif isinstance(node, nir.Input | nir.Output):
                pass  # boundary markers — matches pre-existing behavior

            else:
                raise_unsupported_node(node, "PyNNIO", _SUPPORTED, node_name=name)

        for pre_name, post_name in graph.edges:
            if pre_name in node_vars and post_name in node_vars:
                pre_var = node_vars[pre_name]
                post_var = node_vars[post_name]
                pre_node = graph.nodes[pre_name]
                post_node = graph.nodes[post_name]

                if isinstance(pre_node, nir.LIF | nir.CubaLIF) and isinstance(
                    post_node, nir.Linear
                ):
                    for next_pre, next_post in graph.edges:
                        if next_pre == post_name and next_post in node_vars:
                            target_var = node_vars[next_post]
                            weight = post_node.weight
                            lines.append(
                                f"# Projection via Linear node: {pre_name} -> {post_name} -> {next_post}"
                            )
                            lines.append(f"W_{pre_var}_{target_var} = np.array({weight.tolist()})")
                            lines.append(
                                f"conn_list = [(i, j, float(W_{pre_var}_{target_var}[j, i]), 1.0) "
                                f"for i in range({weight.shape[1]}) for j in range({weight.shape[0]})]"
                            )
                            lines.append("sim.Projection(")
                            lines.append(f"    {pre_var}, {target_var},")
                            lines.append("    sim.FromListConnector(conn_list),")
                            lines.append("    synapse_type=sim.StaticSynapse(),")
                            lines.append(")")
                            lines.append("")
                elif isinstance(pre_node, nir.LIF | nir.CubaLIF) and isinstance(
                    post_node, nir.LIF | nir.CubaLIF
                ):
                    lines.append(f"# Direct Projection: {pre_name} -> {post_name}")
                    lines.append("sim.Projection(")
                    lines.append(f"    {pre_var}, {post_var},")
                    lines.append("    sim.OneToOneConnector(),")
                    lines.append("    synapse_type=sim.StaticSynapse(weight=1.0, delay=1.0),")
                    lines.append(")")
                    lines.append("")

        return "\n".join(lines)
