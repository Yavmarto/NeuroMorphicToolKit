"""Brian2 simulator adapter for the shared CNL → NIR → Simulator contract.

Dispatches through :class:`neurocnl.converter.brian2_io.Brian2IO` and the
isolated :class:`neurocnl.converter.brian2_runtime.Brian2Backend` worker when
``NEUROCNL_BRIAN2_WORKER_URL`` is set, or in-process when ``brian2`` is
importable locally.
"""

from __future__ import annotations

import importlib.util
import logging
import os
import time
from dataclasses import dataclass, field
from typing import Any

import nir

from neurocnl.converter.brian2_io import Brian2IO
from neurocnl.converter.brian2_runtime import Brian2Backend, Brian2BackendError
from neurocnl.runtime.lava_simulator import (
    _infer_output_population,
    _normalize_flat_spikes,
)
from neurocnl.runtime.stimulus import ValidatedStimulus

logger = logging.getLogger(__name__)


@dataclass(slots=True)
class Brian2SimulatorResult:
    spikes: dict[str, dict[str, list[int]]] = field(default_factory=dict)
    voltages: dict[str, dict[str, list[float]]] = field(default_factory=dict)
    execution_time_ms: float = 0.0
    runtime_mode: str = "unknown"
    warnings: list[str] = field(default_factory=list)


class Brian2DispatchError(RuntimeError):
    def __init__(self, *diagnostics: str) -> None:
        self.diagnostics: list[str] = list(diagnostics)
        super().__init__("; ".join(diagnostics))


def _is_brian2_available() -> bool:
    return importlib.util.find_spec("brian2") is not None


class Brian2SimulatorAdapter:
    """Run a compiled NIR graph through Brian2."""

    def run(
        self,
        graph: nir.NIRGraph,
        stimulus: ValidatedStimulus,
        timesteps: int,
        seed: int,  # noqa: ARG002 — reserved for API parity; Brian2 path is deterministic
        *,
        worker_url: str | None = None,
    ) -> Brian2SimulatorResult:
        try:
            if _is_brian2_available():
                logger.info("brian2_sim: dispatching in-process")
                return self._run_in_process(graph, timesteps)
            if worker_url:
                logger.info(
                    "brian2_sim: dispatching via remote worker at %s", worker_url
                )
                return self._run_remote(graph, timesteps, worker_url)
            raise Brian2DispatchError(
                "Brian2 simulator is not available: brian2 is not installed and "
                "NEUROCNL_BRIAN2_WORKER_URL is not set."
            )
        except Brian2DispatchError:
            raise
        except Exception as exc:  # noqa: BLE001
            logger.exception(
                "brian2_sim: unexpected exception in run() [%s]", type(exc).__name__
            )
            raise Brian2DispatchError(f"Brian2 simulation failed: {exc}") from exc

    def _run_in_process(
        self, graph: nir.NIRGraph, timesteps: int
    ) -> Brian2SimulatorResult:
        output_pop = _infer_output_population(graph)
        t_start = time.monotonic()
        try:
            backend = Brian2Backend()
            session_id = backend.compile(Brian2IO().to_runtime_payload(graph))
            run_response = backend.run(session_id, steps=timesteps)
        except Brian2BackendError as exc:
            raise Brian2DispatchError(str(exc)) from exc

        execution_time_ms = float(run_response.get("execution_time_ms") or 0.0)
        if not execution_time_ms:
            execution_time_ms = (time.monotonic() - t_start) * 1000.0

        raw_spikes: dict[str, list[int]] = run_response.get("spikes", {})
        spikes = _normalize_flat_spikes(raw_spikes, output_pop)
        warnings: list[str] = []
        if not spikes:
            warnings.append(
                f"Brian2 ran {timesteps} timesteps but returned no spikes for '{output_pop}'."
            )
        return Brian2SimulatorResult(
            spikes=spikes,
            execution_time_ms=round(execution_time_ms, 3),
            runtime_mode="in_process_brian2_sim",
            warnings=warnings,
        )

    def _run_remote(
        self,
        graph: nir.NIRGraph,
        timesteps: int,
        worker_url: str,
    ) -> Brian2SimulatorResult:
        output_pop = _infer_output_population(graph)
        timeout_s = 60.0
        timeout_env = os.environ.get("NEUROCNL_BRIAN2_REMOTE_TIMEOUT_S")
        if timeout_env:
            try:
                timeout_s = float(timeout_env)
            except ValueError:
                logger.warning(
                    "brian2_sim: invalid NEUROCNL_BRIAN2_REMOTE_TIMEOUT_S=%r, using %.0fs",
                    timeout_env,
                    timeout_s,
                )

        t_start = time.monotonic()
        try:
            response = Brian2IO().compile_and_run_remote(
                graph,
                base_url=worker_url,
                steps=timesteps,
                timeout=timeout_s,
            )
        except Exception as exc:  # noqa: BLE001
            raise Brian2DispatchError(
                f"Remote Brian2 worker request failed: {exc}"
            ) from exc

        execution_time_ms = (time.monotonic() - t_start) * 1000.0
        run_response: dict[str, Any] = response.get("run", {})
        raw_spikes: dict[str, list[int]] = run_response.get("spikes", {})
        if run_response.get("execution_time_ms"):
            execution_time_ms = float(run_response["execution_time_ms"])

        spikes = _normalize_flat_spikes(raw_spikes, output_pop)
        warnings: list[str] = []
        if not spikes:
            warnings.append(
                f"Remote Brian2 worker ran {timesteps} timesteps but returned no spikes "
                f"for population '{output_pop}'."
            )
        return Brian2SimulatorResult(
            spikes=spikes,
            execution_time_ms=round(execution_time_ms, 3),
            runtime_mode="remote_brian2_sim_worker",
            warnings=warnings,
        )
