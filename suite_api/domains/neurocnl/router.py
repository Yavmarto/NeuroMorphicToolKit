"""Mount neurocnl domain routes in suite_api.
All routes are mounted under /api/neurocnl/.
"""
# Ensure neurocnl/backend is importable via sys.path preamble
import suite_api.domains.neurocnl  # noqa: F401 (side-effect import)

import logging
from fastapi import APIRouter

from backend.app.routers import (
    parse,
    validate,
    generate,
    simulate,
    export,
    deploy,
    jobs,
    neurosim_handoff,
    templates,
)
from backend.app.routers.prosthetic import (
    analysis as prosthetic_analysis,
    export as prosthetic_export,
    simulate as prosthetic_sim,
    sleep as prosthetic_sleep,
)

from typing import Any
from fastapi.responses import JSONResponse

logger = logging.getLogger("suite_api.neurocnl")

# Hardware router is optional — requires physical serial port access
try:
    from backend.app.routers.prosthetic import hardware as prosthetic_hardware
    _has_prosthetic_hw = True
except ImportError as exc:
    logger.warning("neurocnl: prosthetic hardware router unavailable: %s", exc)
    _has_prosthetic_hw = False

router = APIRouter(prefix="/api/neurocnl")


@router.get("/health")
def neurocnl_health() -> dict[str, Any]:
    """Proxy-equivalent health check for neurocnl domain."""
    import shutil
    from datetime import UTC, datetime
    from pathlib import Path
    import neurocnl

    disk = shutil.disk_usage(Path.cwd())
    return {
        "status": "ok",
        "neurocnl_version": neurocnl.__version__,
        "timestamp": datetime.now(UTC).isoformat(),
        "modules": {},
        "disk": {
            "total_gb": round(disk.total / (1024**3), 2),
            "used_gb": round((disk.total - disk.free) / (1024**3), 2),
            "free_gb": round(disk.free / (1024**3), 2),
            "low_space": round(disk.free / (1024**3), 2) < 5,
        },
    }

for _r in [
    parse.router,
    validate.router,
    generate.router,
    simulate.router,
    export.router,
    deploy.router,
    jobs.router,
    neurosim_handoff.router,
    templates.router,
]:
    router.include_router(_r)

# Prosthetic sub-routes
for _r in [
    prosthetic_sim.router,
    prosthetic_sleep.router,
    prosthetic_export.router,
    prosthetic_analysis.router,
]:
    router.include_router(_r, prefix="/prosthetic")

if _has_prosthetic_hw:
    router.include_router(prosthetic_hardware.router, prefix="/prosthetic")
