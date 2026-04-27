"""Mount Neurochip domain routes in suite_api.

Neurochip routers already carry their full /api/neurochip/ prefix, so the
domain router is created without an additional prefix.

Optional hardware routers (akida, lava, pynq, spinnaker2) are guarded with
try/except — suite_api starts cleanly on machines without hardware SDKs.
"""
import logging
from typing import Any

from fastapi import APIRouter
from neurochip.app.routers import (
    analysis,
    deployments,
    estimation,
    export,
    faults,
    quantization,
    serial,
    targets,
)

logger = logging.getLogger("suite_api.neurochip")

# Optional hardware routers
_optional_routers = []
for _name, _module in [
    ("akida",      "neurochip.app.routers.akida"),
    ("lava",       "neurochip.app.routers.lava"),
    ("pynq",       "neurochip.app.routers.pynq"),
    ("spinnaker2", "neurochip.app.routers.spinnaker2"),
]:
    try:
        import importlib
        _mod = importlib.import_module(_module)
        _optional_routers.append(_mod.router)
    except ImportError as exc:
        logger.warning("neurochip: %s router unavailable: %s", _name, exc)

# Neurochip routers already contain their full prefix
router = APIRouter()

for _r in [
    targets.router,
    analysis.router,
    quantization.router,
    faults.router,
    estimation.router,
    export.router,
    serial.router,
    deployments.router,
]:
    router.include_router(_r)

for _r in _optional_routers:
    router.include_router(_r)


@router.get("/api/neurochip/health")
async def neurochip_health() -> dict[str, Any]:
    """Health check for the Neurochip domain (matches original 'healthy' status)."""
    return {"status": "healthy", "service": "neurochip"}
