"""neurocnl physics worker — MuJoCo + Nengo co-simulation.

Serves the prosthetic/simulate route which requires MuJoCo.
Started only when MuJoCo is installed (docker profile: physics).

Default port: 8006 (existing neurocnl-physics port).
Start with: uvicorn workers.neurocnl_physics.main:app --port 8006

Suite_api routes /api/neurocnl/prosthetic/simulate here when the physics
worker is running; returns 503 when it is not.
"""

import logging
import sys
from collections.abc import AsyncGenerator
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Any

from fastapi import FastAPI

# Make neurocnl/backend importable
_BACKEND_PATH = Path(__file__).parents[2] / "neurocnl"
if str(_BACKEND_PATH) not in sys.path:
    sys.path.insert(0, str(_BACKEND_PATH))

from nmtk.http_metrics import attach_fastapi_metrics

logger = logging.getLogger("neurocnl_physics_worker")


@asynccontextmanager
async def lifespan(_app: FastAPI) -> AsyncGenerator[None, None]:
    # job_store's sqlite tables are created lazily by initialize(); the main
    # neurocnl backend does this in its own lifespan, but this worker runs
    # as a separate process/DB and was never wired up to do the same, so
    # every submit() hit "no such table: jobs".
    from backend.app.services.job_store import job_store

    await job_store.initialize()
    yield


app = FastAPI(
    title="neurocnl Physics Worker",
    version="0.1.0",
    description="MuJoCo physics co-simulation worker. Profile: physics.",
    lifespan=lifespan,
)
attach_fastapi_metrics(app)

# Mount the prosthetic simulate router (the only one that needs MuJoCo)
try:
    from backend.app.routers.prosthetic import simulate as prosthetic_sim

    app.include_router(prosthetic_sim.router, prefix="/api/neurocnl/prosthetic")
    logger.info("neurocnl_physics: prosthetic simulate router loaded")
except ImportError as exc:
    logger.error(
        "neurocnl_physics: prosthetic simulate router failed to load: %s. "
        "Install MuJoCo with: pip install mujoco",
        exc,
    )


@app.get("/health")
async def health() -> dict[str, Any]:
    """Health check — also verifies MuJoCo is importable."""
    try:
        import mujoco  # type: ignore[import-untyped]

        mujoco_version = getattr(mujoco, "__version__", "unknown")
        mujoco_ok = True
    except ImportError:
        mujoco_version = None
        mujoco_ok = False

    return {
        "status": "ok" if mujoco_ok else "degraded",
        "service": "neurocnl-physics-worker",
        "mujoco_available": mujoco_ok,
        "mujoco_version": mujoco_version,
    }
