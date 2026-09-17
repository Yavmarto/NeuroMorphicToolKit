"""Prometheus HTTP metric series shared by all NMTK services."""

from __future__ import annotations

from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest

HTTP_REQUEST_COUNT = Counter(
    "http_requests_total",
    "Total number of HTTP requests",
    ["method", "endpoint", "status_code"],
)

HTTP_REQUEST_LATENCY = Histogram(
    "http_request_duration_seconds",
    "HTTP request latency in seconds",
    ["method", "endpoint"],
    buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0),
)


def record_http_request(
    *,
    method: str,
    endpoint: str,
    status_code: int,
    latency_seconds: float,
) -> None:
    HTTP_REQUEST_COUNT.labels(
        method=method, endpoint=endpoint, status_code=str(status_code)
    ).inc()
    HTTP_REQUEST_LATENCY.labels(method=method, endpoint=endpoint).observe(
        latency_seconds
    )


def metrics_body() -> bytes:
    return generate_latest()


def metrics_content_type() -> str:
    return CONTENT_TYPE_LATEST
