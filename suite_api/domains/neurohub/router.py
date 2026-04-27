"""Mount Neurohub domain routes in suite_api.

Neurohub routers carry no prefix themselves — they are mounted with
prefix="/api/neurohub" mirroring the original main.py.

Neurohub's lifespan (Alembic + workflow worker) is handled separately in
suite_api/main.py's asynccontextmanager.
"""
import logging
from typing import Any

from fastapi import APIRouter
from neurohub.app.routers import (
    activity,
    assets,
    auth,
    config as nh_config,
    dashboard,
    health as nh_health,
    members,
    milestones,
    notes,
    projects,
    workflows,
)

logger = logging.getLogger("suite_api.neurohub")

router = APIRouter()

# Mount all Neurohub routers with the same prefix as the original main.py
for _r in [
    auth.router,
    dashboard.router,
    projects.router,
    milestones.router,
    assets.router,
    workflows.router,
    activity.router,
    nh_health.router,
    nh_config.router,
    members.router,
    notes.router,
]:
    router.include_router(_r, prefix="/api/neurohub")
