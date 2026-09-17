"""sc-neurocore simulator adapter for the shared CNL → NIR → Simulator contract.

This module bridges the T1-5 contract layer with the ``sc-neurocore``
stochastic-computing SNN framework.  It exposes a single public class,
:class:`ScNeuroCoreSimulatorAdapter`, that:

1. Accepts a compiled ``nir.NIRGraph``.
2. Builds a :class:`sc_neurocore.network.Population` per LIF/CubaLIF node,
   mapping NIR parameters to :class:`sc_neurocore.neurons.StochasticLIFNeuron`.
3. Runs a manual per-timestep simulation loop, propagating input currents
   through Linear weight matrices and stepping each population.
4. Normalises spike and voltage output into the shared ``SimulatorRunResult``
   schema used by all CNL Studio simulator backends.

Design constraints
------------------
- ``sc_neurocore`` and its submodules are **never imported at module level** —
  missing the package must not crash the NeuroCNL backend at startup.
- There is no remote-worker path: sc-neurocore runs in-process.
- CubaLIF is approximated as LIF with mean tau; synaptic filter not modelled.
- FPGA RTL export (``sc_neurocore.ir.export_scnir_from_nir``) is intentionally
  out of scope here — that path is a static code-generation step.
"""

from __future__ import annotations

import logging
import time
from collections import defaultdict
from dataclasses import dataclass, field
from typing import Any

import nir
import numpy as np

from neurocnl.lif_semantics import discretize_lif
from neurocnl.runtime.population_sizes import (
    lif_population_size,
    reconcile_population_sizes_from_linear_weights,
)
from neurocnl.runtime.stimulus import ValidatedStimulus

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Public result type
# ---------------------------------------------------------------------------


@dataclass(slots=True)
class ScNeuroCoreSimulatorResult:
    """Result returned by :class:`ScNeuroCoreSimulatorAdapter`.

    Attributes
    ----------
    spikes : dict[str, dict[str, list[int]]]
        ``population_name → {neuron_index_str → [timestep, ...]}``
    voltages : dict[str, dict[str, list[float]]]
        Membrane traces, if the installed sc-neurocore version exposes them.
        ``population_name → {neuron_index_str → [voltage_at_t0, ...]}``
    execution_time_ms : float
        Wall-clock time for the sc-neurocore timestep loop.
    runtime_mode : str
        Always ``"in_process_sc_neurocore_sim"``.
    warnings : list[str]
        Non-fatal messages about approximated NIR semantics or missing
        optional capabilities in the installed sc-neurocore version.
    """

    spikes: dict[str, dict[str, list[int]]] = field(default_factory=dict)
    voltages: dict[str, dict[str, list[float]]] = field(default_factory=dict)
    execution_time_ms: float = 0.0
    runtime_mode: str = "in_process_sc_neurocore_sim"
    warnings: list[str] = field(default_factory=list)


# ---------------------------------------------------------------------------
# Private helpers for NIR parameter mapping and graph traversal
# ---------------------------------------------------------------------------


def _lif_params_for_node(
    node: nir.LIF | nir.CubaLIF,
    seed: int,
    graph: nir.NIRGraph | None = None,
) -> dict[str, Any]:
    """Map NIR LIF / CubaLIF parameters to StochasticLIFNeuron kwargs.

    ``StochasticLIFNeuron`` integrates a *different* ODE from NIR::

        v += -(v - v_rest) * (dt / tau_mem) + resistance * I * dt

    Its input gain sits outside the ``1/tau``, where NIR's sits inside. Working
    in timestep units (``dt = 1``, ``tau_mem = tau/dt_seconds``) and folding the
    NIR input gain into ``resistance`` makes the two exactly equal::

        v[t+1] = beta * v[t] + input_scale * I[t]

    which is the same recurrence snnTorch's ``Leaky`` runs, so both backends
    report the same membrane trace for the same network.

    Scaling ``resistance`` rather than dividing the threshold is deliberate.
    ``v_rest``, ``v_reset`` and ``noise_std`` are voltages too; threshold-scaling
    would silently break them at any non-zero leak, and would leave the plotted
    membrane trace off by ``1/input_scale`` — 200x for tau = 0.02 s — against
    the other backends' panels.

    Previously this passed ``tau`` straight through in seconds against a
    hardcoded ``dt = 1.0``, giving ``dt/tau = 500`` for a 2 ms time constant.
    Forward Euler is unstable above ``dt/tau = 2``, so the membrane diverged
    to +/-1e6 instead of decaying.
    """
    discretization = discretize_lif(node, graph=graph)
    return {
        "tau_mem": max(1e-6, discretization.tau_steps),
        "resistance": max(1e-6, discretization.input_scale),
        "v_threshold": discretization.v_threshold,
        "v_reset": discretization.v_leak,
        "v_rest": discretization.v_leak,
        "dt": 1.0,
        "seed": seed,
    }


