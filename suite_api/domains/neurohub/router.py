"""Mount Neurohub domain routes in suite_api.

Neurohub routers carry no prefix themselves — they are mounted with the
same prefixes as ``Neurohub/neurohub/app/main.py``.

Neurohub's lifespan (Alembic migrations) is handled separately in
``suite_api/main.py``'s asynccontextmanager.
"""

import logging

from fastapi import APIRouter
from neurohub.app.routers import (
    assets,
    config as nh_config,
    github_auth,
    health as nh_health,
    projects,
    registry_artefacts,
    registry_auth,
    registry_community,
    registry_health,
    registry_search,
    sharing,
    workspaces,
)

logger = logging.getLogger("suite_api.neurohub")

router = APIRouter()

for _r in (
    projects.router,
    assets.router,
    nh_health.router,
    nh_config.router,
    sharing.router,
    workspaces.router,
    github_auth.router,
):
    router.include_router(_r, prefix="/api/neurohub")

for _r in (
    registry_auth.router,
    registry_artefacts.router,
    registry_search.router,
    registry_community.router,
    registry_health.router,
):
    router.include_router(_r, prefix="/api/v1")
