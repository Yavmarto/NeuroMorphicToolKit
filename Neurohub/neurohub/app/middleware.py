import logging
import time
import uuid
from collections.abc import Awaitable, Callable

from fastapi import Request, Response
from starlette.middleware.base import BaseHTTPMiddleware

logger = logging.getLogger(__name__)


class RequestIdMiddleware(BaseHTTPMiddleware):
    """Middleware to add a unique request ID to each request and response."""

    async def dispatch(
        self, request: Request, call_next: Callable[[Request], Awaitable[Response]]
    ) -> Response:
        """Add request ID to headers and state.

        Args:
            request: The incoming FastAPI request.
            call_next: The next handler in the middleware chain.

        Returns:
            Response: The FastAPI response.
        """
        request_id = request.headers.get("X-Request-ID", str(uuid.uuid4()))
        request.state.request_id = request_id
        response = await call_next(request)
        response.headers["X-Request-ID"] = request_id
        return response


class LoggingMiddleware(BaseHTTPMiddleware):
    """Middleware to log details of every request and response."""

    async def dispatch(
        self, request: Request, call_next: Callable[[Request], Awaitable[Response]]
    ) -> Response:
        """Log request method, path, status code, and duration.

        Args:
            request: The incoming FastAPI request.
            call_next: The next handler in the middleware chain.

        Returns:
            Response: The FastAPI response.
        """
        request_id = getattr(request.state, "request_id", None)
        start_time = time.time()

        try:
            response = await call_next(request)
            duration = time.time() - start_time

            logger.info(
                "%s %s - %s",
                request.method,
                request.url.path,
                response.status_code,
                extra={
                    "request_id": request_id,
                    "method": request.method,
                    "path": request.url.path,
                    "status_code": response.status_code,
                    "duration_seconds": round(duration, 4),
                },
            )
            return response

        except Exception as e:
            duration = time.time() - start_time
            logger.error(
                "Request failed: %s %s - %s",
                request.method,
                request.url.path,
                type(e).__name__,
                extra={
                    "request_id": request_id,
                    "method": request.method,
                    "path": request.url.path,
                    "duration_seconds": round(duration, 4),
                    "error": str(e),
                },
            )
            raise


class SecurityHeadersMiddleware(BaseHTTPMiddleware):
    """Attach OWASP-recommended security headers to every HTTP response.

    Headers applied:
    - ``Strict-Transport-Security``: HSTS with 1-year max-age and subdomains.
    - ``X-Content-Type-Options``: Prevents MIME-type sniffing.
    - ``X-Frame-Options``: Blocks clickjacking via iframe embedding.
    - ``Referrer-Policy``: Limits referrer leakage to same-origin.
    - ``Permissions-Policy``: Disables unused browser features.
    """

    async def dispatch(
        self,
        request: Request,
        call_next: Callable[[Request], Awaitable[Response]],
    ) -> Response:
        """Process the request and attach security headers to the response.

        Args:
            request: The incoming HTTP request.
            call_next: The next middleware or route handler.

        Returns:
            The response with security headers attached.
        """
        response = await call_next(request)
        response.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["X-Frame-Options"] = "DENY"
        response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
        response.headers["Permissions-Policy"] = (
            "geolocation=(), camera=(), microphone=(), payment=()"
        )
        return response
