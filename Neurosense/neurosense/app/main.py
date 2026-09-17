import os
from pathlib import Path
from typing import Any

from fastapi import Depends, FastAPI, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.openapi.utils import get_openapi
from fastapi.staticfiles import StaticFiles

from .auth import get_api_key
from .logging_utils import setup_logging
from .routers import (
    devices,
    encoding,
    export,
    nir,
    presets,
    prophesee,
    pynq,
    quality,
    recording,
    sessions,
    stream,
)
from .schemas.runtime import HealthResponse, WelcomeResponse, healthy_response

# Initialize structured logging
setup_logging()

app = FastAPI(
    title="NeuroSense API",
    description="Biosignal Acquisition & Spike Encoding Toolkit",
    version="0.1.0",
)

# CORS configuration — matches pattern used by Neurochip / neurocnl
_allowed_origins_str = os.getenv("ALLOWED_ORIGINS", "*")
_origins: list[str] = [o.strip() for o in _allowed_origins_str.split(",") if o.strip()]
_allow_credentials = "*" not in _origins
app.add_middleware(
    CORSMiddleware,
    allow_origins=_origins,
    allow_credentials=_allow_credentials,
    allow_methods=["*"],
    allow_headers=["*"],
)

import logging as _logging  # noqa: E402

_log = _logging.getLogger("neurosense.api")
if "*" in _origins:
    _log.warning(
        "cors_open_to_all_origins: CORS is open to all origins. Set ALLOWED_ORIGINS for production."
    )


@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception) -> Response:
    """Catch-all handler: log full traceback and return structured JSON 500."""
    import traceback

    from fastapi.responses import JSONResponse

    _log.error("Unhandled exception: %s\n%s", str(exc), traceback.format_exc())
    return JSONResponse(status_code=500, content={"detail": "Internal Server Error"})


app.include_router(
    devices.router,
    prefix="/api/neurosense/devices",
    tags=["Devices"],
    dependencies=[Depends(get_api_key)],
)
app.include_router(
    presets.router,
    prefix="/api/neurosense/presets",
    tags=["Presets"],
    dependencies=[Depends(get_api_key)],
)
app.include_router(
    stream.router,
    prefix="/api/neurosense/stream",
    tags=["Stream"],
    dependencies=[Depends(get_api_key)],
)
app.include_router(
    encoding.router,
    prefix="/api/neurosense/encode",
    tags=["Encoding"],
    dependencies=[Depends(get_api_key)],
)
app.include_router(
    recording.router,
    prefix="/api/neurosense/recording",
    tags=["Recording"],
    dependencies=[Depends(get_api_key)],
)
app.include_router(
    sessions.router,
    prefix="/api/neurosense/sessions",
    tags=["Sessions"],
    dependencies=[Depends(get_api_key)],
)
app.include_router(
    quality.router,
    prefix="/api/neurosense/quality",
    tags=["Quality"],
    dependencies=[Depends(get_api_key)],
)
app.include_router(
    export.router,
    prefix="/api/neurosense/export",
    tags=["Export"],
    dependencies=[Depends(get_api_key)],
)
app.include_router(
    nir.router,
    prefix="/api/neurosense/nir",
    tags=["NIR"],
    dependencies=[Depends(get_api_key)],
)
app.include_router(
    prophesee.router,
    prefix="/api/neurosense/sense/prophesee",
    tags=["Prophesee"],
)
app.include_router(
    pynq.router,
    prefix="/api/neurosense",
    tags=["PYNQ"],
    dependencies=[Depends(get_api_key)],
)


def custom_openapi() -> dict[str, Any]:
    if app.openapi_schema:
        return app.openapi_schema
    openapi_schema = get_openapi(
        title="NeuroSense API",
        version="0.1.0",
        description="Biosignal Acquisition & Spike Encoding Toolkit",
        routes=app.routes,
    )
    openapi_schema.setdefault("components", {})["securitySchemes"] = {
        "APIKeyHeader": {"type": "apiKey", "in": "header", "name": "X-API-Key"},
        "APIKeyQuery": {"type": "apiKey", "in": "query", "name": "api_key"},
    }
    openapi_schema["security"] = [{"APIKeyHeader": []}, {"APIKeyQuery": []}]
    app.openapi_schema = openapi_schema
    return app.openapi_schema


app.openapi = custom_openapi


@app.get("/health", response_model=HealthResponse)
def health(request: Request, response: Response) -> HealthResponse:
    """Health check endpoint."""
    return healthy_response()


# Serve Flutter web frontend at / (must be after all API routes)
_frontend_dir = Path(__file__).resolve().parent.parent.parent / "frontend" / "build" / "web"
if _frontend_dir.is_dir():
    app.mount("/", StaticFiles(directory=str(_frontend_dir), html=True), name="frontend")
else:

    @app.get("/", response_model=WelcomeResponse)
    def read_root(request: Request, response: Response) -> WelcomeResponse:
        return WelcomeResponse(message="Welcome to NeuroSense API")
