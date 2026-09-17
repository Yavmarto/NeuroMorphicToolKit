"""Lava simulator adapter for the shared CNL → NIR → Simulator contract.

This module bridges the T1-5 contract layer with the Intel Lava software
simulator.  It exposes a single public class, :class:`LavaSimulatorAdapter`,
that:

1. Converts a compiled ``nir.NIRGraph`` to a Lava network via
   :class:`neurocnl.converter.lava_io.LavaIO`.
2. Executes it using one of two dispatch paths:

   - **In-process** — imports ``lava`` directly when it is available in the
     current Python process and runs the simulation inside the NeuroCNL
     backend process.
   - **Remote worker** — uses ``LavaIO.compile_and_run_remote()`` when the
     ``NEUROCNL_LAVA_WORKER_URL`` environment variable is set and points to
     a Neurochip Lava worker.

3. Normalises the Lava spike output into the shared
   ``dict[str, dict[str, list[int]]]`` shape expected by
   :class:`~neurocnl.backend.app.schemas.simulators.SimulatorRunResult`.

Design constraints
------------------
- ``neurochip`` is **not** imported here; the neurochip package runs in its
  own venv and is only reachable over HTTP via the remote path.
- Missing ``lava-nc`` must never crash the NeuroCNL backend at import time.
- Loihi 2 hardware mode is always rejected; only ``Loihi2SimCfg`` is used.
"""

from __future__ import annotations

import concurrent.futures
import importlib.util
import logging
import os
import time
from dataclasses import dataclass, field
from typing import Any

import nir
import numpy as np

from neurocnl.converter.lava_io import LavaIO
from neurocnl.lif_semantics import DEFAULT_LIF_DT_SECONDS, lava_lif_parameters
from neurocnl.runtime.stimulus import ValidatedStimulus

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Lava-nc supported NIR node types
# ---------------------------------------------------------------------------

_LAVA_NC_SUPPORTED_TYPES: frozenset[str] = frozenset(
    {"Input", "Output", "LIF", "CubaLIF", "Linear", "Affine", "Delay"}
)


# ---------------------------------------------------------------------------
# Public result type
# ---------------------------------------------------------------------------


@dataclass(slots=True)
class LavaSimulatorResult:
    """Result returned by :class:`LavaSimulatorAdapter`.

    Attributes
    ----------
    spikes : dict[str, dict[str, list[int]]]
        ``population_name → {neuron_index_str → [timestep, ...]}``
    voltages : dict[str, dict[str, list[float]]]
        ``population_name → {neuron_index_str → [voltage_at_t, ...]}``
        Membrane traces captured via the ``v`` probe on the last LIF population.
        Empty when probe data is unavailable or the remote worker omits it.
    execution_time_ms : float
        Wall-clock time for the Lava simulation.
    runtime_mode : str
        One of ``"in_process_lava_sim"``, ``"remote_lava_sim_worker"``.
    warnings : list[str]
        Non-fatal messages about approximations or fallback behaviour.
    """

    spikes: dict[str, dict[str, list[int]]] = field(default_factory=dict)
    voltages: dict[str, dict[str, list[float]]] = field(default_factory=dict)
    execution_time_ms: float = 0.0
    runtime_mode: str = "unknown"
    warnings: list[str] = field(default_factory=list)


# ---------------------------------------------------------------------------
# Error type
# ---------------------------------------------------------------------------


class LavaDispatchError(RuntimeError):
    """Raised when the Lava adapter cannot dispatch or normalise results.

    Attributes
    ----------
    diagnostics : list[str]
        Human-readable messages, one per failure.
    """

    def __init__(self, *diagnostics: str) -> None:
        self.diagnostics: list[str] = list(diagnostics)
        super().__init__("; ".join(diagnostics))


# ---------------------------------------------------------------------------
# Availability helpers
# ---------------------------------------------------------------------------


