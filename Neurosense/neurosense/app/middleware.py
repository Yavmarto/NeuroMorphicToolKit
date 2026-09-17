import logging
import time
import uuid

from fastapi import Request, Response
from starlette.middleware.base import BaseHTTPMiddleware, RequestResponseEndpoint

logger = logging.getLogger("neurosense.api")


class RequestIdMiddleware(BaseHTTPMiddleware):
    """Middleware to add a unique request ID to each request."""

    async def dispatch(self, request: Request, call_next: RequestResponseEndpoint) -> Response:
        # Honour an incoming X-Request-ID so cross-service traces stay correlated.
        request_id = request.headers.get("X-Request-ID", str(uuid.uuid4()))
        # We store it in scope so it's accessible in LoggingMiddleware
        request.scope["request_id"] = request_id

        # Also store it in request.state for convenience in other parts of the app
        request.state.request_id = request_id

        response = await call_next(request)
        response.headers["X-Request-ID"] = request_id
        return response


class LoggingMiddleware(BaseHTTPMiddleware):
    """Middleware to log API requests with structured information."""

    async def dispatch(self, request: Request, call_next: RequestResponseEndpoint) -> Response:
        start_time = time.perf_counter()
        # Get request_id directly from the scope we just set in RequestIdMiddleware
        request_id = request.scope.get("request_id", "unknown")

        # Create a local copy of the logger to pass the request_id easily
        # or use a LoggerAdapter if needed. For now, let's stick to 'extra'.

        try:
            response = await call_next(request)
        except Exception as exc:
            duration = (time.perf_counter() - start_time) * 1000
            logger.error(
                f"Request failed: {request.method} {request.url.path}",
                extra={
                    "request_id": request_id,
                    "extra_fields": {
                        "method": request.method,
                        "path": request.url.path,
                        "status_code": 500,
                        "duration_ms": round(duration, 2),
                        "exception": str(exc),
                    },
                },
            )
            raise exc

        duration = (time.perf_counter() - start_time) * 1000
        logger.info(
            f"Request completed: {request.method} {request.url.path} {response.status_code}",
            extra={
                "request_id": request_id,
                "extra_fields": {
                    "method": request.method,
                    "path": request.url.path,
                    "status_code": response.status_code,
                    "duration_ms": round(duration, 2),
                },
            },
        )
        return response
