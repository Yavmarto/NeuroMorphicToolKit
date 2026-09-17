"""Main entry point for the NeuroChip FastAPI application.

This module initializes the FastAPI application, sets up metadata (title,
description, version), defines a basic health check endpoint, and includes
all the domain-specific routers.
"""

import logging
import os
import time
import uuid
from collections.abc import AsyncIterator, Awaitable, Callable
from contextlib import asynccontextmanager
from pathlib import Path
from types import ModuleType

from fastapi import Depends, FastAPI, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from .auth import AUTH_ENABLED, validate_startup_auth_config, verify_api_key
from .routers import (
    akida,
    analysis,
    deployments,
    estimation,
    export,
    faults,
    hardware,
    pynq,
    quantization,
    serial,
    speck,
    targets,
)
from .schemas.health import HealthResponse, healthy_response

lava: ModuleType | None
try:
    from .routers import lava
except ImportError:
    lava = None

spinnaker2: ModuleType | None
try:
    from .routers import spinnaker2
except ImportError:
    spinnaker2 = None

logging.basicConfig(
    level=logging.INFO,
    format='{"timestamp": "%(asctime)s", "level": "%(levelname)s", "logger": "%(name)s", "message": "%(message)s"}',
)
logger = logging.getLogger("neurochip")


@asynccontextmanager
async def lifespan(_app: FastAPI) -> AsyncIterator[None]:
    """Application lifespan: validate startup config and log router availability."""
    validate_startup_auth_config()
    logger.info(
        "mounted_routers=%s lava_router_available=%s spinnaker2_router_available=%s",
        ",".join(_mounted_router_names),
        lava is not None,
        spinnaker2 is not None,
    )
    if "*" in _origins:
        logger.warning(
            "cors_open_to_all_origins: CORS is open to all origins. "
            "Set ALLOWED_ORIGINS for production."
        )
    if not AUTH_ENABLED:
        logger.warning(
            "auth_disabled: API key auth is disabled. "
            "Set NEUROCHIP_AUTH_ENABLED=true for production."
        )
    yield


app = FastAPI(
    title="NeuroChip API",
    description="Hardware Deployment & Compilation Toolkit",
    version="0.1.0",
    lifespan=lifespan,
)


@app.middleware("http")
async def add_request_id_and_log_request(
    request: Request,
    call_next: Callable[[Request], Awaitable[Response]],
) -> Response:
    request_id = str(uuid.uuid4())
    request.state.request_id = request_id
    start_time = time.time()

    response = await call_next(request)

    process_time = time.time() - start_time
    response.headers["X-Request-ID"] = request_id

    logger.info(
        "request_id=%s method=%s path=%s status=%s duration=%.4fs",
        request_id,
        request.method,
        request.url.path,
        response.status_code,
        process_time,
    )

    return response


# CORS configuration — default is loopback-only; set ALLOWED_ORIGINS for broader access.
_DEFAULT_ORIGINS = (
    "http://localhost,"
    "http://localhost:8000,"
    "http://localhost:3000,"
    "http://localhost:5173,"
    "http://127.0.0.1,"
    "http://127.0.0.1:8000,"
    "http://127.0.0.1:3000,"
    "http://127.0.0.1:5173"
)
_allowed_origins_str = os.getenv("ALLOWED_ORIGINS", _DEFAULT_ORIGINS)
_origins: list[str] = [
    origin.strip() for origin in _allowed_origins_str.split(",") if origin.strip()
]

# Starlette prevents allow_credentials=True if allow_origins=["*"]
allow_credentials = "*" not in _origins

if _origins:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=_origins,
        allow_credentials=allow_credentials,
        allow_methods=["*"],
        allow_headers=["*"],
    )
# Production-safety warnings are emitted during lifespan startup (see lifespan() above).


@app.get("/health", response_model=HealthResponse)
def health_check() -> HealthResponse:
    """Health check endpoint to verify API status.

    Returns:
        HealthResponse: Structured payload with the service status.
    """
    return healthy_response(status="healthy")


@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception) -> Response:
    """Catch-all handler: log full traceback and return structured JSON 500."""
    import traceback

    from fastapi.responses import JSONResponse

    logger.error("Unhandled exception: %s\n%s", str(exc), traceback.format_exc())
    return JSONResponse(status_code=500, content={"detail": "Internal Server Error"})


app.include_router(targets.router, dependencies=[Depends(verify_api_key)])
app.include_router(analysis.router, dependencies=[Depends(verify_api_key)])
app.include_router(quantization.router, dependencies=[Depends(verify_api_key)])
app.include_router(faults.router, dependencies=[Depends(verify_api_key)])
app.include_router(estimation.router, dependencies=[Depends(verify_api_key)])
app.include_router(export.router, dependencies=[Depends(verify_api_key)])
app.include_router(serial.router, dependencies=[Depends(verify_api_key)])
app.include_router(deployments.router, dependencies=[Depends(verify_api_key)])
app.include_router(pynq.router, dependencies=[Depends(verify_api_key)])
app.include_router(akida.router, dependencies=[Depends(verify_api_key)])
app.include_router(speck.router, dependencies=[Depends(verify_api_key)])
app.include_router(hardware.router, dependencies=[Depends(verify_api_key)])
if lava is not None:
    app.include_router(lava.router, dependencies=[Depends(verify_api_key)])
if spinnaker2 is not None:
    app.include_router(spinnaker2.router, dependencies=[Depends(verify_api_key)])

_mounted_router_names = [
    "targets",
    "analysis",
    "quantization",
    "faults",
    "estimation",
    "export",
    "serial",
    "deployments",
    "pynq",
    "akida",
    "speck",
    "hardware",
]
if lava is not None:
    _mounted_router_names.append("lava")
if spinnaker2 is not None:
    _mounted_router_names.append("spinnaker2")

# Serve Flutter web frontend at / (must be after all API routes)
_frontend_dir = Path(__file__).resolve().parent.parent.parent / "frontend" / "build" / "web"
if _frontend_dir.is_dir():
    app.mount("/", StaticFiles(directory=str(_frontend_dir), html=True), name="frontend")
