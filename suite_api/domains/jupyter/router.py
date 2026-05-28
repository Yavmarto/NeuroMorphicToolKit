"""Health proxy for the Jupyter Server worker.

Exposes GET /api/jupyter/health which probes the Jupyter Server 2.x built-in
health endpoint and returns a normalised status object consistent with other
NMTK module health responses.
"""
import logging

import httpx
from fastapi import APIRouter
from fastapi.responses import JSONResponse

from suite_api.config import settings

router = APIRouter(prefix="/api/jupyter", tags=["jupyter"])

_logger = logging.getLogger("suite_api.jupyter")


@router.get("/health")
async def jupyter_health() -> JSONResponse:
    """Probe the Jupyter Server worker and return a normalised health status."""
    target = f"{settings.jupyter_worker_url.rstrip('/')}/api/status"
    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            resp = await client.get(target)
        if resp.status_code == 200:
            return JSONResponse({"status": "ok", "module": "jupyter"})
        return JSONResponse(
            {"status": "degraded", "module": "jupyter", "detail": f"HTTP {resp.status_code}"},
            status_code=200,
        )
    except httpx.ConnectError:
        return JSONResponse(
            {"status": "unavailable", "module": "jupyter", "detail": "Jupyter Server not reachable"},
            status_code=503,
        )
    except Exception as exc:  # noqa: BLE001
        _logger.warning("Jupyter health check failed: %s", exc)
        return JSONResponse(
            {"status": "error", "module": "jupyter", "detail": str(exc)},
            status_code=503,
        )
