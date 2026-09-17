import pytest
from fastapi.testclient import TestClient

from neurosim.app.main import app


@pytest.fixture
def client() -> TestClient:
    # Provide a clear client environment to avoid cross-test limiter contamination
    return TestClient(app)


def test_rate_limiting_read_endpoints(client: TestClient) -> None:
    # Test a read endpoint (60/minute limit)
    # We will mock the client IP to ensure a fresh bucket
    app.state.limiter.reset()

    # 60 successful requests
    for _i in range(60):
        response = client.get("/health", headers={"X-Forwarded-For": "198.51.100.1"})
        assert response.status_code == 200

    # 61st should be rate limited
    response = client.get("/health", headers={"X-Forwarded-For": "198.51.100.1"})
    assert response.status_code == 429
    assert "Rate limit exceeded: 60 per 1 minute" in response.json().get("error", "")


def test_rate_limiting_simulation_endpoints(client: TestClient) -> None:
    # Test a simulation endpoint (20/minute limit)
    app.state.limiter.reset()

    # 20 successful requests (or at least 404/422 if invalid, but not 429)
    for _i in range(20):
        # We can hit a GET endpoint for ease
        response = client.get(
            "/api/neurosim/simulations/dummy_job",
            headers={"X-Forwarded-For": "198.51.100.2"},
        )
        assert response.status_code != 429

    # 21st should be rate limited
    response = client.get(
        "/api/neurosim/simulations/dummy_job",
        headers={"X-Forwarded-For": "198.51.100.2"},
    )
    assert response.status_code == 429
    assert "Rate limit exceeded: 20 per 1 minute" in response.json().get("error", "")


def test_preview_rate_limiting(client: TestClient) -> None:
    """Confirm that the 21st request to /preview within one minute receives HTTP 429."""
    app.state.limiter.reset()
    test_ip = "198.51.100.4"
    payload = {"graph": {"nodes": [], "edges": []}, "duration_ms": 1.0}

    # 20 successful requests
    for _ in range(20):
        response = client.post(
            "/api/neurosim/preview", json=payload, headers={"X-Forwarded-For": test_ip}
        )
        assert response.status_code == 200

    # 21st should be rate limited
    response = client.post(
        "/api/neurosim/preview", json=payload, headers={"X-Forwarded-For": test_ip}
    )
    assert response.status_code == 429
    assert "Rate limit exceeded: 20 per 1 minute" in response.json().get("error", "")

    # Confirm standard rate-limit headers
    assert "X-RateLimit-Limit" in response.headers or "Retry-After" in response.headers
    if "X-RateLimit-Limit" in response.headers:
        assert response.headers["X-RateLimit-Limit"] == "20"


def test_rate_limit_headers(client: TestClient) -> None:
    app.state.limiter.reset()
    response = client.get("/health", headers={"X-Forwarded-For": "198.51.100.3"})
    assert response.status_code == 200
    assert "X-RateLimit-Limit" in response.headers
    assert "X-RateLimit-Remaining" in response.headers
