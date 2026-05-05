"""Mount Neurobench domain routes in suite_api.

Result-storage and reporting routes (baselines, benchmarks, comparison, faults,
perturbation, regression, reports, results, synsense) are served in-process.

Job-dispatch routes (runner, pynq hardware, spinnaker2) are proxied to the
neurobench-runner-worker (port 8003, Docker profile: jobs). When the worker
is not running, those routes return HTTP 503.

The runner router handles long-running compute jobs; isolating it prevents the
main API from blocking during benchmark execution.
"""
import logging
import importlib
from typing import Any

from fastapi import APIRouter, Request
from fastapi.responses import Response

import suite_api.domains.neurobench  # noqa: F401 (side-effect: env isolation + sys.path)

from app.routers import (
    baselines,
    benchmarks,
    comparison,
    faults,
    perturbation,
    regression,
    reports,
    results,
)

from suite_api.config import settings
from suite_api.proxy import proxy_to_worker

logger = logging.getLogger("suite_api.neurobench")

# Optional in-process: synsense (simulation results, not execution)
_synsense_router = None
try:
    _synsense_mod = importlib.import_module("app.routers.synsense")
    _synsense_router = _synsense_mod.router
except ImportError as exc:
    logger.warning("neurobench: synsense router unavailable: %s", exc)

router = APIRouter()

# ── In-process: result storage and reporting routes ───────────────────────────
router.include_router(benchmarks.router,   prefix="/api/neurobench/benchmarks")
router.include_router(comparison.router,   prefix="/api/neurobench/compare")
router.include_router(faults.router,       prefix="/api/neurobench/faults")
router.include_router(perturbation.router, prefix="/api/neurobench/perturbation")
router.include_router(baselines.router,    prefix="/api/neurobench/baselines")
router.include_router(results.router,      prefix="/api/neurobench/results")
router.include_router(regression.router,   prefix="/api/neurobench/regression")
router.include_router(reports.router,      prefix="/api/neurobench/report")

if _synsense_router is not None:
    router.include_router(_synsense_router, prefix="/bench/synsense")


# ── Proxied: job-dispatch routes → neurobench-runner-worker (port 8003) ───────
# These routes return 503 when the runner worker is not running.

@router.api_route(
    "/api/neurobench/run",
    methods=["GET", "POST"],
)
async def proxy_neurobench_run_root(request: Request) -> Response:
    return await proxy_to_worker(request, settings.neurobench_runner_url, profile_hint="jobs")


@router.api_route(
    "/api/neurobench/run/{path:path}",
    methods=["GET", "POST", "DELETE", "PUT", "PATCH"],
)
async def proxy_neurobench_run(request: Request, path: str) -> Response:
    return await proxy_to_worker(request, settings.neurobench_runner_url, profile_hint="jobs")


@router.api_route(
    "/api/neurobench/pynq/{path:path}",
    methods=["GET", "POST"],
)
async def proxy_neurobench_pynq(request: Request, path: str) -> Response:
    """Proxy PYNQ hardware execution routes to the runner worker."""
    return await proxy_to_worker(request, settings.neurobench_runner_url, profile_hint="jobs")


@router.api_route(
    "/bench/spinnaker2/{path:path}",
    methods=["GET", "POST"],
)
async def proxy_neurobench_spinnaker2(request: Request, path: str) -> Response:
    """Proxy SpiNNaker2 execution routes to the runner worker."""
    return await proxy_to_worker(request, settings.neurobench_runner_url, profile_hint="jobs")


@router.get("/api/neurobench/health")
async def neurobench_health() -> dict[str, Any]:
    """Health check for the Neurobench domain (in-process result-storage routes)."""
    return {
        "status": "ok",
        "service": "neurobench",
        "runner_worker": settings.neurobench_runner_url,
        "note": "Job-dispatch routes (/run, /pynq, /bench/spinnaker2) proxied to runner worker",
    }
