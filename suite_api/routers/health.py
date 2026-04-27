"""Health aggregation endpoint.
GET /api/suite/health  — suite_api's own health.
GET /api/suite/health/modules — aggregated health of all module backends.
"""
import asyncio
import time
from typing import Any

import httpx
from fastapi import APIRouter

from suite_api.config import settings

router = APIRouter()

MODULE_URLS: dict[str, str] = {
    "neurocnl":   f"{settings.neurocnl_url}/health",
    "neurosim":   f"{settings.neurosim_url}/health",
    "neurochip":  f"{settings.neurochip_url}/health",
    "neurobench": f"{settings.neurobench_url}/health",
    "neurosense": f"{settings.neurosense_url}/health",
    "neurohub":   f"{settings.neurohub_url}/api/neurohub/health",
}


@router.get("/health")
async def suite_health() -> dict[str, str]:
    return {"status": "ok", "service": "suite_api"}


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
