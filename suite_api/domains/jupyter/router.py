"""Health + environment-manager proxy for the Jupyter Server worker.

Exposes GET /api/jupyter/health which probes the Jupyter Server 2.x built-in
health endpoint, plus a thin proxy for the ``nmtk_env_manager`` server
extension (``/nmtk-envs/api/*``) so the Flutter app can manage Python
environments through the single suite_api surface.
"""
import logging

import httpx
from fastapi import APIRouter, Request, Response
from fastapi.responses import JSONResponse

from suite_api.config import settings

router = APIRouter(prefix="/api/jupyter", tags=["jupyter"])

_logger = logging.getLogger("suite_api.jupyter")

# Base URL of the env-manager extension inside the Jupyter worker.
_ENV_BASE = f"{settings.jupyter_worker_url.rstrip('/')}/nmtk-envs/api"


async def _proxy(
    method: str,
    path: str,
    *,
    params: dict | None = None,
    body: bytes | None = None,
) -> Response:
    """Forward a request to the env-manager extension, preserving status/body."""
    url = f"{_ENV_BASE}/{path.lstrip('/')}"
    try:
        async with httpx.AsyncClient(timeout=30.0) as client:
            upstream = await client.request(
                method,
                url,
                params=params,
                content=body,
                headers={"Content-Type": "application/json"} if body else None,
            )
    except httpx.ConnectError:
        return JSONResponse(
            {"error": "Jupyter Server not reachable", "module": "jupyter"},
            status_code=503,
        )
    except Exception as exc:  # noqa: BLE001
        _logger.warning("Jupyter env proxy failed: %s", exc)
        return JSONResponse({"error": str(exc), "module": "jupyter"}, status_code=502)
    media_type = upstream.headers.get("content-type")
    return Response(
        content=upstream.content,
        status_code=upstream.status_code,
        media_type=media_type,
    )


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


# ── Environment manager proxy ──────────────────────────────────────────────────
@router.get("/environments")
async def list_environments() -> Response:
    return await _proxy("GET", "environments")


@router.post("/environments")
async def create_environment(request: Request) -> Response:
    """Create a clone (or import a requirements file). Returns a job id."""
    return await _proxy("POST", "environments", body=await request.body())


@router.delete("/environments/{slug}")
async def delete_environment(slug: str) -> Response:
    return await _proxy("DELETE", f"environments/{slug}")


@router.get("/environments/{slug}/packages")
async def list_packages(slug: str) -> Response:
    return await _proxy("GET", f"environments/{slug}/packages")


@router.post("/environments/{slug}/packages")
async def mutate_packages(slug: str, request: Request) -> Response:
    """Install/uninstall packages in a clone. Returns a job id."""
    return await _proxy("POST", f"environments/{slug}/packages", body=await request.body())


@router.get("/environments/{slug}/requirements")
async def export_requirements(slug: str, mode: str = "delta") -> Response:
    return await _proxy("GET", f"environments/{slug}/requirements", params={"mode": mode})


@router.get("/jobs/{job_id}")
async def get_job(job_id: str) -> Response:
    return await _proxy("GET", f"jobs/{job_id}")
