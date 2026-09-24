"""Live host resource stats for the launcher server popup.

GET /api/suite/system/resources — CPU, memory, optional GPU, and host info.
"""

import asyncio as asyncio  # re-exported: tests patch system.asyncio.to_thread
import logging
import platform as platform  # re-exported: tests patch system.platform
import socket as socket  # re-exported: tests patch system.socket
import time as time  # re-exported: tests patch system.time
from typing import Any

import psutil as psutil  # re-exported: tests patch system.psutil
from fastapi import APIRouter

router = APIRouter()
logger = logging.getLogger("suite_api.system")


def _collect_gpu_stats() -> list[dict[str, Any]] | None:
    try:
        import pynvml  # type: ignore[import-not-found]
    except ImportError:
        return None

    try:
        pynvml.nvmlInit()
    except Exception:
        return None

    try:
        gpus: list[dict[str, Any]] = []
        for index in range(pynvml.nvmlDeviceGetCount()):
            handle = pynvml.nvmlDeviceGetHandleByIndex(index)
            raw_name = pynvml.nvmlDeviceGetName(handle)
            name = (
                raw_name.decode("utf-8", errors="replace")
                if isinstance(raw_name, bytes)
                else str(raw_name)
            )
            memory = pynvml.nvmlDeviceGetMemoryInfo(handle)
            utilization = pynvml.nvmlDeviceGetUtilizationRates(handle)
            gpus.append(
                {
                    "name": name,
                    "memory_total": memory.total,
                    "memory_used": memory.used,
                    "utilization": utilization.gpu,
                }
            )
        return gpus
    except Exception:
        logger.debug("gpu_stats_unavailable", exc_info=True)
        return None
    finally:
        try:
            pynvml.nvmlShutdown()
        except Exception:
            logger.debug("pynvml_shutdown_failed", exc_info=True)


def _collect_resources() -> dict[str, Any]:
    virtual_memory = psutil.virtual_memory()
    return {
        "cpu": {
            "percent": psutil.cpu_percent(interval=0.1),
            "cores": psutil.cpu_count(logical=True) or 0,
        },
        "memory": {
            "total": virtual_memory.total,
            "used": virtual_memory.used,
            "percent": virtual_memory.percent,
        },
        "gpu": _collect_gpu_stats(),
        "host": {
            "hostname": socket.gethostname(),
            "platform": platform.platform(),
            "uptime": max(0.0, time.time() - psutil.boot_time()),
        },
    }


@router.get("/system/resources")
async def system_resources() -> dict[str, Any]:
    return await asyncio.to_thread(_collect_resources)
