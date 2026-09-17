"""Minimal board-side FastAPI application for the PYNQ runtime agent."""

from __future__ import annotations

import logging
import os
import time
import uuid
from collections.abc import Awaitable, Callable
from pathlib import Path
from typing import cast

import uvicorn
from fastapi import Depends, FastAPI, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from slowapi import _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from slowapi.middleware import SlowAPIMiddleware

from .auth import verify_api_key
from .limiter import limiter
from .routers import pynq

logging.basicConfig(
    level=logging.INFO,
    format='{"timestamp": "%(asctime)s", "level": "%(levelname)s", "logger": "%(name)s", "message": "%(message)s"}',
)
logger = logging.getLogger("neurochip-pynq-agent")


def _handle_rate_limit_exceeded(request: Request, exc: Exception) -> Response:
    return _rate_limit_exceeded_handler(request, cast(RateLimitExceeded, exc))


def create_app() -> FastAPI:
    """Create the minimal PYNQ runtime application."""
    app = FastAPI(
        title="NeuroChip PYNQ Agent",
        description="Minimal board-side PYNQ runtime agent",
        version="0.1.0",
    )
    app.state.limiter = limiter
    app.state.RATELIMIT_HEADERS_ENABLED = True
    app.add_exception_handler(RateLimitExceeded, _handle_rate_limit_exceeded)

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

    app.add_middleware(SlowAPIMiddleware)

    allowed_origins = [
        origin.strip() for origin in os.getenv("ALLOWED_ORIGINS", "*").split(",") if origin.strip()
    ]
    allow_credentials = "*" not in allowed_origins

    if allowed_origins:
        app.add_middleware(
            CORSMiddleware,
            allow_origins=allowed_origins,
            allow_credentials=allow_credentials,
            allow_methods=["*"],
            allow_headers=["*"],
        )

    @app.get("/health")
    def health_check() -> dict[str, str]:
        return {"status": "healthy"}

    app.include_router(pynq.router, dependencies=[Depends(verify_api_key)])

    return app


app = create_app()


def main() -> None:
    """Run the minimal PYNQ agent via uvicorn."""
    host = os.getenv("NEUROCHIP_PYNQ_AGENT_HOST", "0.0.0.0")
    port = int(os.getenv("NEUROCHIP_PYNQ_AGENT_PORT", "8002"))
    uvicorn.run(
        "neurochip.app.pynq_agent:app",
        host=host,
        port=port,
        reload=False,
    )


def canonical_overlay_dir() -> Path:
    """Expose the canonical overlay directory for provisioning helpers."""
    return Path(__file__).resolve().parents[1] / "overlays"
