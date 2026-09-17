"""Lava framework importer/exporter for NIR.

Maps Lava processes to NIR nodes and NIR graphs to Lava process definitions.
"""

from __future__ import annotations

import json
import logging
import urllib.error
import urllib.request
from typing import Any

_logger = logging.getLogger(__name__)

import nir
import numpy as np

from neurocnl.converter._diagnostics import raise_unsupported_node
from neurocnl.lif_semantics import lava_lif_parameters, resolve_dt
from neurocnl.runtime.population_sizes import (
    reconcile_population_sizes_from_linear_weights,
)


def _input_neuron_count(node: nir.Input) -> int:
    """Infer the neuron count for a ``nir.Input`` node from its ``input_type`` shape.

    Mirrors ``neurocnl.runtime.stimulus._neuron_count`` (duplicated here to avoid
    a converter -> runtime import dependency). ``nir.Input.input_type`` is a dict
    mapping port name -> shape array (e.g. ``{'input': array([2])}``).
    """
    try:
        input_type = node.input_type
        if isinstance(input_type, dict) and input_type:
            shape = next(iter(input_type.values()))
            if hasattr(shape, "__len__") and len(shape) > 0:
                return int(shape[0])
        elif hasattr(input_type, "__len__") and len(input_type) > 0:
            return int(input_type[0])
    except (AttributeError, TypeError, IndexError, StopIteration):
        pass
    return 1  # conservative fallback


