"""suite_api — unified NeuroMorphicToolKit backend.

Start with: uvicorn suite_api.main:app --port 9000 --reload
"""

import logging
import traceback
from collections.abc import AsyncGenerator
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles
from starlette.exceptions import HTTPException as StarletteHTTPException

from suite_api.domains.neurocnl.lifespan import neurocnl_shutdown, neurocnl_startup
from suite_api.domains.neurohub.lifespan import neurohub_shutdown, neurohub_startup
from suite_api.errors import error_response
from suite_api.middleware import attach_middleware
from suite_api.routers import health


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncGenerator[None, None]:
    await neurocnl_startup(app)
    await neurohub_startup()
    yield
    await neurohub_shutdown()
    await neurocnl_shutdown()


app = FastAPI(
    title="NeuroMorphicToolKit Suite API",
    version="0.1.0",
    description="Unified backend for the NMTK suite.",
    lifespan=lifespan,
)

attach_middleware(app)

_logger = logging.getLogger("suite_api")


@app.exception_handler(StarletteHTTPException)
async def http_exception_handler(
    request: Request, exc: StarletteHTTPException
) -> JSONResponse:
    """Normalize framework and route errors at the external boundary."""
    code = "not_found" if exc.status_code == 404 else "request_failed"
    message = str(exc.detail) if isinstance(exc.detail, str) else "Request failed."
    retryable = False
    if isinstance(exc.detail, dict):
        candidate_code = exc.detail.get("code")
        candidate_message = exc.detail.get("message")
        if isinstance(candidate_code, str) and candidate_code:
            code = candidate_code
        if isinstance(candidate_message, str) and candidate_message:
            message = candidate_message
        retryable = exc.detail.get("retryable") is True
    return error_response(
        request,
        status_code=exc.status_code,
        code=code,
        message=message,
        retryable=retryable,
    )


@app.exception_handler(RequestValidationError)
async def validation_exception_handler(
    request: Request, _exc: RequestValidationError
) -> JSONResponse:
    """Return a stable validation error without echoing submitted values."""
    return error_response(
        request,
        status_code=422,
        code="invalid_request",
        message="The request did not match the expected schema.",
        retryable=False,
    )


@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception) -> JSONResponse:
    """Catch-all handler: log full traceback and return structured JSON 500."""
    _logger.error("Unhandled exception: %s\n%s", str(exc), traceback.format_exc())
    return error_response(
        request,
        status_code=500,
        code="internal_error",
        message="An internal error occurred.",
        retryable=False,
    )


app.include_router(health.router, prefix="/api/suite", tags=["health"])

from suite_api.domains.neurocnl.router import router as neurocnl_router

app.include_router(neurocnl_router)

from suite_api.domains.neurosim.router import router as neurosim_router

app.include_router(neurosim_router)

from suite_api.domains.neurochip.router import router as neurochip_router

app.include_router(neurochip_router)

from suite_api.domains.neurobench.router import (
    router as neurobench_router,
)

app.include_router(neurobench_router)

from suite_api.domains.neurosense.router import (
    router as neurosense_router,
)

app.include_router(neurosense_router)

from suite_api.domains.neurohub.router import router as neurohub_router

app.include_router(neurohub_router)

from suite_api.domains.jupyter.router import router as jupyter_router

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
