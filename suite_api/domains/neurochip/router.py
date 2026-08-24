"""Mount Neurochip domain routes in suite_api.

Non-hardware analysis routes (targets, analysis, quantization, faults,
estimation, export, spinnaker2, deployments) are served in-process.

Hardware routes (akida, lava, speck, pynq, serial) are proxied to the
neurochip-hw-worker (port 8002, Docker profile: hardware). When the worker
is not running, those routes return HTTP 503.

Suite_api starts cleanly on machines without Akida/PYNQ/Lava/Speck installed
(the hardware routes simply 503 when the worker is not running).
"""

import logging
import importlib
from typing import Any

from fastapi import APIRouter, Request
from fastapi.responses import Response

from neurochip.app.routers import (
    analysis,
    deployments,
    estimation,
    export,
    faults,
    quantization,
    targets,
)

from suite_api.config import settings
from suite_api.proxy import proxy_to_worker

logger = logging.getLogger("suite_api.neurochip")

# Optional in-process: spinnaker2 (software simulation, not hardware)
_spinnaker2_router = None
try:
    _spinnaker2_mod = importlib.import_module("neurochip.app.routers.spinnaker2")
    _spinnaker2_router = _spinnaker2_mod.router
except ImportError as exc:
    logger.warning("neurochip: spinnaker2 router unavailable: %s", exc)

# Neurochip routers already contain their full prefix
router = APIRouter()

# ── In-process: non-hardware routes ──────────────────────────────────────────
for _r in [
    targets.router,
    analysis.router,
    quantization.router,
    faults.router,
    estimation.router,
    export.router,
    deployments.router,
]:
    router.include_router(_r)

if _spinnaker2_router is not None:
    router.include_router(_spinnaker2_router)


# ── Proxied: hardware routes → neurochip-hw-worker (port 8002) ───────────────
# These routes return 503 when the hardware worker is not running.

for prefix in [
    "/api/neurochip/akida/{path:path}",
    "/api/neurochip/hardware/lava/{path:path}",
    "/api/neurochip/hardware/speck/{path:path}",
    "/hardware/pynq/{path:path}",
    "/api/neurochip/serial/{path:path}",
]:

    @router.api_route(
        prefix,
        methods=["GET", "POST", "DELETE", "PUT", "PATCH"],
    )
    async def _hw_proxy(request: Request, path: str) -> Response:
        extra_headers = (
            {"X-API-Key": settings.neurochip_hw_worker_api_key}
            if settings.neurochip_hw_worker_api_key
            else None
        )
        return await proxy_to_worker(
            request, settings.neurochip_hw_worker_url, extra_headers=extra_headers
        )


@router.get("/api/neurochip/health")
async def neurochip_health() -> dict[str, Any]:
    """Health check for the Neurochip domain."""
    return {
        "status": "healthy",
        "service": "neurochip",
        "hardware_worker": settings.neurochip_hw_worker_url,
        "note": "Hardware routes (akida/lava/speck/pynq/serial) proxied to hardware worker",
    }
