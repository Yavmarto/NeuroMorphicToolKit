"""Notebook helper for the lava-backend worker (port 8012).

Usage::

    from nmtk_client import lava

    session = lava.compile(
        populations=[{"name": "pop_a", "size": 10, "threshold": 1.0}],
        connections=[{"src": "pop_a", "dst": "pop_a", "weight": 0.2}],
    )
    results = lava.run(session, steps=100)
    print(results["spikes"])
    lava.stop(session)

The lava-backend URL is read from the ``LAVA_BACKEND_URL`` environment
variable (default: ``http://lava-backend:8012``).  The first compile after
container start may take 30-90 s while Lava JIT-compiles its actor models;
subsequent calls are fast.
"""
from __future__ import annotations

from ._base import NmtkServiceClient

_client = NmtkServiceClient(
    env_var="LAVA_BACKEND_URL",
    service_name="lava-backend",
    default_url="http://lava-backend:8012",
)


def health() -> dict:
    """Return the lava-backend health response."""
    return _client._get("/health")


def compile(
    populations: list[dict],
    connections: list[dict],
    *,
    neuron_model: str = "LIF",
    weight_bit_width: int = 8,
    network_depth: int = 1,
    run_config: str = "sim",
) -> str:
    """Compile a network and return a session ID.

    Args:
        populations:     List of population dicts, each with ``name``, ``size``,
                         and ``threshold`` keys.
        connections:     List of connection dicts, each with ``src``, ``dst``,
                         and ``weight`` keys.
        neuron_model:    Lava neuron model name (default: ``"LIF"``).
        weight_bit_width: Synapse weight precision in bits (default: 8).
        network_depth:   Number of processing layers (default: 1).
        run_config:      ``"sim"`` for software emulation (no chip needed) or
                         ``"hw"`` for real Loihi 2 hardware (returns 503 if absent).

    Returns:
        A session ID string to pass to :func:`run` and :func:`stop`.
    """
    result = _client._post(
        "/api/neurochip/hardware/lava/compile",
        json={
            "network": {
                "num_neurons": sum(p.get("size", 0) for p in populations),
                "num_synapses": len(connections),
                "neuron_model": neuron_model,
                "populations": populations,
                "connections": connections,
                "weight_bit_width": weight_bit_width,
                "network_depth": network_depth,
            },
            "run_config": run_config,
        },
    )
    return result["session_id"]


def run(session_id: str, steps: int = 100) -> dict:
    """Run a compiled session and return the results.

    Args:
        session_id: Session ID returned by :func:`compile`.
        steps:      Number of simulation timesteps (default: 100).

    Returns:
        Dict with keys ``status``, ``spikes`` (population name → spike list),
        ``voltages``, ``emulation``, and ``execution_time_ms``.
    """
    return _client._post(
        "/api/neurochip/hardware/lava/run",
        json={"session_id": session_id, "steps": steps},
    )


def stop(session_id: str) -> None:
    """Stop and release a compiled session."""
    _client._post(
        "/api/neurochip/hardware/lava/stop",
        json={"session_id": session_id},
    )
