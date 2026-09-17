import pytest
from fastapi.testclient import TestClient

import neurochip.app.auth as auth
from neurochip.app.auth import validate_startup_auth_config
from neurochip.app.main import app


def test_auth_disabled_by_default():
    # Ensure AUTH_ENABLED is False for this test
    original_enabled = auth.AUTH_ENABLED
    auth.AUTH_ENABLED = False

    client = TestClient(app)
    # This should succeed even without a key
    response = client.get("/api/neurochip/targets")
    assert response.status_code == 200

    auth.AUTH_ENABLED = original_enabled


def test_auth_rejection_when_enabled():
    # Force AUTH_ENABLED to True for this test
    original_enabled = auth.AUTH_ENABLED
    auth.AUTH_ENABLED = True

    client = TestClient(app)
    # This should fail without a key
    response = client.get("/api/neurochip/targets")
    assert response.status_code == 401
    assert response.json() == {"detail": "Invalid or missing API Key"}

    auth.AUTH_ENABLED = original_enabled


def test_auth_success_with_correct_key():
    # Force AUTH_ENABLED to True and set a known key
    original_enabled = auth.AUTH_ENABLED
    original_key = auth.API_KEY
    auth.AUTH_ENABLED = True
    auth.API_KEY = "test-secret-key"

    client = TestClient(app)
    # This should succeed with the correct key
    response = client.get("/api/neurochip/targets", headers={"X-API-Key": "test-secret-key"})
    assert response.status_code == 200

    auth.AUTH_ENABLED = original_enabled
    auth.API_KEY = original_key


def test_auth_failure_with_wrong_key():
    # Force AUTH_ENABLED to True and set a known key
    original_enabled = auth.AUTH_ENABLED
    original_key = auth.API_KEY
    auth.AUTH_ENABLED = True
    auth.API_KEY = "test-secret-key"

    client = TestClient(app)
    # This should fail with the wrong key
    response = client.get("/api/neurochip/targets", headers={"X-API-Key": "wrong-key"})
    assert response.status_code == 401

    auth.AUTH_ENABLED = original_enabled
    auth.API_KEY = original_key


def test_health_check_unauthenticated():
    # Health check should NOT require authentication
    original_enabled = auth.AUTH_ENABLED
    auth.AUTH_ENABLED = True

    client = TestClient(app)
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "healthy"}

    auth.AUTH_ENABLED = original_enabled


# ---------------------------------------------------------------------------
# validate_startup_auth_config tests
# ---------------------------------------------------------------------------


def test_validate_startup_auth_config_raises_on_default_key():
    """Auth enabled + default key must abort startup."""
    original_enabled = auth.AUTH_ENABLED
    original_key = auth.API_KEY
    auth.AUTH_ENABLED = True
    auth.API_KEY = auth._DEFAULT_API_KEY
    try:
        with pytest.raises(RuntimeError, match="NEUROCHIP_API_KEY is still the default"):
            validate_startup_auth_config()
    finally:
        auth.AUTH_ENABLED = original_enabled
        auth.API_KEY = original_key


def test_validate_startup_auth_config_passes_with_custom_key():
    """Auth enabled + custom key must not raise."""
    original_enabled = auth.AUTH_ENABLED
    original_key = auth.API_KEY
    auth.AUTH_ENABLED = True
    auth.API_KEY = "my-very-secret-key-xyz"
    try:
        validate_startup_auth_config()  # should not raise
    finally:
        auth.AUTH_ENABLED = original_enabled
        auth.API_KEY = original_key


def test_validate_startup_auth_config_passes_when_auth_disabled():
    """Auth disabled with default key must not raise."""
    original_enabled = auth.AUTH_ENABLED
    original_key = auth.API_KEY
    auth.AUTH_ENABLED = False
    auth.API_KEY = auth._DEFAULT_API_KEY
    try:
        validate_startup_auth_config()  # should not raise
    finally:
        auth.AUTH_ENABLED = original_enabled
        auth.API_KEY = original_key
