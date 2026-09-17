"""Brian2 framework importer/exporter for NIR.

Maps Brian2 objects to NIR nodes and NIR graphs to Brian2 script code.
"""

from __future__ import annotations

import json
import urllib.error
import urllib.request
from typing import Any

import nir
import numpy as np

from neurocnl.converter._diagnostics import raise_unsupported_node
from neurocnl.runtime.population_sizes import reconcile_population_sizes_from_linear_weights


class Brian2IO:
    """Brian2 framework handler for NIR conversion."""

    def to_nir(self, model: Any, **kwargs: Any) -> nir.NIRGraph:
        """Convert a Brian2 model (NeuronGroups and Synapses) to NIR.

        Parameters
        ----------
        model : list or dict
            Expected as a list or dict of Brian2 objects.
        """
        nodes: dict[str, nir.NIRNode] = {}
        edges: list[tuple[str, str]] = []

        # Simple list of Brian2 objects
        if not isinstance(model, list | tuple | dict):
            model = [model]

        objs = model.values() if isinstance(model, dict) else model

        for obj in objs:
            # Handle NeuronGroups
            if hasattr(obj, "equations") and hasattr(obj, "N"):
                name = getattr(obj, "name", "pop")
                n = obj.N
                nodes[name] = nir.LIF(
                    tau=np.full(n, 0.02),  # Default 20ms tau
                    v_threshold=np.full(n, 1.0),
                    v_leak=np.zeros(n),
                    r=np.ones(n),
                )

            # Handle Synapses
            if hasattr(obj, "source") and hasattr(obj, "target"):
                pre_name = getattr(obj.source, "name", "pre")
                post_name = getattr(obj.target, "name", "post")

                # Get weight matrix (simplified)
                if hasattr(obj, "w"):
                    weights = np.array(obj.w).reshape((obj.target.N, obj.source.N))
                    conn_name = f"conn_{pre_name}_{post_name}"
                    nodes[conn_name] = nir.Linear(weight=weights)
                    edges.append((pre_name, conn_name))
                    edges.append((conn_name, post_name))
                else:
                    edges.append((pre_name, post_name))

        return nir.NIRGraph(nodes=nodes, edges=edges)

    def from_nir(self, graph: nir.NIRGraph, **kwargs: Any) -> str:
        """Convert an NIR graph to Brian2 simulation code (Python string)."""
        lines = [
            '"""Brian2 code — auto-generated from NIR."""',
            "",
            "from brian2 import *",
            "import numpy as np",
            "",
            "defaultclock.dt = 0.1*ms",
            "",
        ]

        _SUPPORTED = (nir.Input, nir.Output, nir.Linear, nir.LIF, nir.CubaLIF)
        node_vars = {}
        for name, node in graph.nodes.items():
            var_name = name.replace(" ", "_").replace("-", "_")
            node_vars[name] = var_name

            if isinstance(node, nir.LIF | nir.CubaLIF):
                n_neurons = node.tau.size if hasattr(node.tau, "size") else 1
                tau = float(node.tau.flat[0]) if hasattr(node.tau, "flat") else 0.02
                lines.append(f"# NIR Node: {name} (LIF)")
                lines.append(f"eqs_{var_name} = '''")
                lines.append(f"dv/dt = -v / ({tau}*second) : 1 (unless refractory)")
                lines.append("'''")
                lines.append(
                    f"{var_name} = NeuronGroup({n_neurons}, eqs_{var_name}, "
                    "threshold='v > 1.0', reset='v = 0.0', method='exact')"
                )
                lines.append("")

            elif isinstance(node, nir.Linear):
                pass

            elif isinstance(node, nir.Input | nir.Output):
                pass  # boundary markers — matches pre-existing behavior

            else:
                raise_unsupported_node(node, "Brian2IO", _SUPPORTED, node_name=name)

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
                            lines.append(f"# Synapse: {pre_name} -> {post_name} -> {next_post}")
                            lines.append(
                                f"S_{pre_var}_{target_var} = Synapses({pre_var}, {target_var}, "
                                "'w : 1', on_pre='v += w')"
                            )
                            lines.append(f"S_{pre_var}_{target_var}.connect()")
                            lines.append(f"W_{pre_var}_{target_var} = np.array({weight.tolist()})")
                            lines.append(
                                f"S_{pre_var}_{target_var}.w = W_{pre_var}_{target_var}.flatten()"
                            )
                            lines.append("")
                elif isinstance(pre_node, nir.LIF | nir.CubaLIF) and isinstance(
                    post_node, nir.LIF | nir.CubaLIF
                ):
                    lines.append(f"# Direct Synapse: {pre_name} -> {post_name}")
                    lines.append(
                        f"S_{pre_var}_{post_var} = Synapses({pre_var}, {post_var}, "
                        "on_pre='v += 1.0')"
                    )
                    lines.append(f"S_{pre_var}_{post_var}.connect(j='i')")
                    lines.append("")

        return "\n".join(lines)

    def to_runtime_payload(
        self,
        graph: nir.NIRGraph,
        *,
        weight_bit_width: int = 8,
    ) -> dict[str, Any]:
        """Build a Brian2-worker-compatible runtime payload from NIR."""
        populations: list[dict[str, Any]] = []
        population_sizes: dict[str, int] = {}
        population_order: list[str] = []
        connections: list[dict[str, Any]] = []
        dense_nodes: dict[str, np.ndarray[Any, Any]] = {}
        seen_connections: set[tuple[str, str]] = set()

        for name, node in graph.nodes.items():
            if isinstance(node, nir.LIF | nir.CubaLIF):
                size = int(node.tau.size) if hasattr(node.tau, "size") else 1
                population_sizes[name] = size
                population_order.append(name)
                populations.append(
                    {
                        "name": name,
                        "size": size,
                        "threshold": self._first_scalar(node.v_threshold, 1.0),
                        "tau_rc": self._first_scalar(node.tau, 0.02),
                        "role": "hidden",
                    }
                )
            elif isinstance(node, nir.Linear):
                dense_nodes[name] = np.asarray(node.weight, dtype=float)

        population_sizes = reconcile_population_sizes_from_linear_weights(
            graph, population_sizes
        )
        for pop_entry in populations:
            pop_entry["size"] = population_sizes[pop_entry["name"]]

        for pre_name, post_name in graph.edges:
            dense_weight: np.ndarray[Any, Any] | None = None
            source_name = pre_name
            target_name = post_name

            if post_name in dense_nodes:
                dense_weight = dense_nodes[post_name]
                downstream = self._next_population_target(graph, post_name)
                if downstream is None:
                    continue
                target_name = downstream
            elif pre_name in dense_nodes:
                dense_weight = dense_nodes[pre_name]
                upstream = self._previous_population_source(graph, pre_name)
                if upstream is None:
                    continue
                source_name = upstream
            else:
                source_size = population_sizes.get(pre_name, 1)
                target_size = population_sizes.get(post_name, 1)
                dense_weight = np.eye(target_size, source_size)

            if source_name not in population_sizes or target_name not in population_sizes:
                continue
            if (source_name, target_name) in seen_connections:
                continue
            seen_connections.add((source_name, target_name))

            connections.append(
                {
                    "pre": source_name,
                    "post": target_name,
                    "weight_count": int(dense_weight.size),
                    "weights": dense_weight.tolist(),
                }
            )

        total_neurons = sum(population_sizes.values())
        return {
            "num_neurons": total_neurons,
            "num_synapses": sum(connection["weight_count"] for connection in connections),
            "neuron_model": "LIF",
            "populations": populations,
            "connections": connections,
            "weight_bit_width": weight_bit_width,
            "network_depth": max(len(population_order), 1),
        }

    def compile_remote(
        self,
        graph: nir.NIRGraph,
        *,
        base_url: str,
        weight_bit_width: int = 8,
        timeout: float = 30.0,
        opener: Any | None = None,
    ) -> dict[str, Any]:
        """Compile a Brian2 runtime payload through an isolated HTTP backend."""
        payload = {
            "network": self.to_runtime_payload(graph, weight_bit_width=weight_bit_width),
        }
        return self._post_json(
            f"{base_url.rstrip('/')}/api/neurocnl/brian2/compile",
            payload,
            timeout=timeout,
            opener=opener,
        )

    def run_remote(
        self,
        *,
        base_url: str,
        session_id: str,
        steps: int = 100,
        timeout: float = 30.0,
        opener: Any | None = None,
    ) -> dict[str, Any]:
        """Run a previously compiled Brian2 session through an isolated HTTP backend."""
        return self._post_json(
            f"{base_url.rstrip('/')}/api/neurocnl/brian2/run",
            {"session_id": session_id, "steps": steps},
            timeout=timeout,
            opener=opener,
        )

    def compile_and_run_remote(
        self,
        graph: nir.NIRGraph,
        *,
        base_url: str,
        steps: int = 100,
        weight_bit_width: int = 8,
        timeout: float = 30.0,
        opener: Any | None = None,
    ) -> dict[str, Any]:
        """Compile and run a Brian2 graph via the isolated HTTP backend."""
        compile_response = self.compile_remote(
            graph,
            base_url=base_url,
            weight_bit_width=weight_bit_width,
            timeout=timeout,
            opener=opener,
        )
        session_id = str(compile_response["session_id"])
        run_response = self.run_remote(
            base_url=base_url,
            session_id=session_id,
            steps=steps,
            timeout=timeout,
            opener=opener,
        )
        return {"compile": compile_response, "run": run_response}

    def _post_json(
        self,
        url: str,
        payload: dict[str, Any],
        *,
        timeout: float,
        opener: Any | None,
    ) -> dict[str, Any]:
        open_request = opener or urllib.request.urlopen
        request = urllib.request.Request(
            url=url,
            data=json.dumps(payload).encode("utf-8"),
            method="POST",
            headers={"Content-Type": "application/json"},
        )
        try:
            with open_request(request, timeout=timeout) as response:
                body = response.read().decode("utf-8")
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode("utf-8", errors="replace")
            raise RuntimeError(
                f"Brian2 backend request failed with HTTP {exc.code}: {detail}"
            ) from exc
        except urllib.error.URLError as exc:
            raise RuntimeError(f"Could not reach Brian2 backend at {url}: {exc.reason}") from exc

        payload_obj = json.loads(body)
        if not isinstance(payload_obj, dict):
            raise RuntimeError("Brian2 backend returned a non-object JSON response.")
        return payload_obj

    def _next_population_target(self, graph: nir.NIRGraph, node_name: str) -> str | None:
        for pre_name, post_name in graph.edges:
            if pre_name == node_name and isinstance(
                graph.nodes.get(post_name), nir.LIF | nir.CubaLIF
            ):
                return str(post_name)
        return None

    def _previous_population_source(self, graph: nir.NIRGraph, node_name: str) -> str | None:
        for pre_name, post_name in graph.edges:
            if post_name == node_name and isinstance(
                graph.nodes.get(pre_name), nir.LIF | nir.CubaLIF
            ):
                return str(pre_name)
        return None

    def _first_scalar(self, value: Any, default: float) -> float:
        if value is None:
            return default
        array = np.asarray(value, dtype=float)
        if array.size == 0:
            return default
        return float(array.flat[0])
