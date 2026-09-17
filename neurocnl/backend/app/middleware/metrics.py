import time

from prometheus_client import Counter, Histogram
from starlette.middleware.base import BaseHTTPMiddleware, RequestResponseEndpoint
from starlette.requests import Request
from starlette.responses import Response

# Define metrics
HTTP_REQUEST_COUNT = Counter(
    "http_requests_total",
    "Total number of HTTP requests",
    ["method", "endpoint", "status_code"],
)

HTTP_REQUEST_LATENCY = Histogram(
    "http_request_duration_seconds",
    "HTTP request latency in seconds",
    ["method", "endpoint"],
)


class PrometheusMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next: RequestResponseEndpoint) -> Response:
        method = request.method

        # Use route path template if available to keep cardinality low
        # e.g., /api/jobs/{job_id} instead of /api/jobs/uuid
        route = request.scope.get("route")
        if route and hasattr(route, "path"):
            endpoint = route.path
        else:
            endpoint = request.url.path

        start_time = time.perf_counter()

        try:
            response = await call_next(request)
            status_code = response.status_code
        except Exception:
            # If an exception occurs, we don't have a status code yet,
            # but we should still record the request count (likely 500)
            HTTP_REQUEST_COUNT.labels(method=method, endpoint=endpoint, status_code=500).inc()
            raise
        finally:
            latency = time.perf_counter() - start_time
            HTTP_REQUEST_LATENCY.labels(method=method, endpoint=endpoint).observe(latency)

        HTTP_REQUEST_COUNT.labels(method=method, endpoint=endpoint, status_code=status_code).inc()

        return response
