"""Shared middleware for suite_api.
Attach all middleware through the single attach_middleware() function.
"""
import os
import time
import uuid
import logging

from fastapi import FastAPI, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from starlette.middleware.base import BaseHTTPMiddleware

logger = logging.getLogger("suite_api")


class RequestIdMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next) -> Response:
        # Honour an incoming X-Request-ID so cross-service traces stay correlated.
        request_id = request.headers.get("X-Request-ID", str(uuid.uuid4()))
        request.state.request_id = request_id
        response = await call_next(request)
        response.headers["X-Request-Id"] = request_id
        return response


class ResponseTimeMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next) -> Response:
        start = time.perf_counter()
        response = await call_next(request)
        elapsed_ms = (time.perf_counter() - start) * 1000
        response.headers["X-Response-Time-Ms"] = f"{elapsed_ms:.2f}"
        return response


def attach_middleware(app: FastAPI) -> None:
    # CORS — read from env var so production can lock this down.
    # allow_credentials=True is incompatible with allow_origins=["*"] per the
    # CORS spec; Starlette silently drops credentials when origins is a wildcard,
    # so we only enable it when specific origins are configured.
    _allowed_origins_str = os.getenv("ALLOWED_ORIGINS", "*")
    _origins = [o.strip() for o in _allowed_origins_str.split(",") if o.strip()]
    _allow_credentials = "*" not in _origins
    if "*" in _origins:
        logger.warning(
            "cors_open_to_all_origins: CORS is open to all origins. "
            "Set ALLOWED_ORIGINS for production."
        )
    app.add_middleware(
        CORSMiddleware,
        allow_origins=_origins,
        allow_credentials=_allow_credentials,
        allow_methods=["*"],
        allow_headers=["*"],
    )
    app.add_middleware(RequestIdMiddleware)
    app.add_middleware(ResponseTimeMiddleware)
