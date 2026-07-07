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
from suite_api.proxy import proxy_to_worker

router = APIRouter(prefix="/api/jupyter", tags=["jupyter"])

_logger = logging.getLogger("suite_api.jupyter")


def _env_manager_path(public_path: str) -> str:
    """Map suite API Jupyter routes to the worker extension mount path."""
    prefix = "/api/jupyter"
    suffix = public_path[len(prefix) :] if public_path.startswith(prefix) else public_path
    return f"/nmtk-envs/api{suffix}"


async def _proxy_to_env_manager(request: Request) -> Response:
    return await proxy_to_worker(
        request,
        settings.jupyter_worker_url,
        target_path=_env_manager_path(request.url.path),
    )


@router.get("/url")
async def jupyter_url() -> JSONResponse:
    """Return the publicly accessible JupyterLab URL when the server is reachable.

    The Flutter app calls this endpoint to get the URL it should load in the
    embedded WebView.  Returns 503 while the Jupyter worker is not yet up so
    the client can poll and retry automatically.
    """
    target = f"{settings.jupyter_worker_url.rstrip('/')}/api/status"
    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            resp = await client.get(target)
        if resp.status_code == 200:
            return JSONResponse({"url": settings.jupyter_public_url})
        return JSONResponse(
            {"error": f"Jupyter unavailable (HTTP {resp.status_code})"},
            status_code=503,
        )
    except httpx.ConnectError:
        return JSONResponse(
            {"error": "Jupyter Server not reachable"},
            status_code=503,
        )
    except Exception as exc:  # noqa: BLE001
        _logger.warning("Jupyter URL check failed: %s", exc)
        return JSONResponse({"error": str(exc)}, status_code=503)


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
async def list_environments(request: Request) -> Response:
    return await _proxy_to_env_manager(request)


@router.post("/environments")
async def create_environment(request: Request) -> Response:
    """Create a clone (or import a requirements file). Returns a job id."""
    return await _proxy_to_env_manager(request)


@router.delete("/environments/{slug}")
async def delete_environment(request: Request, slug: str) -> Response:
    return await _proxy_to_env_manager(request)


@router.get("/environments/{slug}/packages")
async def list_packages(request: Request, slug: str) -> Response:
    return await _proxy_to_env_manager(request)


@router.post("/environments/{slug}/packages")
async def mutate_packages(request: Request, slug: str) -> Response:
    """Install/uninstall packages in a clone. Returns a job id."""
    return await _proxy_to_env_manager(request)


@router.get("/environments/{slug}/requirements")
async def export_requirements(request: Request, slug: str) -> Response:
    return await _proxy_to_env_manager(request)


@router.post("/executions")
async def execute_notebook(request: Request) -> Response:
    return await _proxy_to_env_manager(request)


@router.get("/jobs/{job_id}")
async def get_job(request: Request, job_id: str) -> Response:
    return await _proxy_to_env_manager(request)
