"""API Key authentication middleware."""

import hmac
import os

from starlette.middleware.base import BaseHTTPMiddleware, RequestResponseEndpoint
from starlette.requests import Request
from starlette.responses import JSONResponse, Response


class APIKeyMiddleware(BaseHTTPMiddleware):
    """Middleware that validates an API key in the X-API-Key header."""

    async def dispatch(self, request: Request, call_next: RequestResponseEndpoint) -> Response:
        # Only apply to /api/ routes
        if not request.url.path.startswith("/api"):
            return await call_next(request)

        # Check if auth is enabled
        auth_enabled = os.getenv("AUTH_ENABLED", "false").lower() == "true"
        if not auth_enabled:
            return await call_next(request)

        # Validate API key
        expected_key = os.getenv("API_KEY")
        if not expected_key:
            # If auth is enabled but no key is configured, deny all for safety
            return JSONResponse(
                status_code=500,
                content={
                    "detail": "API authentication is enabled but no API_KEY is configured on the server."
                },
            )

        api_key = request.headers.get("X-API-Key")
        if not api_key or not hmac.compare_digest(api_key.encode(), expected_key.encode()):
            return JSONResponse(
                status_code=401,
                content={"detail": "Invalid or missing API key."},
            )

        return await call_next(request)
