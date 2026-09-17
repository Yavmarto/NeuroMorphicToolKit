"""Lava / Loihi 2 execution backend service."""

from __future__ import annotations

import logging
import time
import uuid
from typing import Any, cast

from ..schemas.estimation import NetworkInput

logger = logging.getLogger(__name__)

try:
    import numpy as np
    from lava.magma.core.run_conditions import RunSteps  # type: ignore[import-not-found]
    from lava.magma.core.run_configs import (  # type: ignore[import-not-found]
        Loihi2HwCfg,
        Loihi2SimCfg,
    )
    from lava.proc.dense.process import Dense  # type: ignore[import-not-found]
    from lava.proc.io.source import RingBuffer  # type: ignore[import-not-found]
    from lava.proc.lif.process import LIF  # type: ignore[import-not-found]
    from lava.proc.monitor.process import Monitor  # type: ignore[import-not-found]

    LAVA_AVAILABLE = True
except ImportError:
    RunSteps = None  # type: ignore[assignment]
    Loihi2HwCfg = None  # type: ignore[assignment]
    Loihi2SimCfg = None  # type: ignore[assignment]
    Dense = None  # type: ignore[assignment]
    RingBuffer = None  # type: ignore[assignment]
    LIF = None  # type: ignore[assignment]
    Monitor = None  # type: ignore[assignment]
    LAVA_AVAILABLE = False
    np = None  # type: ignore[assignment]


class LavaBackendError(RuntimeError):
    """Raised when a Lava backend operation fails."""