class LavaIO:
    """Lava framework handler for NIR conversion."""

    def to_nir(self, model: Any, **kwargs: Any) -> nir.NIRGraph:
        """Convert a Lava model (Process or list of Processes) to NIR.

        Lava's hierarchical processes and implicit connectivity make extraction complex.
        This implementation extracts Process properties for LIF and Dense.
        """
        nodes: dict[str, nir.NIRNode] = {}
        edges: list[tuple[str, str]] = []

        processes = model if isinstance(model, list) else [model]

        # Simple extraction of Process properties
        for i, proc in enumerate(processes):
            name = getattr(proc, "name", f"proc_{i}")

            # Map Lava LIF to NIR LIF
            from lava.proc.lif.process import LIF

            if isinstance(proc, LIF):
                n = proc.shape[0]
                # Map Lava 'du' (decay) back to NIR 'tau'
                # Lava du=1/tau (approx)
                du = getattr(proc.du, "init", 10)
                tau = 1.0 / float(du) if du > 0 else 0.02
                nodes[name] = nir.LIF(
                    tau=np.full(n, tau),
                    v_threshold=np.full(n, 128.0),  # Lava default vth
                    v_leak=np.zeros(n),
                    r=np.ones(n),
                )

            # Map Lava Dense to NIR Linear
            from lava.proc.dense.process import Dense

            if isinstance(proc, Dense):
                weights = getattr(proc.weights, "init", np.eye(proc.shape[0]))
                nodes[name] = nir.Linear(weight=np.array(weights))

        # Connectivity extraction would require inspecting Lava's runtime graph.
        # Current limitation: Edges are not automatically inferred in Lava -> NIR.
        return nir.NIRGraph(nodes=nodes, edges=edges)

    def from_nir(
        self, graph: nir.NIRGraph, hw_mode: bool = False, **kwargs: Any
    ) -> str:
        """Convert an NIR graph to Lava process definitions (Python code).

        Returns a Python string that defines and connects Lava Processes.
        """
        lines = [
            '"""Lava Process definitions — auto-generated from NIR."""',
            "",
            "import numpy as np",
            "from lava.proc.lif.process import LIF",
            "from lava.proc.dense.process import Dense",
            "from lava.magma.core.run_configs import Loihi2SimCfg, Loihi2HwCfg",
            "from lava.magma.core.run_conditions import RunSteps",
            "",
        ]

        _SUPPORTED = (nir.Input, nir.Output, nir.Linear, nir.LIF, nir.CubaLIF)
        node_vars = {}
        for i, (name, node) in enumerate(graph.nodes.items()):
            var_name = name.replace(" ", "_").replace("-", "_")
            node_vars[name] = var_name

            if isinstance(node, nir.LIF | nir.CubaLIF):
                n_neurons = node.tau.size if hasattr(node.tau, "size") else 1
                tau = float(node.tau.flat[0]) if hasattr(node.tau, "flat") else 0.02
                # NIR tau is in seconds, Lava du is integer decay
                du = int(1.0 / tau) if tau > 0 else 50
                vth = 128
                lines.append(f"# NIR Node: {name} (LIF)")
                lines.append(
                    f"{var_name} = LIF(shape=({n_neurons},), du={du}, dv=1, vth={vth})"
                )
                lines.append("")

            elif isinstance(node, nir.Linear):
                weight = node.weight
                lines.append(f"# NIR Node: {name} (Linear/Dense)")
                lines.append(f"{var_name} = Dense(weights=np.array({weight.tolist()}))")
                lines.append("")

            elif isinstance(node, nir.Input | nir.Output):
                pass  # boundary markers — matches pre-existing behavior

            else:
                raise_unsupported_node(node, "LavaIO", _SUPPORTED, node_name=name)

        for pre_name, post_name in graph.edges:
            if pre_name in node_vars and post_name in node_vars:
                pre_var = node_vars[pre_name]
                post_var = node_vars[post_name]
                pre_node = graph.nodes[pre_name]
                post_node = graph.nodes[post_name]

                if isinstance(pre_node, nir.LIF | nir.CubaLIF) and isinstance(
                    post_node, nir.Linear
                ):
                    lines.append(f"{pre_var}.s_out.connect({post_var}.s_in)")
                elif isinstance(pre_node, nir.Linear) and isinstance(
                    post_node, nir.LIF | nir.CubaLIF
                ):
                    lines.append(f"{pre_var}.a_out.connect({post_var}.a_in)")
                elif isinstance(pre_node, nir.LIF | nir.CubaLIF) and isinstance(
                    post_node, nir.LIF | nir.CubaLIF
                ):
                    dense_name = f"dense_{pre_var}_{post_var}"
                    n = pre_node.tau.size if hasattr(pre_node.tau, "size") else 1
                    lines.append(f"{dense_name} = Dense(weights=np.eye({n}))")
                    lines.append(f"{pre_var}.s_out.connect({dense_name}.s_in)")
                    lines.append(f"{dense_name}.a_out.connect({post_var}.a_in)")
                lines.append("")

        lines.extend(
            [
                "# --- Run simulation ---",
                f"run_cfg = {'Loihi2HwCfg()' if hw_mode else 'Loihi2SimCfg()'}",
                "run_cond = RunSteps(num_steps=1000)",
            ]
        )
        if node_vars:
            first_var = list(node_vars.values())[0]
            lines.extend(
                [
                    f"{first_var}.run(condition=run_cond, run_cfg=run_cfg)",
                    f"{first_var}.stop()",
                ]
            )
        else:
            lines.append("# No populations to run")

        return "\n".join(lines)

    def to_runtime_payload(
        self,
        graph: nir.NIRGraph,
        *,
        weight_bit_width: int = 8,
        stimulus: Any | None = None,
    ) -> dict[str, Any]:
        """Build a Neurochip-compatible Lava runtime payload from NIR.

        Parameters
        ----------
        graph : nir.NIRGraph
            Compiled NIR graph.
        weight_bit_width : int
            Quantization width recorded in the payload metadata.
        stimulus : neurocnl.runtime.stimulus.ValidatedStimulus | None
            Optional validated spike-train stimulus for the graph's
            ``nir.Input`` population.  When provided, it is embedded in the
            payload as ``{"population": ..., "neuron_count": ..., "spikes":
            {idx_str: [timestep, ...]}}`` so both the in-process and remote
            Lava runtimes can build a real spike source process instead of
            leaving the network undriven.
        """
        populations: list[dict[str, Any]] = []
        population_sizes: dict[str, int] = {}
        population_order: list[str] = []
        connections: list[dict[str, Any]] = []
        dense_nodes: dict[str, np.ndarray[Any, Any]] = {}
        seen_connections: set[tuple[str, str]] = set()

        _SUPPORTED = (
            nir.Input,
            nir.Output,
            nir.Linear,
            nir.Affine,
            nir.LIF,
            nir.CubaLIF,
        )
        for name, node in graph.nodes.items():
            if isinstance(node, nir.LIF | nir.CubaLIF):
                # nir.CubaLIF has tau_mem, not tau — reading .tau on one raises.
                tau_arr = getattr(node, "tau", None)
                if tau_arr is None:
                    tau_arr = getattr(node, "tau_mem", None)
                tau_size = getattr(tau_arr, "size", None)
                size = int(tau_size) if tau_size is not None else 1
                population_sizes[name] = size
                population_order.append(name)
                populations.append(
                    {
                        "name": name,
                        "size": size,
                        "threshold": self._first_scalar(node.v_threshold, 1.0),
                        "refractory_period": 0.002,
                        # tau_rc is seconds; consumers discretize it against the
                        # graph timestep via neurocnl.lif_semantics. r and v_leak
                        # travel with it because the threshold rescale needs them.
                        "tau_rc": self._first_scalar(tau_arr, 0.02),
                        "r": self._first_scalar(getattr(node, "r", None), 1.0),
                        "v_leak": self._first_scalar(
                            getattr(node, "v_leak", None), 0.0
                        ),
                        "dt": self._population_dt(node, graph),
                        # Lava's own LIF terms, resolved here so the remote
                        # worker does not have to re-derive them -- it has no
                        # access to neurocnl and would inevitably drift.
                        **self._lava_terms(node, graph),
                        "role": "hidden",
                    }
                )
            elif isinstance(node, nir.Linear):
                dense_nodes[name] = np.asarray(node.weight, dtype=float)
            elif isinstance(node, nir.Affine):
                bias = np.asarray(node.bias, dtype=float)
                if not np.allclose(bias, 0.0):
                    raise ValueError(
                        f"nir.Affine node {name!r} has a non-zero bias "
                        f"(max |bias| = {float(np.abs(bias).max()):.6g}). The "
                        "lava_sim backend maps nir.Affine to "
                        "lava.proc.dense.Dense, which has no bias input, so "
                        "only zero-bias Affine nodes can be simulated. Use a "
                        "bias-free nir.Linear node instead, or choose a "
                        "backend that supports biased affine layers (e.g. "
                        "snntorch_sim)."
                    )
                dense_nodes[name] = np.asarray(node.weight, dtype=float)
            elif isinstance(node, nir.Input):
                # Register the Input node as a real population (role="input")
                # so downstream connection resolution keeps the Input -> Dense
                # -> LIF edge instead of silently dropping it (the network's
                # first synapse would otherwise never appear in "connections",
                # leaving the first hidden population permanently undriven).
                size = _input_neuron_count(node)
                population_sizes[name] = size
                population_order.append(name)
                populations.append(
                    {
                        "name": name,
                        "size": size,
                        "threshold": 0.0,
                        "role": "input",
                    }
                )
            elif isinstance(node, nir.Output):
                pass  # boundary marker — matches pre-existing behavior
            else:
                raise_unsupported_node(
                    node, "LavaIO.to_runtime_payload", _SUPPORTED, node_name=name
                )

        population_sizes = reconcile_population_sizes_from_linear_weights(
            graph, population_sizes
        )

        # Propagate corrected sizes back into the populations list.
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

            if (
                source_name not in population_sizes
                or target_name not in population_sizes
            ):
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
        stimulus_payload: dict[str, Any] | None = None
        if stimulus is not None:
            stimulus_payload = {
                "population": stimulus.population,
                "neuron_count": stimulus.neuron_count,
                "spikes": {
                    str(idx): list(times) for idx, times in stimulus.spikes.items()
                },
            }
        return {
            "num_neurons": total_neurons,
            "num_synapses": sum(
                connection["weight_count"] for connection in connections
            ),
            "neuron_model": "LIF",
            "populations": populations,
            "connections": connections,
            "weight_bit_width": weight_bit_width,
            "network_depth": max(len(population_order), 1),
            "stimulus": stimulus_payload,
        }

    def compile_remote(
        self,
        graph: nir.NIRGraph,
        *,
        base_url: str,
        run_config: str = "sim",
        weight_bit_width: int = 8,
        timeout: float = 30.0,
        opener: Any | None = None,
        stimulus: Any | None = None,
    ) -> dict[str, Any]:
        """Compile a Lava runtime payload through an isolated HTTP backend."""
        payload = {
            "network": self.to_runtime_payload(
                graph, weight_bit_width=weight_bit_width, stimulus=stimulus
            ),
            "run_config": run_config,
        }
        return self._post_json(
            f"{base_url.rstrip('/')}/api/neurochip/hardware/lava/compile",
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
        """Run a previously compiled Lava session through an isolated HTTP backend."""
        return self._post_json(
            f"{base_url.rstrip('/')}/api/neurochip/hardware/lava/run",
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
        run_config: str = "sim",
        weight_bit_width: int = 8,
        timeout: float = 30.0,
        opener: Any | None = None,
        stimulus: Any | None = None,
    ) -> dict[str, Any]:
        """Compile and run a Lava graph via the isolated HTTP backend."""
        compile_response = self.compile_remote(
            graph,
            base_url=base_url,
            run_config=run_config,
            weight_bit_width=weight_bit_width,
            timeout=timeout,
            opener=opener,
            stimulus=stimulus,
        )
        session_id = str(compile_response["session_id"])
        try:
            run_response = self.run_remote(
                base_url=base_url,
                session_id=session_id,
                steps=steps,
                timeout=timeout,
                opener=opener,
            )
        finally:
            # Release the worker's Lava runtime whatever happened. Its processes
            # are backed by POSIX shared memory that only `/stop` frees, so a
            # caller that compiles and runs without stopping leaks a runtime per
            # simulation until the worker runs out of file descriptors and every
            # subsequent run fails with "[Errno 24] Too many open files". The
            # worker now also stops itself after a run; this covers an older
            # worker and any path that raised before it got there.
            self._stop_remote_quietly(
                base_url=base_url, session_id=session_id, timeout=timeout, opener=opener
            )
        return {"compile": compile_response, "run": run_response}

    def _stop_remote_quietly(
        self,
        *,
        base_url: str,
        session_id: str,
        timeout: float,
        opener: Any | None,
    ) -> None:
        """Best-effort ``/stop``; never turns a good run into a failed one."""
        try:
            self._post_json(
                f"{base_url.rstrip('/')}/api/neurochip/hardware/lava/stop",
                {"session_id": session_id},
                timeout=timeout,
                opener=opener,
            )
        except Exception:  # noqa: BLE001
            _logger.debug(
                "Lava session %s could not be stopped", session_id, exc_info=True
            )

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
                f"Lava backend request failed with HTTP {exc.code}: {detail}"
            ) from exc
        except urllib.error.URLError as exc:
            raise RuntimeError(
                f"Could not reach Lava backend at {url}: {exc.reason}"
            ) from exc

        try:
            payload_obj = json.loads(body)
        except json.JSONDecodeError as exc:
            raise RuntimeError(
                f"Lava backend returned non-JSON response: {exc!r}"
            ) from exc
        if not isinstance(payload_obj, dict):
            raise RuntimeError("Lava backend returned a non-object JSON response.")
        return payload_obj

    def _next_population_target(
        self, graph: nir.NIRGraph, node_name: str
    ) -> str | None:
        for pre_name, post_name in graph.edges:
            if pre_name == node_name and isinstance(
                graph.nodes.get(post_name), nir.LIF | nir.CubaLIF
            ):
                return str(post_name)
        return None

    def _previous_population_source(
        self, graph: nir.NIRGraph, node_name: str
    ) -> str | None:
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

    def _lava_terms(self, node: Any, graph: nir.NIRGraph) -> dict[str, float]:
        """``du``/``dv``/``vth`` for this population, or ``{}`` if undecidable.

        Emitted into the runtime payload so the worker is a dumb executor: the
        discretization stays in `neurocnl.lif_semantics`, one formula, and a
        worker that predates these keys simply ignores them.
        """
        tau_arr = getattr(node, "tau", None)
        if tau_arr is None:
            tau_arr = getattr(node, "tau_mem", None)
        tau = self._first_scalar(tau_arr, 0.0)
        if tau <= 0:
            return {}
        try:
            du, dv, vth = lava_lif_parameters(
                tau,
                self._population_dt(node, graph),
                self._first_scalar(getattr(node, "r", None), 1.0) or 1.0,
                self._first_scalar(getattr(node, "v_threshold", None), 1.0) or 1.0,
            )
        except ValueError:
            # The adapter raises its own actionable error for this; the payload
            # just omits the keys rather than shipping a bad decay.
            return {}
        return {"du": du, "dv": dv, "vth": vth}

    def _population_dt(self, node: Any, graph: nir.NIRGraph) -> float:
        """Timestep this population's tau_rc should be discretized against.

        Carried in the payload so the runtime does not have to re-resolve it
        from a graph it no longer holds.
        """
        dt, _ = resolve_dt(node, graph)
        return dt
