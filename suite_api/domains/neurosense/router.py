"""Mount Neurosense domain routes in suite_api.

Data-processing routes (presets, encoding, NIR, quality) are served in-process.
Recording lifecycle, stream capture, sessions, and exports share one worker.

Hardware routes (devices, stream, prophesee, pynq) are proxied to the
neurosense-hw-worker (port 8004, Docker profile: hardware). When the worker
is not running, those routes return HTTP 503.

WebSocket stream routes are bridged through Suite API so the worker stays
unpublished.
"""

import logging
from typing import Any

from fastapi import APIRouter, Request, WebSocket
from fastapi.responses import Response

from neurosense.app.routers import (
    encoding,
    nir,
    presets,
    quality,
)
from suite_api.config import settings
from suite_api.middleware import admin_token_valid
from suite_api.proxy import proxy_to_worker, proxy_websocket_to_worker

logger = logging.getLogger("suite_api.neurosense")

router = APIRouter()

# ── In-process: data-processing routes (no hardware needed) ──────────────────
router.include_router(presets.router, prefix="/api/neurosense/presets")
router.include_router(encoding.router, prefix="/api/neurosense/encode")
router.include_router(quality.router, prefix="/api/neurosense/quality")
router.include_router(nir.router, prefix="/api/neurosense/nir")


def _owned_route_proxy(segment: str) -> Any:
    async def endpoint(request: Request, path: str = "") -> Response:
        return await proxy_to_worker(
            request,
            settings.neurosense_hw_worker_url,
            target_path=f"/api/neurosense/{segment}/{path}".rstrip("/"),
        )

    return endpoint


for _owned_path in ("recording", "sessions", "export"):
    _methods = ["GET", "POST", "DELETE", "PUT", "PATCH"]
    router.add_api_route(
        f"/api/neurosense/{_owned_path}",
        _owned_route_proxy(_owned_path),
        methods=_methods,
        name=f"proxy_neurosense_{_owned_path}_root",
    )
    router.add_api_route(
        f"/api/neurosense/{_owned_path}/{{path:path}}",
        _owned_route_proxy(_owned_path),
        methods=_methods,
        name=f"proxy_neurosense_{_owned_path}",
    )


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
    """HTTP proxy for stream control."""
    return await proxy_to_worker(request, settings.neurosense_hw_worker_url)


@router.websocket("/api/neurosense/stream/{path:path}")
async def proxy_neurosense_stream_websocket(websocket: WebSocket, path: str) -> None:
    """Authenticate and bridge stream traffic to the owning worker."""
    provided = websocket.headers.get("X-NMTK-Admin-Token", "") or websocket.cookies.get(
        "nmtk_admin_session", ""
    )
    if not admin_token_valid(provided):
        await websocket.close(code=4401, reason="Administrator authentication required")
        return
    await proxy_websocket_to_worker(
        websocket,
        settings.neurosense_hw_worker_url,
        target_path=f"/api/neurosense/stream/{path}",
    )


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