class LavaBackend:
    """Service class for managing the Lava process lifecycle."""

    # Fixed spike-buffer length used to size input RingBuffer processes at
    # compile time, before the caller's requested step count is known (it
    # only arrives later, in ``run()``).  Must cover the largest timestep
    # count the API allows for lava_sim (see neurocnl's SimulatorCapability
    # ``max_timesteps=1000``); requests for fewer steps simply read a prefix.
    _INPUT_BUFFER_TIMESTEPS = 1000

    def __init__(self) -> None:
        if not LAVA_AVAILABLE:
            logger.warning("Lava framework is not installed. Operations will fail.")
        self.sessions: dict[str, dict[str, Any]] = {}

    def compile(self, network: NetworkInput, run_config: str = "sim") -> str:
        """Prepare a structured Lava simulator session and return its session id."""
        normalized_run_config = run_config.strip().lower()
        if normalized_run_config == "hw":
            raise LavaBackendError(
                "Hardware preflight failed: Loihi 2 hardware runtime is unavailable in this environment."
            )

        if normalized_run_config != "sim":
            raise LavaBackendError(f"Unsupported Lava run_config {run_config!r}.")

        if not LAVA_AVAILABLE:
            raise LavaBackendError("Lava framework (lava-nc) is not installed.")

        if network.neuron_model.strip().upper() != "LIF":
            raise LavaBackendError(
                f"Unsupported neuron model {network.neuron_model!r}; Lava simulator expects LIF."
            )

        try:
            session_id = str(uuid.uuid4())
            populations = self._build_populations(network)
            population_sizes = {entry["name"]: int(entry["size"]) for entry in populations}
            target_population_name = self._infer_target_population_name(network, populations)

            population_processes: dict[str, Any] = {}
            for population in populations:
                if population.get("role") == "input":
                    spike_matrix = self._build_input_spike_matrix(
                        network.stimulus, population["name"], population["size"]
                    )
                    population_processes[population["name"]] = RingBuffer(data=spike_matrix)
                else:
                    # du/dv arrive already discretized from neurocnl
                    # (lif_semantics.lava_lif_parameters) so the time constant
                    # is honoured here too. Without them this built
                    # LIF(shape, vth) and every population ran with Lava's
                    # default decay -- a different neuron from the one the
                    # network was trained as, and from the one the other
                    # simulators run. Older payloads omit the keys and keep the
                    # previous behaviour.
                    lif_kwargs: dict[str, Any] = {
                        "shape": (population["size"],),
                        "vth": population.get("vth", population["threshold"]),
                    }
                    if population.get("dv") is not None:
                        lif_kwargs["dv"] = population["dv"]
                        lif_kwargs["du"] = population.get("du", 1.0)
                    population_processes[population["name"]] = LIF(**lif_kwargs)

            dense_processes: list[dict[str, Any]] = []
            for connection in network.connections:
                pre_name = str(connection["pre"]).strip()
                post_name = str(connection["post"]).strip()
                source_size = population_sizes[pre_name]
                target_size = population_sizes[post_name]
                weights = self._parse_weights(
                    connection=connection,
                    source_size=source_size,
                    target_size=target_size,
                )
                dense = Dense(weights=weights)
                population_processes[pre_name].s_out.connect(dense.s_in)
                dense.a_out.connect(population_processes[post_name].a_in)
                dense_processes.append(
                    {
                        "pre": pre_name,
                        "post": post_name,
                        "weights": weights,
                        "process": dense,
                    }
                )

            self.sessions[session_id] = {
                "network": network,
                "population_specs": populations,
                "population_processes": population_processes,
                "dense_processes": dense_processes,
                "run_config": normalized_run_config,
                "target_population_name": target_population_name,
                "status": "compiled",
            }
            logger.info(
                "Compiled Lava network for session %s with %d populations and %d connections",
                session_id,
                len(populations),
                len(dense_processes),
            )
            return session_id
        except LavaBackendError:
            raise
        except Exception as exc:  # noqa: BLE001
            logger.exception("Failed to compile Lava network")
            raise LavaBackendError(f"Compilation failed: {exc}") from exc

    def run(self, session_id: str, steps: int = 100) -> dict[str, Any]:
        """Run a compiled simulator session and return structured spike results."""
        if not LAVA_AVAILABLE:
            raise LavaBackendError("Lava framework (lava-nc) is not installed.")

        session = self.sessions.get(session_id)
        if session is None:
            raise LavaBackendError(f"Invalid session ID: {session_id}")

        root_population_name = session["target_population_name"]
        root_process = session["population_processes"][root_population_name]
        monitor = Monitor()
        monitor.probe(root_process.s_out, steps)

        logger.info(
            "Running Lava session %s for %d steps using simulator config",
            session_id,
            steps,
        )
        start_time = time.time()

        try:
            root_process.run(
                condition=RunSteps(num_steps=steps),
                run_cfg=Loihi2SimCfg(),
            )
            execution_time_ms = (time.time() - start_time) * 1000
            raw_spikes = monitor.get_data()
            formatted_spikes = self._format_spikes(
                raw_spikes=raw_spikes,
                population_process=root_process,
            )
            if not formatted_spikes:
                logger.warning(
                    "Lava session %s ran %d steps but recorded no spikes in population %r. "
                    "Check the stimulus and neuron threshold settings.",
                    session_id,
                    steps,
                    root_population_name,
                )

            session["status"] = "ran"
            session["execution_time_ms"] = execution_time_ms
            session["spikes"] = formatted_spikes
            return {
                "status": "success",
                "spikes": formatted_spikes,
                "execution_time_ms": execution_time_ms,
            }
        except LavaBackendError:
            raise
        except Exception as exc:  # noqa: BLE001
            logger.exception("Failed to run Lava network")
            raise LavaBackendError(f"Execution failed: {exc}") from exc
        finally:
            # Lava's runtime is a set of OS processes backed by POSIX shared
            # memory (`/psm_*`). `run()` starts them and only `stop()` releases
            # them, so a run that returned successfully used to leave the whole
            # runtime resident: callers reach `/compile` and `/run` but never
            # `/stop`, so every successful simulation leaked processes and shm
            # handles until the worker hit its descriptor limit. After that even
            # a two-neuron network failed with
            # "[Errno 24] Too many open files: '/psm_...'" until the container
            # was restarted. Stopping here is safe because the spikes have
            # already been collected, and `stop()` below tolerates an
            # already-stopped process.
            try:
                root_process.stop()
            except Exception:  # noqa: BLE001
                logger.debug("Ignoring Lava process stop failure", exc_info=True)

    def stop(self, session_id: str) -> None:
        """Terminate execution and clean up resources."""
        if not LAVA_AVAILABLE:
            raise LavaBackendError("Lava framework (lava-nc) is not installed.")

        session = self.sessions.pop(session_id, None)
        if session is None:
            raise LavaBackendError(f"Invalid session ID: {session_id}")

        for process in session["population_processes"].values():
            try:
                process.stop()
            except Exception:  # noqa: BLE001
                logger.debug("Ignoring stop failure for Lava process", exc_info=True)

    def _build_populations(self, network: NetworkInput) -> list[dict[str, Any]]:
        populations: list[dict[str, Any]] = []
        for index, raw_population in enumerate(network.populations):
            name = str(raw_population.get("name") or f"pop_{index}").strip()
            size = int(raw_population.get("size") or 1)
            threshold = float(raw_population.get("threshold") or 1.0)
            role = str(raw_population.get("role") or "hidden")
            entry: dict[str, Any] = {
                "name": name,
                "size": size,
                "threshold": threshold,
                "role": role,
            }
            # Optional Lava terms resolved upstream. Carried through verbatim
            # rather than re-derived: the discretization lives in neurocnl and
            # a second copy here would drift.
            for key in ("du", "dv", "vth"):
                value = raw_population.get(key)
                if value is not None:
                    entry[key] = float(value)
            populations.append(entry)

        if not populations:
            raise LavaBackendError("Compilation failed: network payload contains no populations.")

        return populations

    def _build_input_spike_matrix(
        self,
        stimulus: dict[str, Any] | None,
        population_name: str,
        size: int,
    ) -> Any:
        """Build a dense (neurons, timesteps) binary spike matrix for a RingBuffer.

        Returns an all-zero matrix (silent input) when *stimulus* is absent or
        does not target *population_name*.
        """
        matrix = np.zeros((size, self._INPUT_BUFFER_TIMESTEPS), dtype=int)
        if not stimulus:
            return matrix
        if str(stimulus.get("population")) != population_name:
            return matrix
        raw_spikes = stimulus.get("spikes") or {}
        for idx_str, times in raw_spikes.items():
            try:
                idx = int(idx_str)
            except (TypeError, ValueError):
                continue
            if not (0 <= idx < size):
                continue
            for t in times:
                if isinstance(t, int) and 0 <= t < self._INPUT_BUFFER_TIMESTEPS:
                    matrix[idx, t] = 1
        return matrix

    def _infer_target_population_name(
        self,
        network: NetworkInput,
        populations: list[dict[str, Any]],
    ) -> str:
        if network.connections:
            candidate = network.connections[-1].get("post")
            if isinstance(candidate, str) and candidate.strip():
                return candidate.strip()
        return cast(str, populations[-1]["name"])

    def _parse_weights(
        self,
        *,
        connection: dict[str, Any],
        source_size: int,
        target_size: int,
    ) -> Any:
        weights = connection.get("weights")
        if weights is None:
            scalar_weight = 1.0
            return np.full((target_size, source_size), scalar_weight, dtype=float)

        matrix = np.asarray(weights, dtype=float)
        expected_shape = (target_size, source_size)
        if matrix.shape != expected_shape:
            raise LavaBackendError(
                "Compilation failed: connection "
                f"{connection.get('pre')!r} -> {connection.get('post')!r} expected "
                f"weight shape {expected_shape}, got {matrix.shape}."
            )
        return matrix

    def _format_spikes(
        self,
        *,
        raw_spikes: Any,
        population_process: Any,
    ) -> dict[str, list[int]]:
        formatted: dict[str, list[int]] = {}
        if not isinstance(raw_spikes, dict):
            return formatted

        process_name = getattr(population_process, "name", "")
        port_data = raw_spikes.get(process_name)
        if not isinstance(port_data, dict):
            port_data = None

        spike_array = port_data.get("s_out") if isinstance(port_data, dict) else None
        if spike_array is None:
            for candidate in raw_spikes.values():
                if isinstance(candidate, dict) and candidate.get("s_out") is not None:
                    spike_array = candidate["s_out"]
                    break
        if spike_array is None:
            return formatted

        spike_matrix = np.asarray(spike_array)
        if spike_matrix.ndim == 1:
            spike_matrix = spike_matrix.reshape(-1, 1)
        if spike_matrix.ndim != 2:
            return formatted

        for neuron_index in range(spike_matrix.shape[1]):
            spike_times = np.nonzero(spike_matrix[:, neuron_index])[0].tolist()
            if spike_times:
                formatted[str(neuron_index)] = spike_times
        return formatted