def _is_lava_available() -> bool:
    """Return True if the ``lava`` package is importable in this process."""
    return importlib.util.find_spec("lava") is not None


def _import_lava() -> tuple[Any, Any, Any, Any, Any, Any]:
    """Import and return Lava classes required for in-process execution.

    Returns
    -------
    tuple of (LIF, Dense, Monitor, RunSteps, Loihi2SimCfg, RingBuffer)
    """
    from lava.magma.core.run_conditions import RunSteps
    from lava.magma.core.run_configs import Loihi2SimCfg
    from lava.proc.dense.process import Dense
    from lava.proc.io.source import RingBuffer
    from lava.proc.lif.process import LIF
    from lava.proc.monitor.process import Monitor

    return LIF, Dense, Monitor, RunSteps, Loihi2SimCfg, RingBuffer


# ---------------------------------------------------------------------------
# Spike normalisation helpers
# ---------------------------------------------------------------------------


def _lava_lif_params(pop: dict[str, Any]) -> tuple[float, float, float]:
    """Map a runtime-payload population onto Lava ``LIF(du, dv, vth)``.

    Lava's ``dv`` is the per-step *voltage decay fraction*, i.e. ``dt/tau`` --
    the complement of the ``beta`` every other backend uses. ``du`` is the
    synaptic-current decay; 1.0 means no synaptic filtering, which is correct
    for a plain LIF. Same mapping as ``paper/nir_to_lava.py`` (which the paper
    build uses and nothing imports).

    ``Loihi2SimCfg()`` is constructed without a ``select_tag``, so it resolves
    to the floating-point ``PyLifModelFloat``: ``du``/``dv`` stay floats and no
    12-bit fixed-point quantization is needed here. Do not copy the fixed-point
    branch from the paper file without also switching the run config.

    The threshold is rescaled by ``1/input_scale`` rather than folding the gain
    into the ``Dense`` weights, because those weights are reported back to the
    user as ``SimulatorRunResult.trained_weights``.

    Previously this ignored ``tau`` entirely and built ``LIF(shape, vth)``, so
    every population ran with Lava's default decay instead of its own.
    """
    name = str(pop.get("name", "?"))
    threshold = float(pop.get("threshold", 1.0))
    tau = float(pop.get("tau_rc", 0.0) or 0.0)
    r = float(pop.get("r", 1.0) or 1.0)
    dt = float(pop.get("dt", DEFAULT_LIF_DT_SECONDS) or DEFAULT_LIF_DT_SECONDS)

    # Refuse the same graphs the other backends refuse. Falling back to Lava's
    # own decay here made Lava the odd one out: the same network "worked" on
    # Lava and failed on snnTorch and SC-NeuroCore, which reads as the backends
    # disagreeing rather than as the network missing its neuron parameters.
    if tau <= 0:
        raise LavaDispatchError(
            f"Population '{name}' has no usable time constant (tau = {tau:g}), so "
            "its neurons cannot leak or fire. A CNL spec stores time constants as "
            "a shape, not a value, so the trained network file has to supply them: "
            "add a NIR Exporter node to your Training canvas and run the pipeline, "
            "then run this target again."
        )

    # Prefer what the payload already resolved, so the in-process and remote
    # paths cannot compute different neurons from the same graph.
    if "dv" in pop and "vth" in pop:
        return float(pop.get("du", 1.0)), float(pop["dv"]), float(pop["vth"])

    try:
        return lava_lif_parameters(tau, dt, r, threshold)
    except ValueError as exc:
        raise LavaDispatchError(f"Population '{name}': {exc}") from exc


