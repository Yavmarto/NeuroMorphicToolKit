"""Mount Neurosense domain routes in suite_api.

Data-processing routes (presets, encoding, recording, sessions, export, nir, quality)
are served in-process by suite_api.

Hardware routes (devices, stream, prophesee, pynq) are proxied to the
neurosense-hw-worker (port 8004, Docker profile: hardware). When the worker
is not running, those routes return HTTP 503.

WebSocket stream routes (/api/neurosense/stream/*) are served directly by
the worker — WebSocket connections should target port 8004 when the hardware
profile is active.
"""
import logging
from typing import Any

from fastapi import APIRouter, Request
from fastapi.responses import Response

from neurosense.app.routers import (
    encoding,
    export,
    nir,
    presets,
    quality,
    recording,
    sessions,
)

from suite_api.config import settings
from suite_api.proxy import proxy_to_worker

logger = logging.getLogger("suite_api.neurosense")

router = APIRouter()

# ── In-process: data-processing routes (no hardware needed) ──────────────────
router.include_router(presets.router,   prefix="/api/neurosense/presets")
router.include_router(encoding.router,  prefix="/api/neurosense/encode")
router.include_router(recording.router, prefix="/api/neurosense/recording")
router.include_router(sessions.router,  prefix="/api/neurosense/sessions")
router.include_router(quality.router,   prefix="/api/neurosense/quality")
router.include_router(export.router,    prefix="/api/neurosense/export")
router.include_router(nir.router,       prefix="/api/neurosense/nir")


# ── Proxied: hardware I/O routes → neurosense-hw-worker (port 8004) ──────────
# These routes return 503 when the hardware worker is not running.

@router.api_route(
    "/api/neurosense/devices",
    methods=["GET", "POST", "DELETE", "PUT", "PATCH"],
)
async def proxy_neurosense_devices_root(request: Request) -> Response:
    return await proxy_to_worker(request, settings.neurosense_hw_worker_url)


@router.api_route(
    "/api/neurosense/devices/{path:path}",
    methods=["GET", "POST", "DELETE", "PUT", "PATCH"],
)
async def proxy_neurosense_devices(request: Request, path: str) -> Response:
    return await proxy_to_worker(request, settings.neurosense_hw_worker_url)


@router.api_route(
    "/api/neurosense/stream/{path:path}",
    methods=["GET", "POST"],
)
async def proxy_neurosense_stream(request: Request, path: str) -> Response:
    """HTTP proxy for stream control. WebSocket connections go directly to port 8004."""
    return await proxy_to_worker(request, settings.neurosense_hw_worker_url)


@router.api_route(
    "/api/neurosense/sense/{path:path}",
    methods=["GET", "POST", "DELETE", "PUT", "PATCH"],
)
async def proxy_neurosense_sense(request: Request, path: str) -> Response:
    """Proxy prophesee and pynq sense routes to the hardware worker."""
    return await proxy_to_worker(request, settings.neurosense_hw_worker_url)


@router.get("/api/neurosense/health")
async def neurosense_health() -> dict[str, Any]:
    """Health check for the Neurosense domain (in-process data-processing routes)."""
    return {
        "status": "ok",
        "service": "neurosense",
        "hardware_worker": settings.neurosense_hw_worker_url,
        "note": "Hardware routes (devices/stream/sense) proxied to hardware worker",
    }
