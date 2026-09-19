"""Tests for suite_api /metrics exposure."""

from fastapi.testclient import TestClient

from suite_api.main import app


def test_metrics_endpoint_returns_prometheus_format() -> None:
    client = TestClient(app)
    response = client.get("/metrics")
    assert response.status_code == 200
    assert response.headers["content-type"].startswith("text/plain")
    assert "http_requests_total" in response.text


def test_metrics_records_request_after_health_probe() -> None:
    client = TestClient(app)
    client.get("/api/suite/health")
    metrics = client.get("/metrics").text
    assert 'endpoint="/api/suite/health"' in metrics or "/api/suite/health" in metrics
