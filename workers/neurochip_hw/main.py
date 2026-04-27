"""Neurochip hardware worker — PYNQ, Akida, Lava, serial port flash.

Serves hardware-only routes: akida, lava, pynq, serial.
Started only when physical hardware is present.

Default port: 8002 (kept for backward compat during transition).
Start with: uvicorn workers.neurochip_hw.main:app --port 8002

Suite_api routes /api/neurochip/akida, /api/neurochip/lava,
/hardware/pynq, and /api/neurochip/serial here via HTTP proxy.

On machines without Akida/PYNQ/Lava installed, hardware routers are
skipped with a logged warning and the worker starts cleanly.
"""
import importlib
import logging
from typing import Any

from fastapi import FastAPI

logger = logging.getLogger("neurochip_hw_worker")

app = FastAPI(
    title="Neurochip Hardware Worker",
    version="0.1.0",
    description="Hardware deployment worker — Akida, Lava, PYNQ, serial flash. Profile: hardware.",
)

# Mount hardware routers — each guarded for machines without the SDK
for _name, _module, _prefix in [
    ("akida",  "neurochip.app.routers.akida",  None),   # carries own /api/neurochip/akida prefix
    ("lava",   "neurochip.app.routers.lava",   None),   # carries own /api/neurochip/hardware/lava prefix
    ("pynq",   "neurochip.app.routers.pynq",   None),   # carries own /hardware/pynq prefix
    ("serial", "neurochip.app.routers.serial", None),   # carries own /api/neurochip/serial prefix
]:
    try:
        _mod = importlib.import_module(_module)
        if _prefix:
            app.include_router(_mod.router, prefix=_prefix)
        else:
            app.include_router(_mod.router)
        logger.info("neurochip_hw: %s router loaded", _name)
    except ImportError as exc:
        logger.warning(
            "neurochip_hw: %s router skipped (hardware SDK not installed): %s",
            _name, exc,
        )


@app.get("/health")
async def health() -> dict[str, Any]:
    return {"status": "ok", "service": "neurochip-hw-worker"}
