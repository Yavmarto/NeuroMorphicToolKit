"""Health aggregation endpoint.
GET /api/suite/health  — suite_api's own health.
GET /api/suite/health/modules — aggregated health of all module backends.
"""

import asyncio as asyncio  # re-exported: tests patch health.asyncio.to_thread
import logging
import os
import sqlite3
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import httpx as httpx  # re-exported: tests patch health.httpx.AsyncClient
from fastapi import APIRouter

from suite_api.config import settings
from suite_api.domains.jupyter.router import probe_jupyter_doctor
from suite_api.schemas.doctor import (
    DoctorCheck,
    DoctorReport,
    DoctorRequest as DoctorRequest,
    DoctorStatus as DoctorStatus,
)
from suite_api.storage import default_neurocnl_data_dir

router = APIRouter()
logger = logging.getLogger("suite_api.health")

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
    "neurocnl": f"{_SELF}/api/neurocnl/health",
    "neurosim": f"{_SELF}/api/neurosim/health",
    "neurochip": f"{_SELF}/api/neurochip/health",
    "neurobench": f"{_SELF}/api/neurobench/health",
    "neurosense": f"{_SELF}/api/neurosense/health",
    "neurohub": f"{_SELF}/api/neurohub/health",
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
            error = (
                None
                if resp.status_code == 200
                else f"Module health check returned HTTP {resp.status_code}."
            )
        except Exception as exc:
            logger.warning(
                "module_health_probe_failed",
                extra={"module_name": name},
                exc_info=exc,
            )
            status = "offline"
            error = "Module health check is unavailable."
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


def _storage_checks(data_dir: Path) -> list[DoctorCheck]:
    checks: list[DoctorCheck] = []
    upload_dir = data_dir / "pipeline_uploads"
    try:
        upload_dir.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(
            dir=upload_dir, prefix=".nmtk-doctor-"
        ) as probe:
            probe.write(b"nmtk-health")
            probe.flush()
        checks.append(
            DoctorCheck(
                id="dataset-storage",
                label="Dataset uploads",
                status=DoctorStatus.OK,
                detail="The server can create and remove dataset upload files.",
            )
        )
    except OSError:
        checks.append(
            DoctorCheck(
                id="dataset-storage",
                label="Dataset uploads",
                status=DoctorStatus.FAILED,
                detail="The server data directory is not writable.",
                recovery="Repair the backend storage from System Health.",
                repairable=True,
            )
        )

    database_paths = [data_dir / "datasets.db", data_dir / "jobs.db"]
    failed_databases: list[str] = []
    for database_path in database_paths:
        try:
            with sqlite3.connect(database_path) as connection:
                result = connection.execute("PRAGMA quick_check").fetchone()
            if result is None or result[0] != "ok":
                failed_databases.append(database_path.name)
        except sqlite3.Error:
            failed_databases.append(database_path.name)
    checks.append(
        DoctorCheck(
            id="suite-databases",
            label="Backend databases",
            status=(DoctorStatus.FAILED if failed_databases else DoctorStatus.OK),
            detail=(
                f"Database check failed for {', '.join(failed_databases)}."
                if failed_databases
                else "Dataset and job databases passed an integrity check."
            ),
            recovery=(
                "Run a data-preserving backend reinstall from System Health."
                if failed_databases
                else ""
            ),
            repairable=bool(failed_databases),
        )
    )
    return checks


def _overall_status(checks: list[DoctorCheck]) -> DoctorStatus:
    if any(check.status == DoctorStatus.FAILED and check.required for check in checks):
        return DoctorStatus.FAILED
    if any(
        check.status in {DoctorStatus.FAILED, DoctorStatus.DEGRADED} for check in checks
    ):
        return DoctorStatus.DEGRADED
    return DoctorStatus.OK


@router.post("/doctor", response_model=DoctorReport, response_model_by_alias=True)
async def suite_doctor(request: DoctorRequest) -> DoctorReport:
    """Exercise storage, databases, Jupyter, and configured frameworks."""
    data_dir = default_neurocnl_data_dir()
    storage_checks = await asyncio.to_thread(_storage_checks, data_dir)
    checks = [
        DoctorCheck(
            id="suite-api",
            label="Suite API",
            status=DoctorStatus.OK,
            detail="Suite API is serving diagnostic requests.",
        ),
        *storage_checks,
    ]
    try:
        jupyter_payload = await probe_jupyter_doctor(request.capabilities)
        raw_checks = jupyter_payload.get("checks", [])
        checks.extend(DoctorCheck.model_validate(item) for item in raw_checks)
    except Exception:  # noqa: BLE001
        checks.append(
            DoctorCheck(
                id="jupyter-service",
                label="Jupyter service",
                status=DoctorStatus.FAILED,
                detail="Jupyter did not answer its diagnostic request.",
                recovery="Restart Jupyter from System Health.",
                repairable=True,
            )
        )
    return DoctorReport(
        overall=_overall_status(checks),
        checkedAt=datetime.now(timezone.utc).isoformat(),
        checks=checks,
    )
