"""Dedicated Lava runtime worker.

This isolates the Python 3.10 + lava-nc runtime from the main Neurochip
service while preserving the existing Neurochip Lava HTTP contract.

Background warm-up
------------------
Lava-nc compiles its actor-model implementations on the first call to
``root_process.run()``.  That compilation can take 30–90 seconds, which
previously caused the first client request to time out.

The warm-up is intentionally started **after** the lifespan ``yield`` so
that the ``/health`` endpoint is reachable immediately after container start.
This keeps the Docker health check happy and satisfies ``depends_on:
service_healthy`` constraints in docker-compose.yml, while still pre-warming
the Lava runtime in the background before the first real simulation request
typically arrives.

If warm-up fails (e.g. lava-nc not installed, or a multiprocessing issue in
the container) it is caught and logged as a warning.  The worker continues
running; the first real request will pay the cold-start cost instead.
"""

from __future__ import annotations

import asyncio
import logging
from collections.abc import AsyncGenerator
from contextlib import asynccontextmanager

from fastapi import FastAPI
from neurochip.app.routers import lava

logger = logging.getLogger(__name__)


def _run_lava_warmup() -> None:
    """Run a minimal Lava simulation to pre-compile actor-model implementations.

    Blocking — must be called inside ``asyncio.to_thread``.
    """
    try:
        from neurochip.app.schemas.estimation import NetworkInput
        from neurochip.app.services.lava_backend import LavaBackend

        backend = LavaBackend()
        network = NetworkInput(
            num_neurons=1,
            num_synapses=0,
            neuron_model="LIF",
            populations=[{"name": "warmup", "size": 1, "threshold": 1.0}],
            connections=[],
            weight_bit_width=8,
            network_depth=1,
        )
        session_id = backend.compile(network, run_config="sim")
        backend.run(session_id=session_id, steps=10)
        logger.info("lava-backend: background warm-up complete — Lava actor models compiled")
    except Exception as exc:  # noqa: BLE001
        logger.warning(
            "lava-backend: background warm-up failed (non-fatal, first request will be slow): %s",
            exc,
        )


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncGenerator[None, None]:
    # Yield FIRST so /health is reachable immediately and Docker health checks pass.
    # The warm-up runs in the background after the app starts accepting requests.
    _warmup_task: asyncio.Task[None] = asyncio.create_task(
        asyncio.to_thread(_run_lava_warmup)
    )
    logger.info("lava-backend: background Lava warm-up started (may take 30–90 s)")
    yield
    # Clean up if still running at shutdown.
    if not _warmup_task.done():
        _warmup_task.cancel()
        try:
            await _warmup_task
        except (asyncio.CancelledError, Exception):  # noqa: BLE001, S110
            pass


app = FastAPI(
    title="Lava Backend Worker",
    version="0.1.0",
    description="Isolated Lava simulator worker for Neurochip runtime requests.",
    lifespan=lifespan,
)
app.include_router(lava.router)


@app.get("/health")
async def health() -> dict[str, object]:
    lava_importable = False
    try:
        import importlib.util

        lava_importable = importlib.util.find_spec("lava") is not None
    except (ImportError, ValueError):
        lava_importable = False
    return {
        "status": "ok",
        "service": "lava-backend",
        "lava_importable": lava_importable,
    }
