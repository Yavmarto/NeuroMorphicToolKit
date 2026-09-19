"""FastAPI middleware and route helpers for NMTK HTTP metrics."""

from __future__ import annotations

import time
from collections.abc import Awaitable, Callable

from fastapi import FastAPI, Request, Response
from starlette.middleware.base import BaseHTTPMiddleware, RequestResponseEndpoint

from nmtk.metrics_core import (
    metrics_body,
    metrics_content_type,
    record_http_request,
)


def endpoint_label(request: Request) -> str:
    """Prefer route templates over raw paths to keep cardinality low."""
    route = request.scope.get("route")
    if route is not None and hasattr(route, "path"):
        return str(route.path)
    return request.url.path


class PrometheusMiddleware(BaseHTTPMiddleware):
    async def dispatch(
        self, request: Request, call_next: RequestResponseEndpoint
    ) -> Response:
        method = request.method
        endpoint = endpoint_label(request)
        start = time.perf_counter()
        try:
            response = await call_next(request)
            status_code = response.status_code
        except Exception:
            record_http_request(
                method=method,
                endpoint=endpoint,
                status_code=500,
                latency_seconds=time.perf_counter() - start,
            )
            raise
        record_http_request(
            method=method,
            endpoint=endpoint,
            status_code=status_code,
            latency_seconds=time.perf_counter() - start,
        )
        return response


def metrics_response() -> Response:
    return Response(metrics_body(), media_type=metrics_content_type())


def attach_fastapi_metrics(app: FastAPI) -> None:
    """Add request middleware and a public GET /metrics handler."""
    app.add_middleware(PrometheusMiddleware)

    @app.get("/metrics", include_in_schema=False)
    async def metrics() -> Response:
        return metrics_response()


def wrap_callable(
    call_next: Callable[[Request], Awaitable[Response]],
) -> Callable[[Request], Awaitable[Response]]:
    """Wrap one FastAPI-style middleware chain step with HTTP metrics."""

    async def instrumented(request: Request) -> Response:
        method = request.method
        endpoint = endpoint_label(request)
        start = time.perf_counter()
        try:
            response = await call_next(request)
            status_code = response.status_code
        except Exception:
            record_http_request(
                method=method,
                endpoint=endpoint,
                status_code=500,
                latency_seconds=time.perf_counter() - start,
            )
            raise
        record_http_request(
            method=method,
            endpoint=endpoint,
            status_code=status_code,
            latency_seconds=time.perf_counter() - start,
        )
        return response

    return instrumented