def _infer_output_population(graph: nir.NIRGraph) -> str:
    """Return the name of the primary output population in the NIR graph.

    Uses the last ``nir.LIF`` / ``nir.CubaLIF`` node (by traversal order)
    as a heuristic for the output population.  Falls back to the last node
    name in the graph.
    """
    lif_names: list[str] = [
        str(name)
        for name, node in graph.nodes.items()
        if isinstance(node, nir.LIF | nir.CubaLIF)
    ]
    if lif_names:
        return str(lif_names[-1])
    # Last edge target that is a LIF
    for pre, post in reversed(graph.edges):
        if post in graph.nodes and isinstance(graph.nodes[post], nir.LIF | nir.CubaLIF):
            return str(post)
    return str(list(graph.nodes)[-1]) if graph.nodes else "output"


def _build_input_spike_matrix(
    stimulus: ValidatedStimulus,
    population_name: str,
    size: int,
    timesteps: int,
) -> np.ndarray[Any, np.dtype[np.float64]]:
    """Build a dense (neurons, timesteps) binary spike matrix for a Lava ``RingBuffer``.

    Returns an all-zero matrix (silent input) when *stimulus* does not target
    *population_name* -- callers are expected to have already validated that
    the stimulus population exists in the compiled graph.
    """
    matrix = np.zeros((size, timesteps), dtype=int)
    if stimulus.population != population_name:
        return matrix
    for neuron_idx, times in stimulus.spikes.items():
        if not (0 <= neuron_idx < size):
            continue
        for t in times:
            if 0 <= t < timesteps:
                matrix[neuron_idx, t] = 1
    return matrix


def _normalize_flat_spikes(
    flat: dict[str, list[int]],
    population_name: str,
) -> dict[str, dict[str, list[int]]]:
    """Wrap a flat ``{neuron_idx_str: [timestep]}`` dict under the population name.

    Parameters
    ----------
    flat : dict[str, list[int]]
        Neuron-indexed spike dict as returned by ``LavaBackend.run()["spikes"]``
        or the in-process monitor.
    population_name : str
        Name of the population that owns these neurons.
    """
    return {population_name: {k: v for k, v in flat.items() if v}}


def _extract_spikes_from_monitor(
    raw: Any,
    population_process: Any,
    population_name: str,
) -> dict[str, dict[str, list[int]]]:
    """Extract spike times from a Lava ``Monitor.get_data()`` result.

    The Monitor stores data as ``{process_name: {"s_out": matrix}}``
    where ``matrix`` is ``(timesteps, n_neurons)``.

    Returns the shared ``{population_name: {idx_str: [timestep]}}`` shape.
    """
    flat: dict[str, list[int]] = {}
    if not isinstance(raw, dict):
        return {}

    proc_name = getattr(population_process, "name", "")
    port_data = raw.get(proc_name, {})
    spike_array = port_data.get("s_out") if isinstance(port_data, dict) else None

    if spike_array is None:
        # ponytail: Lava auto-names processes; if the probed process name does
        # not match monitor keys, fall back to the first s_out block rather than
        # returning an empty raster for a network that did fire.
        for candidate in raw.values():
            if isinstance(candidate, dict) and candidate.get("s_out") is not None:
                spike_array = candidate["s_out"]
                break
    if spike_array is None:
        return {}

    matrix = np.asarray(spike_array)
    if matrix.ndim == 1:
        matrix = matrix.reshape(-1, 1)
    if matrix.ndim != 2:
        return {}

    for neuron_idx in range(matrix.shape[1]):
        times = np.nonzero(matrix[:, neuron_idx])[0].tolist()
        if times:
            flat[str(neuron_idx)] = times

    return _normalize_flat_spikes(flat, population_name) if flat else {}


