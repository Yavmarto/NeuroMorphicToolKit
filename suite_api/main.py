"""suite_api — unified NeuroMorphicToolKit backend.

Start with: uvicorn suite_api.main:app --port 9000 --reload
"""
import logging
import traceback
from contextlib import asynccontextmanager
from collections.abc import AsyncGenerator

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from suite_api.middleware import attach_middleware
from suite_api.routers import health
from suite_api.domains.neurohub.lifespan import neurohub_startup, neurohub_shutdown
from suite_api.domains.neurocnl.lifespan import neurocnl_startup, neurocnl_shutdown

from fastapi.staticfiles import StaticFiles
from pathlib import Path


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncGenerator[None, None]:
    # await neurohub_startup()
    await neurocnl_startup(app)
    yield
    await neurocnl_shutdown()
    # await neurohub_shutdown()


app = FastAPI(
    title="NeuroMorphicToolKit Suite API",
    version="0.1.0",
    description="Unified backend for the NMTK suite.",
    lifespan=lifespan,
)

attach_middleware(app)

_logger = logging.getLogger("suite_api")


@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception) -> JSONResponse:
    """Catch-all handler: log full traceback and return structured JSON 500."""
    _logger.error("Unhandled exception: %s\n%s", str(exc), traceback.format_exc())
    return JSONResponse(status_code=500, content={"detail": "Internal Server Error"})


app.include_router(health.router, prefix="/api/suite", tags=["health"])

from suite_api.domains.neurocnl.router import router as neurocnl_router  # noqa: E402
app.include_router(neurocnl_router)

from suite_api.domains.neurosim.router import router as neurosim_router  # noqa: E402
app.include_router(neurosim_router)

from suite_api.domains.neurochip.router import router as neurochip_router  # noqa: E402
app.include_router(neurochip_router)

from suite_api.domains.neurobench.router import router as neurobench_router  # noqa: E402
app.include_router(neurobench_router)

from suite_api.domains.neurosense.router import router as neurosense_router  # noqa: E402
app.include_router(neurosense_router)

# from suite_api.domains.neurohub.router import router as neurohub_router  # noqa: E402
# app.include_router(neurohub_router)

from suite_api.domains.jupyter.router import router as jupyter_router  # noqa: E402
app.include_router(jupyter_router)


# ── Static Frontend Mounting ────────────────────────────────────────────────
# Each module frontend is mounted at /{module_id}/.
# These expect to find build/web/ index.html and assets in their submodules.

REPO_ROOT = Path(__file__).resolve().parents[1]

for module_id, path in [
    ("neurocnl", "neurocnl/frontend/build/web"),
    ("neurosim", "neurocnl/frontend/build/web"),
    ("neurochip", "Neurochip/frontend/build/web"),
    ("neurobench", "Neurobench/frontend/build/web"),
    ("neurohub", "Neurohub/frontend/build/web"),
]:
    full_path = REPO_ROOT / path
    if full_path.exists():
        app.mount(
            f"/{module_id}",
            StaticFiles(directory=str(full_path), html=True),
            name=module_id,
        )
