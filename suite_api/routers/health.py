"""Health aggregation endpoint.
GET /api/suite/health  — suite_api's own health.
GET /api/suite/health/modules — aggregated health of all module backends.
"""
import asyncio
import os
import time
from typing import Any

import httpx
from fastapi import APIRouter

from suite_api.config import settings

router = APIRouter()

# Stamped into the image by .github/workflows/release-docker.yml (see
# suite_api/Dockerfile's NMTK_VERSION ARG). "dev" means a local/source build:
# the launcher reads that as "not a release" and never offers an in-app update
# against it, since there is no release to compare with.
BACKEND_VERSION = os.environ.get("NMTK_VERSION", "dev").strip() or "dev"

# Probe suite_api's own in-process domain health endpoints.
# After consolidation the standalone module services no longer exist;
# all domains run inside suite_api itself.
_SELF = f"http://localhost:{settings.suite_api_port}"
MODULE_URLS: dict[str, str] = {
    "neurocnl":   f"{_SELF}/api/neurocnl/health",
    "neurosim":   f"{_SELF}/api/neurosim/health",
    "neurochip":  f"{_SELF}/api/neurochip/health",
    "neurobench": f"{_SELF}/api/neurobench/health",
    "neurosense": f"{_SELF}/api/neurosense/health",
    "neurohub":   f"{_SELF}/api/neurohub/health",
}


@router.get("/health")
async def suite_health() -> dict[str, str]:
    return {"status": "ok", "service": "suite_api", "version": BACKEND_VERSION}


@router.get("/health/modules")
async def modules_health() -> dict[str, Any]:
    async def probe(name: str, url: str) -> tuple[str, dict[str, Any]]:
        start = time.perf_counter()
        try:
            async with httpx.AsyncClient(timeout=5.0) as client:
                resp = await client.get(url)
            status = "online" if resp.status_code == 200 else "degraded"
            error = None if resp.status_code == 200 else resp.text
        except Exception as exc:
            status = "offline"
            error = str(exc)
        response_time_ms = (time.perf_counter() - start) * 1000
        return name, {
            "status": status,
            "response_time_ms": round(response_time_ms, 2),
            "error": error,
        }

    results = await asyncio.gather(
        *(probe(name, url) for name, url in MODULE_URLS.items())
    )
    return {"suite_api": "ok", "modules": dict(results)}
