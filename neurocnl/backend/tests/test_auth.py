"""Tests for API Key authentication middleware."""

import os
from unittest.mock import patch

from fastapi.testclient import TestClient

from backend.app.main import app

client = TestClient(app)


def test_auth_disabled_by_default():
    """Access should be allowed when AUTH_ENABLED is not set or false."""
    with patch.dict(os.environ, {"AUTH_ENABLED": "false"}):
        response = client.get("/api/templates")
        # Should not be 401
        assert response.status_code == 200


def test_auth_enabled_missing_key():
    """Access should be denied when AUTH_ENABLED is true and key is missing."""
    with patch.dict(os.environ, {"AUTH_ENABLED": "true", "API_KEY": "test-key"}):
        response = client.get("/api/templates")
        assert response.status_code == 401
        assert response.json()["detail"] == "Invalid or missing API key."


def test_auth_enabled_wrong_key():
    """Access should be denied when AUTH_ENABLED is true and key is wrong."""
    with patch.dict(os.environ, {"AUTH_ENABLED": "true", "API_KEY": "test-key"}):
        response = client.get("/api/templates", headers={"X-API-Key": "wrong-key"})
        assert response.status_code == 401
        assert response.json()["detail"] == "Invalid or missing API key."


def test_auth_enabled_correct_key():
    """Access should be allowed when AUTH_ENABLED is true and key is correct."""
    with patch.dict(os.environ, {"AUTH_ENABLED": "true", "API_KEY": "test-key"}):
        response = client.get("/api/templates", headers={"X-API-Key": "test-key"})
        assert response.status_code == 200


def test_auth_not_applied_to_health():
    """Authentication should NOT be applied to non-API routes like /health."""
    with patch.dict(os.environ, {"AUTH_ENABLED": "true", "API_KEY": "test-key"}):
        response = client.get("/health")
        assert response.status_code == 200


def test_auth_enabled_no_server_key_configured():
    """Server should return 500 if AUTH_ENABLED is true but API_KEY is missing from env."""
    with patch.dict(os.environ, {"AUTH_ENABLED": "true"}):
        if "API_KEY" in os.environ:
            del os.environ["API_KEY"]
        response = client.get("/api/templates")
        assert response.status_code == 500
        assert "no API_KEY is configured" in response.json()["detail"]
