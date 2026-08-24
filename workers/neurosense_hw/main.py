"""Neurosense hardware worker — real-time device I/O.

Serves hardware-facing routes only: devices, stream (WebSocket), prophesee,
and pynq. Started only when hardware (BrainFlow/Prophesee/PYNQ) is present.

Default port: 8004 (kept for backward compat during transition).
Start with: uvicorn workers.neurosense_hw.main:app --port 8004

Suite_api routes /api/neurosense/devices, /api/neurosense/stream, and
/api/neurosense/sense/* here via HTTP proxy when this worker is running.
"""

import importlib
import logging
import sys
from pathlib import Path
from typing import Any

from fastapi import FastAPI

# Make neurosense package importable (installed via pip install -e Neurosense/)
# The neurosense package is installed; this just ensures it's on the path.
_NEUROSENSE_PATH = Path(__file__).parents[2] / "Neurosense" / "neurosense"
if str(_NEUROSENSE_PATH) not in sys.path:
    sys.path.insert(0, str(_NEUROSENSE_PATH))

from neurosense.app.routers import devices, export, recording, sessions, stream

logger = logging.getLogger("neurosense_hw_worker")

app = FastAPI(
    title="Neurosense Hardware Worker",
    version="0.1.0",
    description="Hardware I/O worker — BrainFlow, Prophesee, PYNQ. Profile: hardware.",
)

# Core hardware routers
app.include_router(devices.router, prefix="/api/neurosense/devices")
app.include_router(stream.router, prefix="/api/neurosense/stream")
app.include_router(recording.router, prefix="/api/neurosense/recording")
app.include_router(sessions.router, prefix="/api/neurosense/sessions")
app.include_router(export.router, prefix="/api/neurosense/export")

# Optional hardware routers
for _name, _module, _prefix in [
    (
        "prophesee",
        "neurosense.app.routers.prophesee",
        "/api/neurosense/sense/prophesee",
    ),
    ("pynq", "neurosense.app.routers.pynq", "/api/neurosense"),
]:
    try:
        _mod = importlib.import_module(_module)
        app.include_router(_mod.router, prefix=_prefix)
        logger.info("neurosense_hw: %s router loaded", _name)
    except ImportError as exc:
        logger.warning("neurosense_hw: %s unavailable (missing SDK): %s", _name, exc)


@app.get("/health")
async def health() -> dict[str, Any]:
    return {"status": "ok", "service": "neurosense-hw-worker"}