def _extract_voltages_from_monitor(
    raw: Any,
    population_process: Any,
    population_name: str,
) -> dict[str, dict[str, list[float]]]:
    """Extract membrane voltage traces from a Lava ``Monitor.get_data()`` result.

    The Monitor stores data as ``{process_name: {variable_name: matrix}}``
    where ``matrix`` is ``(timesteps, n_neurons)`` with membrane voltages.

    Tries common voltage variable names (``v``, ``membrane``, ``potential``)
    and falls back to the first non-spike probe when ``v`` is unavailable.

    Returns ``{population_name: {idx_str: [voltage_per_t, ...]}}``,
    or an empty dict when no voltage probe data is present.
    """
    if not isinstance(raw, dict):
        return {}
    proc_name = getattr(population_process, "name", "")
    port_data = raw.get(proc_name, {})
    if not isinstance(port_data, dict):
        return {}

    v_array = None
    for key in ("v", "membrane", "potential", "voltage"):
        candidate = port_data.get(key)
        if candidate is not None:
            v_array = candidate
            break

    if v_array is None:
        for key, candidate in sorted(port_data.items()):
            if key == "s_out":
                continue
            if candidate is not None:
                v_array = candidate
                break

    if v_array is None:
        # Fallback: try to read v directly from the process model (final state).
        try:
            pm = getattr(population_process, "_process_model", None)
            if pm is None:
                pm = getattr(population_process, "process_model", None)
            if pm is not None and hasattr(pm, "v"):
                v_array = np.asarray(pm.v, dtype=float)
                if v_array.ndim == 1:
                    v_array = v_array.reshape(1, -1)
        except Exception:  # noqa: BLE001
            return {}

    if v_array is None:
        return {}

    matrix = np.asarray(v_array, dtype=float)
    if matrix.ndim == 1:
        matrix = matrix.reshape(-1, 1)
    if matrix.ndim != 2:
        return {}
    per_neuron: dict[str, list[float]] = {}
    for neuron_idx in range(matrix.shape[1]):
        per_neuron[str(neuron_idx)] = [
            round(float(v), 5) for v in matrix[:, neuron_idx]
        ]
    return {population_name: per_neuron} if per_neuron else {}


# ---------------------------------------------------------------------------
# Main adapter class
# ---------------------------------------------------------------------------


