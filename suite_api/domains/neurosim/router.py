"""Mount Neurosim domain routes in suite_api.

Neurosim routers already carry their full /api/neurosim/ prefix, so the
domain router is created without an additional prefix.
"""

import logging
from typing import Any

from fastapi import APIRouter

from neurosim.app.routers import (
    components,
    custom_nodes,
    export,
    generation,
    nir_canvas,
    preview,
    projects,
    simulation_ws,
    sweep,
    templates,
    validation,
)

logger = logging.getLogger("suite_api.neurosim")

# SpiNNaker2 is optional hardware integration — guard import
try:
    from neurosim.app.routers import spinnaker2

    _has_spinnaker2 = True
except ImportError as exc:
    logger.warning("neurosim: spinnaker2 router unavailable: %s", exc)
    _has_spinnaker2 = False

# Neurosim routers already contain /api/neurosim/ in their prefixes
router = APIRouter()

for _r in [
    components.router,
    custom_nodes.router,
    nir_canvas.router,
    simulation_ws.router,
    templates.router,
    validation.router,
    generation.router,
    preview.router,
    sweep.router,
    export.router,
    projects.router,
]:
    router.include_router(_r)

if _has_spinnaker2:
    router.include_router(spinnaker2.router)


@router.get("/api/neurosim/health")
async def neurosim_health() -> dict[str, Any]:
    """Health check for the Neurosim domain."""
    return {"status": "ok", "service": "neurosim"}
