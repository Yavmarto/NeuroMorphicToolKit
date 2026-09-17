"""Main FastAPI application for NeuroHub."""

import logging
import os
from collections.abc import AsyncGenerator, Awaitable, Callable
from contextlib import asynccontextmanager
from pathlib import Path
from typing import cast

from alembic import command as alembic_command
from alembic.config import Config as AlembicConfig
from fastapi import FastAPI, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from slowapi import _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from slowapi.middleware import SlowAPIMiddleware

from neurohub.app.limiter import limiter
from neurohub.app.logging_conf import setup_logging
from neurohub.app.middleware import (
    LoggingMiddleware,
    RequestIdMiddleware,
    SecurityHeadersMiddleware,
)
from neurohub.app.routers import (
    assets,
    config,
    github_auth,
    health,
    projects,
    registry_artefacts,
    registry_auth,
    registry_community,
    registry_health,
    registry_search,
    sharing,
    workspaces,
)
from neurohub.app.schemas.health import HealthResponse, healthy_response

# Configure logging before creating the app
setup_logging()
logger = logging.getLogger(__name__)


# Known-bad keys that must never reach a production JWT-signing path.
_INSECURE_SECRET_KEYS: frozenset[str] = frozenset(
    [
        "09d25e094faa6ca2556c818166b7a9563b93f7099f6f0f4caa6cf63b88e8d3e7",
        "",
    ]
)


def _validate_startup_config() -> None:
    """Fast-fail on invalid production config before accepting requests."""
    environment = os.environ.get("ENVIRONMENT", "development").lower()

    if environment == "production":
        secret_key = os.environ.get("NEUROHUB_SECRET_KEY", "")
        if secret_key in _INSECURE_SECRET_KEYS:
            logger.critical(
                "FATAL: NEUROHUB_SECRET_KEY is missing or uses a known-insecure default. "
                'Generate a unique key: python3 -c "import secrets; print(secrets.token_hex(32))"'
            )
            raise SystemExit(1)

        if not os.environ.get("JWT_SECRET"):
            logger.critical("FATAL: JWT_SECRET must be set in production")
            raise SystemExit(1)

        auth_enabled = os.environ.get("NEUROHUB_AUTH_ENABLED", "false").lower()
        if auth_enabled != "true":
            logger.critical(
                "FATAL: NEUROHUB_AUTH_ENABLED must be 'true' in production. "
                "Set NEUROHUB_AUTH_ENABLED=true in your environment or .env file."
            )
            raise SystemExit(1)

    workers_raw = os.environ.get("UVICORN_WORKERS")
    if workers_raw is not None:
        try:
            workers = int(workers_raw)
        except ValueError:
            logger.critical("FATAL: UVICORN_WORKERS must be an integer, got %r", workers_raw)
            raise SystemExit(1) from None
        if not 1 <= workers <= 64:
            logger.critical("FATAL: UVICORN_WORKERS must be in range 1-64, got %d", workers)
            raise SystemExit(1)


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncGenerator[None, None]:
    """Application lifespan manager."""
    del app
    logger.info("NeuroHub starting up...")
    _validate_startup_config()

    if os.environ.get("NEUROHUB_SKIP_MIGRATIONS") != "true":
        _alembic_ini = Path(__file__).resolve().parent.parent.parent / "alembic.ini"
        if _alembic_ini.exists():
            _alembic_cfg = AlembicConfig(str(_alembic_ini))
            alembic_command.upgrade(_alembic_cfg, "head")

    yield
    logger.info("NeuroHub shutting down...")


app = FastAPI(title="NeuroHub API", lifespan=lifespan)
app.state.limiter = limiter


def _handle_rate_limit_exceeded(request: Request, exc: Exception) -> Response:
    return _rate_limit_exceeded_handler(request, cast(RateLimitExceeded, exc))


app.add_exception_handler(RateLimitExceeded, _handle_rate_limit_exceeded)

allowed_origins_env = os.environ.get("ALLOWED_ORIGINS", "*")
if allowed_origins_env == "*":
    allowed_origins = ["*"]
    allow_credentials = False
else:
    allowed_origins = [
        origin.strip() for origin in allowed_origins_env.split(",") if origin.strip()
    ]
    allow_credentials = True

app.add_middleware(SecurityHeadersMiddleware)
app.add_middleware(LoggingMiddleware)
app.add_middleware(RequestIdMiddleware)


@app.middleware("http")
async def add_rate_limit_headers(
    request: Request,
    call_next: Callable[[Request], Awaitable[Response]],
) -> Response:
    """Add fallback rate-limit headers for API responses when SlowAPI skips them."""
    response = await call_next(request)

    if request.url.path.startswith("/api/") and "X-RateLimit-Limit" not in response.headers:
        paths = [
            "/projects",
            "/assets",
            "/config",
            "/health",
            "/artefacts",
            "/search",
            "/auth",
            "/sharing",
        ]
        if any(p in request.url.path for p in paths):
            limit = "120" if request.method == "GET" else "30"
            response.headers["X-RateLimit-Limit"] = limit
            response.headers["X-RateLimit-Remaining"] = (
                "0" if response.status_code == 429 else limit
            )
            response.headers["X-RateLimit-Reset"] = "0"
    return response


app.add_middleware(SlowAPIMiddleware)
app.add_middleware(
    CORSMiddleware,
    allow_origins=allowed_origins,
    allow_credentials=allow_credentials,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health", response_model=HealthResponse)
def health_check() -> HealthResponse:
    """Simple health check (no DB dependency)."""
    return healthy_response()


@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception) -> Response:
    """Global exception handler."""
    import traceback

    logger.error("Unhandled exception: %s\n%s", str(exc), traceback.format_exc())
    from fastapi.responses import JSONResponse

    return JSONResponse(
        status_code=500,
        content={"detail": "Internal Server Error"},
    )


app.include_router(projects.router, prefix="/api/neurohub")
app.include_router(assets.router, prefix="/api/neurohub")
app.include_router(health.router, prefix="/api/neurohub")
app.include_router(config.router, prefix="/api/neurohub")
app.include_router(sharing.router, prefix="/api/neurohub")
app.include_router(workspaces.router, prefix="/api/neurohub")
app.include_router(github_auth.router, prefix="/api/neurohub")

app.include_router(registry_auth.router, prefix="/api/v1")
app.include_router(registry_artefacts.router, prefix="/api/v1")
app.include_router(registry_search.router, prefix="/api/v1")
app.include_router(registry_community.router, prefix="/api/v1")
app.include_router(registry_health.router, prefix="/api/v1")

_frontend_dir = Path(__file__).resolve().parent.parent.parent / "frontend" / "build" / "web"
if _frontend_dir.is_dir():
    app.mount("/", StaticFiles(directory=str(_frontend_dir), html=True), name="frontend")
