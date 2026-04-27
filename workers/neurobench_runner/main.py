"""Neurobench runner worker — long-running benchmark job execution.

Serves job-dispatch routes only: runner, pynq (hardware execution), spinnaker2.
Started only when benchmark compute is needed.

Default port: 8003 (kept for backward compat during transition).
Start with: uvicorn workers.neurobench_runner.main:app --port 8003

Suite_api routes /api/neurobench/run and /bench/* here via HTTP proxy.
Result storage (/api/neurobench/results) stays in suite_api in-process.
"""
import importlib
import logging
import sys
from pathlib import Path
from typing import Any

from fastapi import FastAPI

# Make neurobench 'app' package importable via sys.path
_NB_PATH = Path(__file__).parents[2] / "Neurobench" / "neurobench"
if str(_NB_PATH) not in sys.path:
    sys.path.insert(0, str(_NB_PATH))

# Trigger Neurobench config with extra="ignore" to handle suite-level .env vars
import app.config  # noqa: F401, E402

from app.routers import runner  # noqa: E402

logger = logging.getLogger("neurobench_runner_worker")

app_instance = FastAPI(
    title="Neurobench Runner Worker",
    version="0.1.0",
    description="Long-running benchmark job worker. Profile: jobs.",
)

# Core job-dispatch router
app_instance.include_router(runner.router, prefix="/api/neurobench/run")

# Optional hardware runners
for _name, _module, _prefix in [
    ("pynq",       "app.routers.pynq",       "/api/neurobench/pynq"),
    ("spinnaker2", "app.routers.spinnaker2",  "/bench/spinnaker2"),
]:
    try:
        _mod = importlib.import_module(_module)
        app_instance.include_router(_mod.router, prefix=_prefix)
        logger.info("neurobench_runner: %s router loaded", _name)
    except ImportError as exc:
        logger.warning("neurobench_runner: %s unavailable: %s", _name, exc)


@app_instance.get("/health")
async def health() -> dict[str, Any]:
    return {"status": "ok", "service": "neurobench-runner-worker"}


# Expose as 'app' for uvicorn
app = app_instance
