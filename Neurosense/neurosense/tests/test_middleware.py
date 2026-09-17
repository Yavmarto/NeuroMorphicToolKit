import logging

import pytest
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from fastapi.testclient import TestClient

from neurosense.app.middleware import LoggingMiddleware, RequestIdMiddleware

app = FastAPI()
app.add_middleware(LoggingMiddleware)
app.add_middleware(RequestIdMiddleware)


@app.get("/test")
def _test_endpoint(request: Request) -> JSONResponse:
    return JSONResponse({"status": "ok"})


@app.get("/error")
def _error_endpoint(request: Request) -> JSONResponse:
    raise RuntimeError("Test error")


client = TestClient(app)


def test_request_id_middleware() -> None:
    response = client.get("/test")
    assert response.status_code == 200
    assert "x-request-id" in response.headers
    assert response.headers["x-request-id"] is not None


def test_logging_middleware_success(caplog: pytest.LogCaptureFixture) -> None:
    with caplog.at_level(logging.INFO, logger="neurosense.api"):
        response = client.get("/test")
        assert response.status_code == 200

        log_records = caplog.records
        assert len(log_records) > 0
        assert any("Request completed: GET /test 200" in record.message for record in log_records)

        # Verify extra fields are present in the record
        record = next(r for r in log_records if "Request completed: GET /test 200" in r.message)
        assert hasattr(record, "request_id")
        assert hasattr(record, "extra_fields")
        assert record.extra_fields["method"] == "GET"
        assert record.extra_fields["path"] == "/test"
        assert record.extra_fields["status_code"] == 200
        assert "duration_ms" in record.extra_fields


def test_logging_middleware_error(caplog: pytest.LogCaptureFixture) -> None:
    with caplog.at_level(logging.ERROR, logger="neurosense.api"):
        try:
            client.get("/error")
        except RuntimeError:
            pass

        log_records = caplog.records
        assert len(log_records) > 0
        assert any("Request failed: GET /error" in record.message for record in log_records)

        # Verify extra fields are present in the error record
        record = next(r for r in log_records if "Request failed: GET /error" in r.message)
        assert hasattr(record, "request_id")
        assert hasattr(record, "extra_fields")
        assert record.extra_fields["method"] == "GET"
        assert record.extra_fields["path"] == "/error"
        assert record.extra_fields["status_code"] == 500
        assert record.extra_fields["exception"] == "Test error"
        assert "duration_ms" in record.extra_fields
