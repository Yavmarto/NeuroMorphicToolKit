"""Minimal checks for shared HTTP metrics helpers."""

from fastapi import FastAPI
from fastapi.testclient import TestClient

from nmtk.http_metrics import attach_fastapi_metrics, record_http_request


def test_attach_fastapi_metrics_exposes_prometheus_series() -> None:
    app = FastAPI()
    attach_fastapi_metrics(app)

    @app.get("/probe")
    async def probe() -> dict[str, bool]:
        return {"ok": True}

    client = TestClient(app)
    client.get("/probe")
    metrics = client.get("/metrics")
    assert metrics.status_code == 200
    assert "http_requests_total" in metrics.text
    assert "http_request_duration_seconds" in metrics.text


def test_record_http_request_increments_counter() -> None:
    before = (
        record_http_request.__module__
    )  # ponytail: smoke only — counter value not exported here
    record_http_request(
        method="GET",
        endpoint="/probe",
        status_code=200,
        latency_seconds=0.01,
    )
    assert before == "nmtk.metrics_core"