class LavaSimulatorAdapter:
    """Dispatch a compiled NIR graph to the Lava software simulator.

    Uses the in-process path when ``lava`` is importable.  Falls back to
    the remote worker path when ``worker_url`` is provided.  Raises
    :class:`LavaDispatchError` when neither path is available.
    """

    def run(
        self,
        graph: nir.NIRGraph,
        stimulus: ValidatedStimulus,
        timesteps: int,
        seed: int,
        *,
        worker_url: str | None = None,
    ) -> LavaSimulatorResult:
        """Simulate *graph* and return normalised spike output.

        Parameters
        ----------
        graph : nir.NIRGraph
            Compiled NIR graph from ``compile_to_nir()``.
        stimulus : ValidatedStimulus
            Validated spike train for the graph's ``nir.Input`` population.
            Injected into the Lava simulation via a ``lava.proc.io.source.RingBuffer``
            (in-process path) or forwarded to the remote Neurochip Lava worker
            (remote path) so the network is actually driven, rather than left silent.
        timesteps : int
            Number of simulation timesteps.
        seed : int
            Random seed.  Applied via ``np.random.seed`` before the in-process
            simulation begins and recorded in result metadata.  The simulation
            dynamics are deterministic for fixed graph weights; this seed
            primarily affects **default stimulus generation** (when no explicit
            stimulus is provided in the API request).
        worker_url : str or None
            Base URL of a remote Neurochip Lava worker.  When provided and
            lava is not importable locally, the remote path is used.

        Returns
        -------
        LavaSimulatorResult

        Raises
        ------
        LavaDispatchError
            When Lava is not available locally AND no worker URL is provided,
            or when execution fails.
        """
        try:
            if _is_lava_available():
                logger.info("lava_sim: dispatching via in-process Lava")
                return self._run_in_process(graph, stimulus, timesteps, seed)
            elif worker_url:
                logger.info("lava_sim: dispatching via remote worker at %s", worker_url)
                return self._run_remote(graph, stimulus, timesteps, worker_url, seed)
            else:
                raise LavaDispatchError(
                    "Lava simulator is not available: 'lava-nc' is not installed in this "
                    "environment and NEUROCNL_LAVA_WORKER_URL is not set.  "
                    "Install lava-nc (pip install lava-nc) or point NEUROCNL_LAVA_WORKER_URL "
                    "at a running Neurochip Lava worker."
                )
        except LavaDispatchError:
            raise
        except Exception as exc:  # noqa: BLE001
            # NOTE: logger here is a stdlib logging.Logger — it does not accept
            # arbitrary keyword arguments like structlog loggers do.
            logger.exception(
                "lava_sim: unexpected exception in run() [%s]", type(exc).__name__
            )
            raise LavaDispatchError(f"Lava simulation failed: {exc}") from exc

    # ------------------------------------------------------------------
    # In-process path
    # ------------------------------------------------------------------

    def _run_in_process(
        self,
        graph: nir.NIRGraph,
        stimulus: ValidatedStimulus,
        timesteps: int,
        seed: int,
    ) -> LavaSimulatorResult:
        """Build and run Lava processes directly inside the current Python process."""
        try:
            LIF, Dense, Monitor, RunSteps, Loihi2SimCfg, RingBuffer = _import_lava()
        except ImportError as exc:
            raise LavaDispatchError(f"Failed to import lava: {exc}") from exc

        unsupported_in_graph = [
            f"nir.{type(node).__name__} (node '{name}')"
            for name, node in graph.nodes.items()
            if type(node).__name__ not in _LAVA_NC_SUPPORTED_TYPES
        ]
        if unsupported_in_graph:
            raise LavaDispatchError(
                "The lava-nc adapter cannot execute this NIR graph. "
                "The following node types are not supported by lava-nc processes: "
                + ", ".join(unsupported_in_graph)
                + ". Note: some of these types are supported by lava-dl (netx), "
                "which is outside the scope of lava_sim. "
                "Use snntorch_sim for graphs containing these node types."
            )

        np.random.seed(seed)

        payload = LavaIO().to_runtime_payload(graph, stimulus=stimulus)
        populations = payload.get("populations", [])
        connections = payload.get("connections", [])

        if not any(pop.get("role") != "input" for pop in populations):
            raise LavaDispatchError(
                "The compiled NIR graph produced no LIF populations — nothing to simulate."
            )

        # Determine the output (monitored) population: last connection target or last pop.
        target_pop_name: str
        if connections:
            target_pop_name = str(connections[-1].get("post", populations[-1]["name"]))
        else:
            target_pop_name = str(populations[-1]["name"])

        population_processes: dict[str, Any] = {}
        try:
            for pop in populations:
                name = str(pop["name"])
                size = int(pop["size"])
                if pop.get("role") == "input":
                    spike_matrix = _build_input_spike_matrix(
                        stimulus, name, size, timesteps
                    )
                    population_processes[name] = RingBuffer(data=spike_matrix)
                else:
                    du, dv, threshold = _lava_lif_params(pop)
                    population_processes[name] = LIF(
                        shape=(size,), du=du, dv=dv, vth=threshold
                    )
        except LavaDispatchError:
            # Already actionable and already names its population — re-wrapping
            # it would bury the message behind a generic prefix.
            raise
        except Exception as exc:  # noqa: BLE001
            raise LavaDispatchError(
                f"Lava process initialisation failed while building population '{name}': {exc}"
            ) from exc

        pop_sizes = {str(p["name"]): int(p["size"]) for p in populations}

        for conn in connections:
            pre = str(conn["pre"])
            post = str(conn["post"])
            weights_raw = conn.get("weights")
            src_size = pop_sizes.get(pre, 1)
            tgt_size = pop_sizes.get(post, 1)

            if weights_raw is not None:
                weight_matrix = np.asarray(weights_raw, dtype=float)
            else:
                weight_matrix = np.eye(tgt_size, src_size, dtype=float)

            try:
                dense = Dense(weights=weight_matrix)
                population_processes[pre].s_out.connect(dense.s_in)
                dense.a_out.connect(population_processes[post].a_in)
            except Exception as exc:  # noqa: BLE001
                logger.warning(
                    "lava_sim: could not wire connection %s→%s: %s", pre, post, exc
                )

        monitor = Monitor()
        target_process = population_processes[target_pop_name]
        monitor.probe(target_process.s_out, timesteps)

        # Access the compiled process model so we can read membrane voltage
        # directly after each timestep.  lava-nc Monitor cannot probe
        # internal Vars (only OutPorts), so we capture v manually.
        pm = getattr(target_process, "_process_model", None)
        if pm is None:
            pm = getattr(target_process, "process_model", None)

        _timeout_s: float | None = None
        _timeout_env = os.environ.get("NEUROCNL_LAVA_SIM_TIMEOUT_S")
        if _timeout_env:
            try:
                _timeout_s = float(_timeout_env)
            except ValueError:
                logger.warning(
                    "lava_sim: invalid NEUROCNL_LAVA_SIM_TIMEOUT_S=%r, ignoring",
                    _timeout_env,
                )

        t_start = time.monotonic()
        try:
            if _timeout_s is not None:
                _sim_result: dict[str, list[np.ndarray[Any, np.dtype[np.float64]]]] = {
                    "voltage_history": []
                }

                def _step_loop() -> None:
                    h: list[np.ndarray[Any, np.dtype[np.float64]]] = []
                    for _ in range(timesteps):
                        target_process.run(
                            condition=RunSteps(num_steps=1),
                            run_cfg=Loihi2SimCfg(),
                        )
                        if pm is not None and hasattr(pm, "v"):
                            h.append(np.asarray(pm.v, dtype=float).copy())
                    _sim_result["voltage_history"] = h

                with concurrent.futures.ThreadPoolExecutor(max_workers=1) as _pool:
                    _future = _pool.submit(_step_loop)
                    try:
                        _future.result(timeout=_timeout_s)
                    except concurrent.futures.TimeoutError as exc:
                        raise LavaDispatchError(
                            f"Lava in-process simulation timed out after "
                            f"{_timeout_s:.0f}s (set NEUROCNL_LAVA_SIM_TIMEOUT_S "
                            "to adjust or unset to disable)"
                        ) from exc
                voltage_history = _sim_result["voltage_history"]
            else:
                voltage_history = []
                for _ in range(timesteps):
                    target_process.run(
                        condition=RunSteps(num_steps=1),
                        run_cfg=Loihi2SimCfg(),
                    )
                    if pm is not None and hasattr(pm, "v"):
                        voltage_history.append(np.asarray(pm.v, dtype=float).copy())

            execution_time_ms = (time.monotonic() - t_start) * 1000.0

            raw = monitor.get_data()
            spikes = _extract_spikes_from_monitor(raw, target_process, target_pop_name)
            voltages = {}
            if voltage_history:
                v_matrix = np.stack(voltage_history, axis=0)
                per_neuron: dict[str, list[float]] = {}
                for n_idx in range(v_matrix.shape[1]):
                    per_neuron[str(n_idx)] = [
                        round(float(v), 5) for v in v_matrix[:, n_idx]
                    ]
                if per_neuron:
                    voltages = {target_pop_name: per_neuron}

            if not spikes:
                # Report silence rather than crashing — and keep the population
                # key so the Studio's Activity tab lands in the same empty state
                # as snnTorch and sc-neurocore, both of which return the name
                # with an empty value. Dropping the key entirely made Lava the
                # only backend that showed "no populations" instead of an empty
                # raster for the same silent run.
                spikes = {target_pop_name: {}}
                warnings = [
                    f"Lava simulator ran {timesteps} timesteps but recorded no spikes "
                    f"in population '{target_pop_name}'. "
                    "Check your stimulus and threshold settings."
                ]
            else:
                warnings = []

        except LavaDispatchError:
            raise
        except Exception as exc:  # noqa: BLE001
            raise LavaDispatchError(f"Lava in-process execution failed: {exc}") from exc
        finally:
            try:
                target_process.stop()
            except Exception:  # noqa: BLE001
                logger.debug("lava_sim: ignoring stop failure", exc_info=True)

        return LavaSimulatorResult(
            spikes=spikes,
            voltages=voltages,
            execution_time_ms=round(execution_time_ms, 3),
            runtime_mode="in_process_lava_sim",
            warnings=warnings,
        )

    # ------------------------------------------------------------------
    # Remote worker path
    # ------------------------------------------------------------------

    def _run_remote(
        self,
        graph: nir.NIRGraph,
        stimulus: ValidatedStimulus,
        timesteps: int,
        worker_url: str,
        seed: int,  # noqa: ARG002 — forwarded for API consistency; remote worker does not yet accept a seed
    ) -> LavaSimulatorResult:
        """Dispatch to a Neurochip Lava worker over HTTP.

        The remote worker exposes the Neurochip ``/api/neurochip/hardware/lava/``
        endpoints.  ``LavaIO.compile_and_run_remote()`` handles the HTTP
        communication.

        The HTTP timeout defaults to 120 s and is configurable via the
        ``NEUROCNL_LAVA_REMOTE_TIMEOUT_S`` environment variable.  Lava's
        actor-model compilation on first use can take 30–90 s; 120 s gives
        enough headroom without requiring a warm-up for every environment.
        """
        # Resolve timeout — default 120 s to absorb Lava's cold-start compilation.
        _timeout_s = 120.0
        _timeout_env = os.environ.get("NEUROCNL_LAVA_REMOTE_TIMEOUT_S")
        if _timeout_env:
            try:
                _timeout_s = float(_timeout_env)
            except ValueError:
                logger.warning(
                    "lava_sim: invalid NEUROCNL_LAVA_REMOTE_TIMEOUT_S=%r, using %.0fs",
                    _timeout_env,
                    _timeout_s,
                )

        output_pop = _infer_output_population(graph)
        t_start = time.monotonic()
        try:
            response = LavaIO().compile_and_run_remote(
                graph,
                base_url=worker_url,
                steps=timesteps,
                run_config="sim",
                timeout=_timeout_s,
                stimulus=stimulus,
            )
        except Exception as exc:  # noqa: BLE001
            raise LavaDispatchError(
                f"Remote Lava worker request failed: {exc}"
            ) from exc

        execution_time_ms = (time.monotonic() - t_start) * 1000.0

        run_response = response.get("run", {})
        raw_spikes: dict[str, list[int]] = run_response.get("spikes", {})
        if run_response.get("execution_time_ms"):
            execution_time_ms = float(run_response["execution_time_ms"])

        # The remote Neurochip LavaBackend returns {str_idx: [timestep, ...]}
        # already keyed by neuron index string — just wrap under the population name.
        spikes = _normalize_flat_spikes(raw_spikes, output_pop)

        warnings: list[str] = []
        if not spikes:
            warnings.append(
                f"Remote Lava worker ran {timesteps} timesteps but returned no spikes "
                f"for population '{output_pop}'."
            )

        # Best-effort voltage extraction from the remote response.
        voltages: dict[str, dict[str, list[float]]] = {}
        try:
            raw_v = run_response.get("voltages")
            if isinstance(raw_v, dict) and raw_v:
                voltages[str(output_pop)] = {
                    str(neuron_idx): [float(v) for v in trace]
                    for neuron_idx, trace in raw_v.items()
                    if isinstance(trace, list) and trace
                }
        except Exception:  # noqa: BLE001
            pass

        return LavaSimulatorResult(
            spikes=spikes,
            voltages=voltages,
            execution_time_ms=round(execution_time_ms, 3),
            runtime_mode="remote_lava_sim_worker",
            warnings=warnings,
        )