def _build_adjacency(
    graph: nir.NIRGraph,
) -> tuple[dict[str, list[str]], dict[str, list[str]]]:
    """Return (in_edges, out_edges) adjacency dicts for the NIR graph."""
    in_edges: dict[str, list[str]] = {n: [] for n in graph.nodes}
    out_edges: dict[str, list[str]] = {n: [] for n in graph.nodes}
    for src, dst in graph.edges:
        out_edges[src].append(dst)
        in_edges[dst].append(src)
    return in_edges, out_edges


def _topological_sort(
    graph: nir.NIRGraph,
) -> tuple[list[str], dict[str, list[str]]]:
    """Kahn's algorithm; returns (topo_order, in_edges)."""
    in_edges, out_edges = _build_adjacency(graph)
    in_degree = {n: len(ins) for n, ins in in_edges.items()}
    queue = [n for n, d in in_degree.items() if d == 0]
    order: list[str] = []
    while queue:
        node_name = queue.pop(0)
        order.append(node_name)
        for dst in out_edges[node_name]:
            in_degree[dst] -= 1
            if in_degree[dst] == 0:
                queue.append(dst)
    return order, in_edges


# ---------------------------------------------------------------------------
# Error type
# ---------------------------------------------------------------------------


class ScNeuroCoreDispatchError(RuntimeError):
    """Raised when the sc-neurocore adapter cannot build or run the simulation.

    Attributes
    ----------
    diagnostics : list[str]
        Human-readable messages, one per detected problem.
    """

    def __init__(self, *diagnostics: str) -> None:
        self.diagnostics: list[str] = list(diagnostics)
        super().__init__("; ".join(diagnostics))


# ---------------------------------------------------------------------------
# Import helpers (never at module level)
# ---------------------------------------------------------------------------


def _import_sc_neurocore() -> Any:
    """Import and return the ``sc_neurocore`` module.

    Raises
    ------
    ImportError
        When ``sc-neurocore`` is not installed.
    """
    import sc_neurocore
    import sc_neurocore.network
    import sc_neurocore.neurons

    return sc_neurocore


def sc_neurocore_nir_bridge_available() -> bool:
    """Return ``True`` if sc-neurocore is installed and exposes the NIR bridge.

    The NIR bridge is ``sc_neurocore.nir_bridge.from_nir``, which loads a NIR
    graph into sc-neurocore's network representation.  Used as a Docker
    build-time verification probe.

    Returns
    -------
    bool
        ``True`` when ``sc_neurocore.nir_bridge.from_nir`` can be imported and
        is callable.  ``False`` when the package is absent or the capability is
        missing.
    """
    try:
        from sc_neurocore.nir_bridge import from_nir

        return callable(from_nir)
    except ImportError:
        return False


# ---------------------------------------------------------------------------
# Internal helpers (kept for backward compatibility and direct test coverage)
# ---------------------------------------------------------------------------


def _infer_output_population(graph: nir.NIRGraph) -> str:
    """Return the name of the primary LIF output population in the NIR graph.

    Uses the last ``nir.LIF`` / ``nir.CubaLIF`` node (by insertion order) as a
    heuristic.  Falls back to the last node name in the graph.
    """
    lif_names: list[str] = [
        str(name)
        for name, node in graph.nodes.items()
        if isinstance(node, nir.LIF | nir.CubaLIF)
    ]
    if lif_names:
        return lif_names[-1]
    for _pre, post in reversed(graph.edges):
        if post in graph.nodes and isinstance(graph.nodes[post], nir.LIF | nir.CubaLIF):
            return str(post)
    return str(list(graph.nodes)[-1]) if graph.nodes else "output"


