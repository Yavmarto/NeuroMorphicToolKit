"""Mount neurocnl domain routes in suite_api.

Standard CNL routes (parse, validate, generate, simulate, export, deploy,
jobs, templates, neurosim_handoff) are served in-process.

Non-MuJoCo prosthetic routes (sleep, export/crossbar, energy, quantize,
fault-injection, hardware) are served in-process.

The prosthetic/simulate route requires MuJoCo and is proxied to the
neurocnl-physics-worker (port 8006). When the physics worker is not running,
/api/neurocnl/prosthetic/simulate returns 503.
"""

import logging
import shutil
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

from fastapi import APIRouter, Request
from fastapi.responses import Response

import neurocnl
from suite_api.config import settings
from suite_api.proxy import proxy_to_worker

# Ensure neurocnl/backend is importable before importing its top-level
# ``backend`` package. Keep this side-effect import block in this order.
# isort: off
import suite_api.domains.neurocnl  # noqa: F401

from backend.app.routers import (
    datasets,
    deploy,
    export,
    generate,
    jobs,
    kernel_runner,
    neurosim_handoff,
    nir_inspect,
    notebook,
    parse,
    simulate,
    simulators,
    templates,
    training,
    validate,
    workspaces,
)
from backend.app.routers.prosthetic import (
    analysis as prosthetic_analysis,
    export as prosthetic_export,
    sleep as prosthetic_sleep,
)
# isort: on

logger = logging.getLogger("suite_api.neurocnl")

# Hardware serial port router — optional, requires physical device
try:
    from backend.app.routers.prosthetic import hardware as prosthetic_hardware

    _has_prosthetic_hw = True
except ImportError as exc:
    logger.warning("neurocnl: prosthetic hardware router unavailable: %s", exc)
    _has_prosthetic_hw = False

router = APIRouter(prefix="/api/neurocnl")


@router.get("/health")
def neurocnl_health() -> dict[str, Any]:
    """Health check for the neurocnl domain."""
    disk = shutil.disk_usage(Path.cwd())
    return {
        "status": "ok",
        # mypy resolves this import as the top-level "neurocnl" submodule
        # checkout (a namespace package) rather than the installed
        # neurocnl/neurocnl package, so __version__ looks missing statically
        # even though it exists at runtime.
        "neurocnl_version": neurocnl.__version__,  # type: ignore[attr-defined]
        "timestamp": datetime.now(UTC).isoformat(),
        "modules": {},
        "physics_worker": "configured",
        "disk": {
            "total_gb": round(disk.total / (1024**3), 2),
            "used_gb": round((disk.total - disk.free) / (1024**3), 2),
            "free_gb": round(disk.free / (1024**3), 2),
            "low_space": round(disk.free / (1024**3), 2) < 5,
        },
    }


# ── In-process: standard CNL routes ──────────────────────────────────────────
for _r in [
    parse.router,
    validate.router,
    generate.router,
    simulate.router,
    simulators.router,
    datasets.router,
    export.router,
    deploy.router,
    jobs.router,
    neurosim_handoff.router,
    notebook.router,
    kernel_runner.router,
    templates.router,
    training.router,
    nir_inspect.router,
    workspaces.router,
]:
    router.include_router(_r)

# ── In-process: non-MuJoCo prosthetic routes ─────────────────────────────────
for _r in [
    prosthetic_sleep.router,
    prosthetic_export.router,
    prosthetic_analysis.router,
]:
    router.include_router(_r, prefix="/prosthetic")

if _has_prosthetic_hw:
    router.include_router(prosthetic_hardware.router, prefix="/prosthetic")


# ── Proxied: MuJoCo prosthetic/simulate → neurocnl-physics-worker (port 8006) ─
# Returns 503 when the physics worker is not running (MuJoCo not available).


async def _proxy_neurocnl_prosthetic_simulate(request: Request) -> Response:
    """Proxy MuJoCo physics simulation to the physics worker.

    Returns 503 if the physics worker (MuJoCo) is not running.
    """
    return await proxy_to_worker(
        request,
        settings.neurocnl_physics_worker_url,
    )


@router.get("/prosthetic/simulate")
async def get_neurocnl_prosthetic_simulate(request: Request) -> Response:
    """Proxy a compatibility GET simulation request to the physics worker."""
    return await _proxy_neurocnl_prosthetic_simulate(request)


@router.post("/prosthetic/simulate")
async def post_neurocnl_prosthetic_simulate(request: Request) -> Response:
    """Proxy a simulation request to the physics worker."""
    return await _proxy_neurocnl_prosthetic_simulate(request)
