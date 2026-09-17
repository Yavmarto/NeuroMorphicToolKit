"""Isolated Brian2 runtime backend used by the worker container."""

from __future__ import annotations

import time
import uuid
from typing import Any

import numpy as np

try:
    import brian2 as b2

    BRIAN2_AVAILABLE = True
except ImportError:  # pragma: no cover - exercised in worker environments without Brian2
    b2 = None
    BRIAN2_AVAILABLE = False


class Brian2BackendError(RuntimeError):
    """Raised when the isolated Brian2 backend cannot complete a request."""


class Brian2Backend:
    """Compile and run simple LIF network payloads inside the Brian2 container."""

    def __init__(self) -> None:
        self.sessions: dict[str, dict[str, Any]] = {}

    def compile(self, network: dict[str, Any]) -> str:
        """Normalize a worker payload and return a reusable session id."""
        if not BRIAN2_AVAILABLE:
            raise Brian2BackendError("Brian2 is not installed in this runtime.")

        if str(network.get("neuron_model", "")).strip().upper() != "LIF":
            raise Brian2BackendError(
                "Unsupported neuron model "
                f"{network.get('neuron_model')!r}; Brian2 worker expects LIF."
            )

        session_id = str(uuid.uuid4())
        self.sessions[session_id] = self._normalize_network(network)
        return session_id

    def run(self, session_id: str, steps: int = 100) -> dict[str, Any]:
        """Run a previously compiled session and return formatted spike results."""
        if not BRIAN2_AVAILABLE:
            raise Brian2BackendError("Brian2 is not installed in this runtime.")

        session = self.sessions.get(session_id)
        if session is None:
            raise Brian2BackendError(f"Invalid session ID: {session_id}")

        start_time = time.time()
        spikes = self._run_session(session, steps)
        execution_time_ms = (time.time() - start_time) * 1000
        return {
            "status": "success",
            "spikes": spikes,
            "execution_time_ms": execution_time_ms,
        }

    def stop(self, session_id: str) -> None:
        """Discard a compiled session."""
        session = self.sessions.pop(session_id, None)
        if session is None:
            raise Brian2BackendError(f"Invalid session ID: {session_id}")

    def _normalize_network(self, network: dict[str, Any]) -> dict[str, Any]:
        populations: list[dict[str, Any]] = []
        population_sizes: dict[str, int] = {}
        for index, raw_population in enumerate(network.get("populations", [])):
            name = str(raw_population.get("name") or f"pop_{index}").strip()
            size = int(raw_population.get("size") or 1)
            threshold = float(raw_population.get("threshold") or 1.0)
            tau_rc = float(raw_population.get("tau_rc") or 0.02)
            populations.append(
                {
                    "name": name,
                    "size": size,
                    "threshold": threshold,
                    "tau_rc": tau_rc,
                }
            )
            population_sizes[name] = size

        if not populations:
            raise Brian2BackendError("Compilation failed: network payload contains no populations.")

        connections: list[dict[str, Any]] = []
        for raw_connection in network.get("connections", []):
            pre_name = str(raw_connection.get("pre") or "").strip()
            post_name = str(raw_connection.get("post") or "").strip()
            if pre_name not in population_sizes or post_name not in population_sizes:
                raise Brian2BackendError(
                    "Compilation failed: unknown connection endpoints "
                    f"{pre_name!r} -> {post_name!r}."
                )
            source_size = population_sizes[pre_name]
            target_size = population_sizes[post_name]
            weights = np.asarray(raw_connection.get("weights"), dtype=float)
            expected_shape = (target_size, source_size)
            if weights.shape != expected_shape:
                raise Brian2BackendError(
                    "Compilation failed: connection "
                    f"{pre_name!r} -> {post_name!r} expected weight shape {expected_shape}, "
                    f"got {weights.shape}."
                )
            connections.append(
                {
                    "pre": pre_name,
                    "post": post_name,
                    "weights": weights,
                }
            )

        return {
            "populations": populations,
            "connections": connections,
            "target_population_name": populations[-1]["name"],
        }

    def _run_session(self, session: dict[str, Any], steps: int) -> dict[str, list[int]]:
        assert b2 is not None
        b2.start_scope()
        b2.defaultclock.dt = 1.0 * b2.ms

        network = b2.Network()
        groups: dict[str, Any] = {}
        monitors: dict[str, Any] = {}

        equations = """
        dv/dt = -v / tau : 1
        tau : second
        threshold_value : 1
        """

        for population in session["populations"]:
            group = b2.NeuronGroup(
                population["size"],
                model=equations,
                threshold="v > threshold_value",
                reset="v = 0",
                method="exact",
                name=population["name"],
            )
            group.v = 0
            group.tau = population["tau_rc"] * b2.second
            group.threshold_value = population["threshold"]
            groups[population["name"]] = group
            monitor = b2.SpikeMonitor(group)
            monitors[population["name"]] = monitor
            network.add(group, monitor)

        for connection in session["connections"]:
            synapses = b2.Synapses(
                groups[connection["pre"]],
                groups[connection["post"]],
                model="w : 1",
                on_pre="v_post += w",
            )
            weights = connection["weights"]
            pre_indices: list[int] = []
            post_indices: list[int] = []
            weight_values: list[float] = []
            for post_index in range(weights.shape[0]):
                for pre_index in range(weights.shape[1]):
                    pre_indices.append(pre_index)
                    post_indices.append(post_index)
                    weight_values.append(float(weights[post_index, pre_index]))
            synapses.connect(i=pre_indices, j=post_indices)
            synapses.w = weight_values
            network.add(synapses)

        network.run(max(int(steps), 1) * b2.ms)
        target_monitor = monitors[session["target_population_name"]]
        formatted: dict[str, list[int]] = {}
        for neuron_index, spike_time in zip(target_monitor.i, target_monitor.t, strict=False):
            formatted.setdefault(str(int(neuron_index)), []).append(
                int(round(float(spike_time / b2.ms)))
            )
        return formatted
