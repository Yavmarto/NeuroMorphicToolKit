"""Mount Neurobench domain routes in suite_api.

Result-storage and reporting routes (baselines, benchmarks, comparison, faults,
perturbation, regression, reports, results, synsense) are served in-process.

Job-dispatch routes (runner, pynq hardware, spinnaker2) are proxied to the
neurobench-runner-worker (port 8003, Docker profile: jobs). When the worker
is not running, those routes return HTTP 503.

The runner router handles long-running compute jobs; isolating it prevents the
main API from blocking during benchmark execution.
"""

from typing import Any

from fastapi import APIRouter, Request
from fastapi.responses import Response

import suite_api.domains.neurobench  # noqa: F401 (side-effect: env isolation + sys.path)
from suite_api.config import settings
from suite_api.proxy import proxy_to_worker

router = APIRouter()


@router.get("/api/neurobench/health")
async def neurobench_health() -> dict[str, Any]:
    """Health check for the Neurobench domain (in-process result-storage routes)."""
    return {
        "status": "ok",
        "service": "neurobench",
        "runner_worker": settings.neurobench_runner_url,
        "note": "Neurobench routes are owned by the durable runner worker",
    }


@router.api_route(
    "/api/neurobench/{path:path}",
    methods=["GET", "POST", "DELETE", "PUT", "PATCH"],
)
async def proxy_neurobench(request: Request, path: str) -> Response:
    """Proxy the stable Neurobench API to its authoritative worker."""
    return await proxy_to_worker(request, settings.neurobench_runner_url)


@router.api_route(
    "/bench/{path:path}",
    methods=["GET", "POST", "DELETE", "PUT", "PATCH"],
)
async def proxy_neurobench_legacy(request: Request, path: str) -> Response:
    """Proxy legacy benchmark paths without changing their public shape."""
    return await proxy_to_worker(request, settings.neurobench_runner_url)
