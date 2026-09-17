from fastapi.testclient import TestClient

from app.config import settings
from app.main import app

client = TestClient(app)


def test_health_check_always_accessible() -> None:
    """Health check should be accessible even without auth."""
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_benchmarks_accessible_when_auth_disabled() -> None:
    """Endpoints should be accessible when NB_AUTH_ENABLED is False."""
    settings.auth_enabled = False
    response = client.get("/api/neurobench/benchmarks")
    assert response.status_code == 200


def test_benchmarks_protected_when_auth_enabled() -> None:
    """Endpoints should return 403 when auth is enabled and no API key is provided."""
    settings.auth_enabled = True
    response = client.get("/api/neurobench/benchmarks")
    # FastAPI returns 403 when the auth dependency rejects the request.
    assert response.status_code == 403


def test_benchmarks_accessible_with_valid_key() -> None:
    """Endpoints should be accessible when valid API key is provided."""
    settings.auth_enabled = True
    settings.api_key = "test-secret-key"
    response = client.get("/api/neurobench/benchmarks", headers={"X-API-Key": "test-secret-key"})
    assert response.status_code == 200


def test_benchmarks_rejected_with_invalid_key() -> None:
    """Endpoints should return 403 when an invalid API key is provided."""
    settings.auth_enabled = True
    settings.api_key = "test-secret-key"
    response = client.get("/api/neurobench/benchmarks", headers={"X-API-Key": "wrong-key"})
    assert response.status_code == 403
