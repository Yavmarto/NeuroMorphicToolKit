"""Shared middleware for suite_api.
Attach all middleware through the single attach_middleware() function.
"""

import hmac
import logging
import os
import time
import uuid
from pathlib import Path

from fastapi import FastAPI, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from starlette.datastructures import Headers
from starlette.middleware.base import RequestResponseEndpoint
from starlette.types import ASGIApp, Receive, Scope, Send

from suite_api.errors import error_response

logger = logging.getLogger("suite_api")

_ADMIN_HEADER = "X-NMTK-Admin-Token"
_ADMIN_COOKIE = "nmtk_admin_session"


def _load_admin_token() -> str:
    secret_file = os.getenv("NMTK_ADMIN_TOKEN_FILE", "").strip()
    if secret_file:
        try:
            return Path(secret_file).read_text(encoding="utf-8").strip()
        except OSError:
            logger.exception("admin_token_file_unreadable")
            return ""
    return os.getenv("NMTK_ADMIN_TOKEN", "").strip()


def admin_token_valid(provided: str) -> bool:
    """Validate one supplied administrator credential in constant time."""
    expected = _load_admin_token()
    return bool(expected and provided and hmac.compare_digest(provided, expected))


def _bearer_token(headers: Headers) -> str:
    authorization = headers.get("authorization", "").strip()
    scheme, _, credential = authorization.partition(" ")
    return credential.strip() if scheme.lower() == "bearer" else ""


class _AdminWebSocketMiddleware:
    def __init__(self, app: ASGIApp) -> None:
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        required = os.getenv("NMTK_AUTH_REQUIRED", "").strip().lower() in {
            "1",
            "true",
            "yes",
        }
        if scope["type"] == "websocket" and required:
            headers = Headers(scope=scope)
            cookie_token = ""
            for item in headers.get("cookie", "").split(";"):
                name, _, value = item.strip().partition("=")
                if name == _ADMIN_COOKIE:
                    cookie_token = value
                    break
            provided = (
                headers.get(_ADMIN_HEADER, "") or _bearer_token(headers) or cookie_token
            )
            if not admin_token_valid(provided):
                await send(
                    {
                        "type": "websocket.close",
                        "code": 4401,
                        "reason": "Administrator authentication required",
                    }
                )
                return
        await self.app(scope, receive, send)


def attach_middleware(app: FastAPI) -> None:
    app.add_middleware(_AdminWebSocketMiddleware)
    # CORS — read from env var so production can lock this down.
    # allow_credentials=True is incompatible with allow_origins=["*"] per the
    # CORS spec; Starlette silently drops credentials when origins is a wildcard,
    # so we only enable it when specific origins are configured.
    _allowed_origins_str = os.getenv(
        "ALLOWED_ORIGINS",
        "",
    )
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
        allow_headers=[
            "Accept",
            "Authorization",
            "Content-Type",
            "X-NMTK-Admin-Token",
            "X-Request-ID",
        ],
    )

    @app.middleware("http")
    async def admin_auth_middleware(
        request: Request, call_next: RequestResponseEndpoint
    ) -> Response:
        protected = (
            request.url.path != "/api/suite/health" and request.method != "OPTIONS"
        )
        required = os.getenv("NMTK_AUTH_REQUIRED", "").strip().lower() in {
            "1",
            "true",
            "yes",
        }
        if not required:
            return await call_next(request)
        expected = _load_admin_token()
        header_token = request.headers.get(_ADMIN_HEADER, "")
        bearer_token = _bearer_token(request.headers)
        request_token = header_token or bearer_token
        provided = request_token or request.cookies.get(_ADMIN_COOKIE, "")
        if protected and (
            not expected or not provided or not admin_token_valid(provided)
        ):
            return error_response(
                request,
                status_code=401,
                code="unauthorized",
                message="Administrator authentication required.",
                retryable=False,
            )
        response = await call_next(request)
        if request_token and expected and hmac.compare_digest(request_token, expected):
            response.set_cookie(
                _ADMIN_COOKIE,
                expected,
                httponly=True,
                samesite="strict",
                path="/",
            )
        return response

    @app.middleware("http")
    async def request_id_middleware(
        request: Request, call_next: RequestResponseEndpoint
    ) -> Response:
        # Honour an incoming X-Request-ID so cross-service traces stay correlated.
        request_id = request.headers.get("X-Request-ID", str(uuid.uuid4()))
        request.state.request_id = request_id
        response = await call_next(request)
        response.headers["X-Request-Id"] = request_id
        return response

    @app.middleware("http")
    async def response_time_middleware(
        request: Request, call_next: RequestResponseEndpoint
    ) -> Response:
        start = time.perf_counter()
        response = await call_next(request)
        elapsed_ms = (time.perf_counter() - start) * 1000
        response.headers["X-Response-Time-Ms"] = f"{elapsed_ms:.2f}"
        return response