def _build_spike_record(
    raw_spikes: Any,
    output_pop_name: str,
    timesteps: int,
) -> dict[str, dict[str, list[int]]]:
    """Convert various spike-output shapes to the shared schema.

    Accepts:

    - A ``dict[str, list[int]]`` (neuron_idx_str → [timestep, ...]) already
      keyed under the population name.
    - A 2-D array of shape (timesteps, n_neurons).
    - ``None`` when no spikes were recorded.

    Returns
    -------
    dict[str, dict[str, list[int]]]
        ``{output_pop_name: {neuron_idx_str: [timestep, ...]}}``
    """
    if raw_spikes is None:
        return {}

    # Already in the shared dict-of-dicts shape (population → neuron → times).
    if isinstance(raw_spikes, dict):
        if raw_spikes and isinstance(next(iter(raw_spikes.values())), dict):
            return {
                k: {str(ni): v for ni, v in inner.items()}
                for k, inner in raw_spikes.items()
            }
        # Flat {neuron_idx: [times]} dict — wrap under the population name.
        return {output_pop_name: {str(k): v for k, v in raw_spikes.items() if v}}

    # 2-D sequence: rows = timesteps, columns = neurons.
    try:
        matrix = np.asarray(raw_spikes)
        if matrix.ndim == 1:
            # 1-D array: single neuron, spike presence per timestep.
            matrix = matrix.reshape(-1, 1)
        if matrix.ndim != 2:
            return {}
        neuron_spikes: dict[str, list[int]] = defaultdict(list)
        for t in range(matrix.shape[0]):
            for n in range(matrix.shape[1]):
                if matrix[t, n]:
                    neuron_spikes[str(n)].append(t)
        return {output_pop_name: dict(neuron_spikes)} if neuron_spikes else {}
    except Exception:  # noqa: BLE001
        return {}


# ---------------------------------------------------------------------------
# Main adapter
# ---------------------------------------------------------------------------


