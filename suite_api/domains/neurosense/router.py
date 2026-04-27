"""Mount Neurosense domain routes in suite_api.

Neurosense routers carry no prefix — we replicate the original main.py's
prefix assignment. The WebSocket stream router is included as-is; FastAPI's
include_router handles WebSocket routes correctly.

Hardware routes (devices, stream, prophesee, pynq) return 503 when
hardware is absent — existing behaviour, unchanged.
"""
import logging
import importlib
from typing import Any

from fastapi import APIRouter
from neurosense.app.routers import (
    devices,
    encoding,
    export,
    nir,
    presets,
    quality,
    recording,
    sessions,
    stream,
)

logger = logging.getLogger("suite_api.neurosense")

# Optional hardware routers
_optional: list[tuple[Any, str]] = []
for _name, _module, _prefix in [
    ("prophesee", "neurosense.app.routers.prophesee", "/api/neurosense/sense/prophesee"),
    ("pynq",      "neurosense.app.routers.pynq",      "/api/neurosense"),
]:
    try:
        _mod = importlib.import_module(_module)
        _optional.append((_mod.router, _prefix))
    except ImportError as exc:
        logger.warning("neurosense: %s router unavailable: %s", _name, exc)

router = APIRouter()

# Core routers mirroring Neurosense's main.py prefix assignments
router.include_router(devices.router,   prefix="/api/neurosense/devices")
router.include_router(presets.router,   prefix="/api/neurosense/presets")
router.include_router(stream.router,    prefix="/api/neurosense/stream")
router.include_router(encoding.router,  prefix="/api/neurosense/encode")
router.include_router(recording.router, prefix="/api/neurosense/recording")
router.include_router(sessions.router,  prefix="/api/neurosense/sessions")
router.include_router(quality.router,   prefix="/api/neurosense/quality")
router.include_router(export.router,    prefix="/api/neurosense/export")
router.include_router(nir.router,       prefix="/api/neurosense/nir")

for _r, _pfx in _optional:
    router.include_router(_r, prefix=_pfx)


@router.get("/api/neurosense/health")
async def neurosense_health() -> dict[str, Any]:
    """Health check for the Neurosense domain."""
    return {"status": "ok", "service": "neurosense"}
