"""Tests for Prometheus metrics endpoint and application-level metrics."""

from fastapi.testclient import TestClient

from backend.app.main import app

client = TestClient(app)


def test_metrics_endpoint_returns_prometheus_format():
    """GET /metrics returns Prometheus text format."""
    resp = client.get("/metrics")
    assert resp.status_code == 200
    assert "text/plain" in resp.headers["content-type"]
    # Standard HTTP metric should always be present
    assert "http_requests_total" in resp.text


def test_metrics_contain_job_metric_names():
    """Job-related metric names are registered at import time."""
    resp = client.get("/metrics")
    body = resp.text
    # Gauge and counter families should be declared even before any jobs run
    assert "neurocnl_job_queue_depth" in body
    assert "neurocnl_job_active_tasks" in body
    assert "neurocnl_job_completions_total" in body
    assert "neurocnl_job_duration_seconds" in body


def test_metrics_contain_deploy_verdict_name():
    """Deploy verdict counter family is registered."""
    resp = client.get("/metrics")
    assert "neurocnl_deploy_verdicts_total" in resp.text
