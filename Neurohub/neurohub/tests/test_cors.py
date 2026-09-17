"""Tests for CORS configuration in NeuroHub."""

import os
from unittest.mock import patch

from fastapi.testclient import TestClient


def test_cors_default_allow_all(client: TestClient) -> None:
    """Test that CORS defaults to allowing all origins when no environment variable is set."""
    # TestClient in conftest already uses the app with default middleware setup
    # Using /health instead of /api/neurohub/health because it's defined at the top level
    response = client.get("/health", headers={"Origin": "http://example.com"})
    assert response.status_code == 200
    # When allow_origins=["*"], FastAPI echoes back the Origin if it's not a wildcard in the header
    # Or it might just return "*" depending on the version and configuration.
    assert response.headers.get("access-control-allow-origin") in ["*", "http://example.com"]
    # Credentials should be False for wildcard
    assert "access-control-allow-credentials" not in response.headers


def test_cors_specific_origins() -> None:
    """Test that CORS correctly uses ALLOWED_ORIGINS from environment."""
    with patch.dict(
        os.environ, {"ALLOWED_ORIGINS": "http://localhost:3000,http://app.neurohub.io"}
    ):
        # We need to re-import or re-initialize the app to pick up the new env var
        import importlib

        import neurohub.app.main

        importlib.reload(neurohub.app.main)
        from neurohub.app.main import app

        with TestClient(app) as client:
            # Allowed origin
            response = client.get("/health", headers={"Origin": "http://localhost:3000"})
            assert response.status_code == 200
            assert response.headers.get("access-control-allow-origin") == "http://localhost:3000"
            assert response.headers.get("access-control-allow-credentials") == "true"

            # Another allowed origin
            response = client.get("/health", headers={"Origin": "http://app.neurohub.io"})
            assert response.status_code == 200
            assert response.headers.get("access-control-allow-origin") == "http://app.neurohub.io"

            # Disallowed origin
            response = client.get("/health", headers={"Origin": "http://evil.com"})
            assert response.status_code == 200
            assert "access-control-allow-origin" not in response.headers

    # Clean up: reload main again to restore defaults for other tests
    importlib.reload(neurohub.app.main)
