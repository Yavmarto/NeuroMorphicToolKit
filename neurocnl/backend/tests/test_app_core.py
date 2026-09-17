"""Tests for core application features (health, middleware)."""

from fastapi.testclient import TestClient

from backend.app.main import app

client = TestClient(app)


def test_health_endpoint():
    """Test the /health endpoint returns expected fields."""
    resp = client.get("/health")
    assert resp.status_code == 200
    data = resp.json()
    assert data["status"] == "ok"
    assert "neurocnl_version" in data
    assert "timestamp" in data
    # Optional components
    assert "nengo_version" in data or data["status"] == "degraded"


def test_request_id_middleware():
    """Test that every response includes an X-Request-ID header."""
    resp = client.get("/health")
    assert "X-Request-ID" in resp.headers
    request_id = resp.headers["X-Request-ID"]
    assert len(request_id) > 0


def test_cors_headers():
    """Test that CORS headers are present when Origin is sent."""
    resp = client.options(
        "/health",
        headers={
            "Origin": "http://localhost:3000",
            "Access-Control-Request-Method": "GET",
        },
    )
    assert resp.status_code == 200
    # When allow_credentials=False for "*", Starlette returns '*'
    assert resp.headers.get("access-control-allow-origin") == "*"