class ScNeuroCoreSimulatorAdapter:
    """Dispatch a compiled NIR graph to sc-neurocore for fixed-weight simulation.

    Always runs in-process using ``sc_neurocore.network``.  Raises
    :class:`ScNeuroCoreDispatchError` when ``sc-neurocore`` is not installed or
    when execution fails.
    """

    def run(
        self,
        graph: nir.NIRGraph,
        stimulus: ValidatedStimulus,
        timesteps: int,
        seed: int,
    ) -> ScNeuroCoreSimulatorResult:
        """Simulate *graph* with sc-neurocore and return spike output.

        Parameters
        ----------
        graph : nir.NIRGraph
            Compiled NIR graph from ``compile_to_nir()``.
        stimulus : ValidatedStimulus
            Validated stimulus specifying input spike times.  sc-neurocore's
            NIR adapter accepts the input spike schedule as a dense spike
            tensor injected at the ``nir.Input`` port.
        timesteps : int
            Number of simulation timesteps.
        seed : int
            Random seed.  Forwarded to sc-neurocore to ensure deterministic
            noise (if any) in the Rust simulation loop.

        Returns
        -------
        ScNeuroCoreSimulatorResult

        Raises
        ------
        ScNeuroCoreDispatchError
            When ``sc-neurocore`` is not installed, the NIR graph cannot be
            loaded, or the timestep loop fails.
        """
        try:
            sc_neurocore = _import_sc_neurocore()
        except ImportError as exc:
            raise ScNeuroCoreDispatchError(
                f"sc-neurocore is not installed: {exc}.  Install with: pip install sc-neurocore"
            ) from exc

        try:
            return self._simulate(graph, stimulus, timesteps, seed, sc_neurocore)
        except ScNeuroCoreDispatchError:
            raise
        except Exception as exc:  # noqa: BLE001
            raise ScNeuroCoreDispatchError(
                f"sc-neurocore simulation failed: {exc}"
            ) from exc

    # ------------------------------------------------------------------
    # Internal simulation — uses sc_neurocore.network manual timestep loop
    # ------------------------------------------------------------------

    def _simulate(
        self,
        graph: nir.NIRGraph,
        stimulus: ValidatedStimulus,
        timesteps: int,
        seed: int,
        sc_neurocore: Any,
    ) -> ScNeuroCoreSimulatorResult:
        """Run a per-timestep simulation using sc_neurocore.network."""
        Population = sc_neurocore.network.Population
        SpikeMonitor = sc_neurocore.network.SpikeMonitor
        StochasticLIFNeuron = sc_neurocore.neurons.StochasticLIFNeuron

        warnings_out: list[str] = []

        # ── 1. Build populations for every LIF / CubaLIF node ────────────────
        populations: dict[str, Any] = {}
        spike_monitors: dict[str, Any] = {}

        population_sizes: dict[str, int] = {
            name: lif_population_size(node)
            for name, node in graph.nodes.items()
            if isinstance(node, nir.LIF | nir.CubaLIF)
        }
        population_sizes = reconcile_population_sizes_from_linear_weights(
            graph, population_sizes
        )

        for name, node in graph.nodes.items():
            if isinstance(node, nir.LIF | nir.CubaLIF):
                n = population_sizes[name]
                params = _lif_params_for_node(node, seed, graph)
                if isinstance(node, nir.CubaLIF):
                    warnings_out.append(
                        f"CubaLIF node '{name}' approximated as LIF "
                        "(synaptic filter not modelled by sc_neurocore adapter)."
                    )
                populations[name] = Population(
                    StochasticLIFNeuron, n=n, params=params, label=name
                )
                spike_monitors[name] = SpikeMonitor(populations[name])

        if not populations:
            warnings_out.append(
                "No LIF or CubaLIF nodes found in NIR graph; nothing to simulate."
            )
            return ScNeuroCoreSimulatorResult(warnings=warnings_out)

        # ── 2. Topological order + edge adjacency ─────────────────────────────
        topo_order, in_edges = _topological_sort(graph)

        # ── 3. Build input spike matrix from ValidatedStimulus ───────────────
        input_size = stimulus.neuron_count
        spike_matrix = np.zeros((timesteps, input_size), dtype=np.float64)
        for neuron_idx, spike_times in stimulus.spikes.items():
            for t in spike_times:
                if 0 <= t < timesteps and 0 <= neuron_idx < input_size:
                    spike_matrix[t, neuron_idx] = 1.0

        # ── 4. Manual per-timestep simulation loop ───────────────────────────
        t_start = time.monotonic()
        voltage_history: dict[str, list[np.ndarray[Any, np.dtype[np.float64]]]] = {
            n: [] for n in populations
        }

        for t in range(timesteps):
            node_output: dict[str, np.ndarray[Any, np.dtype[np.float64]]] = {}

            for node_name in topo_order:
                node = graph.nodes[node_name]

                if isinstance(node, nir.Input):
                    node_output[node_name] = spike_matrix[t]

                elif isinstance(node, nir.Linear):
                    srcs = in_edges[node_name]
                    w = np.atleast_2d(node.weight)
                    in_dim = w.shape[1]
                    raw_sig = node_output.get(srcs[0]) if srcs else None
                    if raw_sig is None or raw_sig.size == 0:
                        src_sig = np.zeros(in_dim, dtype=np.float64)
                    else:
                        src_sig = np.asarray(raw_sig, dtype=np.float64).flatten()
                        if src_sig.size < in_dim:
                            src_sig = np.pad(src_sig, (0, in_dim - src_sig.size))
                        elif src_sig.size > in_dim:
                            src_sig = src_sig[:in_dim]
                    node_output[node_name] = w @ src_sig

                elif isinstance(node, nir.Affine):
                    srcs = in_edges[node_name]
                    w = np.atleast_2d(node.weight)
                    in_dim = w.shape[1]
                    raw_sig = node_output.get(srcs[0]) if srcs else None
                    if raw_sig is None or raw_sig.size == 0:
                        src_sig = np.zeros(in_dim, dtype=np.float64)
                    else:
                        src_sig = np.asarray(raw_sig, dtype=np.float64).flatten()
                        if src_sig.size < in_dim:
                            src_sig = np.pad(src_sig, (0, in_dim - src_sig.size))
                        elif src_sig.size > in_dim:
                            src_sig = src_sig[:in_dim]
                    bias = np.asarray(node.bias, dtype=np.float64).flatten()
                    node_output[node_name] = w @ src_sig + bias

                elif isinstance(node, nir.LIF | nir.CubaLIF):
                    srcs = in_edges[node_name]
                    lif_src_sig = node_output.get(srcs[0]) if srcs else None
                    pop = populations[node_name]
                    n_neurons: int = pop.n

                    if lif_src_sig is None or lif_src_sig.size == 0:
                        currents = np.zeros(n_neurons, dtype=np.float64)
                    else:
                        currents = np.asarray(lif_src_sig, dtype=np.float64)
                        if currents.size < n_neurons:
                            currents = np.pad(currents, (0, n_neurons - currents.size))
                        else:
                            currents = currents[:n_neurons]

                    spikes = pop.step_all(currents)
                    spike_monitors[node_name].record(spikes, t)

                    v_values: np.ndarray[Any, np.dtype[np.float64]] = np.zeros(
                        n_neurons
                    )
                    found = False

                    # 1) Try get_states() dict with common membrane keys.
                    v_state = pop.get_states()
                    if v_state is not None:
                        for key in ("v", "membrane", "potential", "voltage"):
                            candidate = v_state.get(key)
                            if candidate is not None and not isinstance(
                                candidate, int | float | bool
                            ):
                                try:
                                    v_values = np.asarray(
                                        candidate, dtype=np.float64
                                    ).flatten()
                                    if v_values.shape[0] >= n_neurons:
                                        v_values = v_values[:n_neurons]
                                    found = True
                                    break
                                except (ValueError, TypeError):
                                    pass

                    # 2) Fallback — read v directly from the neuron object.
                    if not found:
                        for attr in ("v", "_v", "membrane", "voltage", "state"):
                            if hasattr(pop, attr):
                                try:
                                    candidate = getattr(pop, attr)
                                    if not isinstance(candidate, int | float | bool):
                                        v_values = np.asarray(
                                            candidate, dtype=np.float64
                                        ).flatten()
                                        if v_values.shape[0] >= n_neurons:
                                            v_values = v_values[:n_neurons]
                                        found = True
                                        break
                                except (ValueError, TypeError):
                                    pass

                    voltage_history[node_name].append(
                        np.asarray(v_values, dtype=float).copy()
                    )
                    node_output[node_name] = spikes.astype(np.float64)

        execution_time_ms = (time.monotonic() - t_start) * 1000.0

        # ── 5. Collect spike results from SpikeMonitor.raster_data() ─────────
        output_pop_name = _infer_output_population(graph)
        result_spikes: dict[str, dict[str, list[int]]] = {}

        for pop_name, mon in spike_monitors.items():
            try:
                t_arr, n_arr = mon.raster_data()
                # A silent population still gets its key, with an empty value.
                # Dropping it entirely left the Studio's Activity tab with no
                # population to select at all, so a network that ran and stayed
                # quiet was indistinguishable from one that never ran.
                neuron_times: dict[str, list[int]] = {}
                for ts, ni in zip(t_arr.tolist(), n_arr.tolist(), strict=False):
                    neuron_times.setdefault(str(int(ni)), []).append(int(ts))
                result_spikes[pop_name] = neuron_times
            except Exception as exc:  # noqa: BLE001
                warnings_out.append(
                    f"Could not retrieve spikes for population '{pop_name}': {exc}"
                )

        if not result_spikes.get(output_pop_name):
            warnings_out.append(
                f"sc-neurocore ran {timesteps} timesteps but recorded no spikes in "
                f"population '{output_pop_name}'. "
                "Check your stimulus spike times and neuron threshold settings."
            )

        # ── 6. Collect voltage traces from recorded history ──────────────────
        voltages: dict[str, dict[str, list[float]]] = {}
        for pop_name, v_hist in voltage_history.items():
            if not v_hist:
                continue
            v_matrix = np.stack(v_hist, axis=0)  # (timesteps, n_neurons)
            per_neuron: dict[str, list[float]] = {}
            for n_idx in range(v_matrix.shape[1]):
                per_neuron[str(n_idx)] = [
                    round(float(v), 5) for v in v_matrix[:, n_idx]
                ]
            if per_neuron:
                voltages[pop_name] = per_neuron

        return ScNeuroCoreSimulatorResult(
            spikes=result_spikes,
            voltages=voltages,
            execution_time_ms=round(execution_time_ms, 3),
            runtime_mode="in_process_sc_neurocore_sim",
            warnings=warnings_out,
        )
