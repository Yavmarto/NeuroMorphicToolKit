"""Mount Neurobench domain routes in suite_api.

Neurobench routers carry no prefix themselves — the original main.py applies
prefixes at include_router time. We replicate that same prefix assignment here.

The runner router handles long-running jobs; its job-dispatch logic is
unchanged — only the HTTP surface moves (Phase 4B will formalize as a worker).
"""
import logging
import importlib
from typing import Any

import suite_api.domains.neurobench  # noqa: F401 (side-effect: env isolation + sys.path)

from fastapi import APIRouter
from app.routers import (
    baselines,
    benchmarks,
    comparison,
    faults,
    perturbation,
    regression,
    reports,
    results,
    runner,
)

logger = logging.getLogger("suite_api.neurobench")

# Optional hardware / simulation routers
_optional: list[tuple[Any, str]] = []
for _name, _module, _prefix in [
    ("pynq",       "app.routers.pynq",       "/api/neurobench/pynq"),
    ("spinnaker2", "app.routers.spinnaker2",  "/bench/spinnaker2"),
    ("synsense",   "app.routers.synsense",    "/bench/synsense"),
]:
    try:
        _mod = importlib.import_module(_module)
        _optional.append((_mod.router, _prefix))
    except ImportError as exc:
        logger.warning("neurobench: %s router unavailable: %s", _name, exc)

router = APIRouter()

# Core routers with their original prefixes (mirroring Neurobench's main.py)
router.include_router(benchmarks.router, prefix="/api/neurobench/benchmarks")
router.include_router(runner.router,     prefix="/api/neurobench/run")
router.include_router(comparison.router, prefix="/api/neurobench/compare")
router.include_router(faults.router,     prefix="/api/neurobench/faults")
router.include_router(perturbation.router, prefix="/api/neurobench/perturbation")
router.include_router(baselines.router,  prefix="/api/neurobench/baselines")
router.include_router(results.router,    prefix="/api/neurobench/results")
router.include_router(regression.router, prefix="/api/neurobench/regression")
router.include_router(reports.router,    prefix="/api/neurobench/report")

for _r, _pfx in _optional:
    router.include_router(_r, prefix=_pfx)


@router.get("/api/neurobench/health")
async def neurobench_health() -> dict[str, Any]:
    """Health check for the Neurobench domain."""
    return {"status": "ok", "service": "neurobench"}
