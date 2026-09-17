import importlib
import os
from unittest.mock import patch

from fastapi.testclient import TestClient

import backend.app.main


def test_cors_default_allow_all():
    # By default, it should allow all if CORS_ALLOWED_ORIGINS is not set
    # We remove it from the patched env to test default behavior
    with patch.dict(os.environ):
        if "CORS_ALLOWED_ORIGINS" in os.environ:
            del os.environ["CORS_ALLOWED_ORIGINS"]

        importlib.reload(backend.app.main)
        from backend.app.main import app

        client = TestClient(app)

        resp = client.options(
            "/health",
            headers={
                "Origin": "http://random-origin.com",
                "Access-Control-Request-Method": "GET",
            },
        )
        assert resp.status_code == 200
        # Since we changed it to allow_credentials=False for "*", Starlette returns "*"
        assert resp.headers.get("access-control-allow-origin") == "*"


def test_cors_restricted_origins():
    # Test with restricted origins, including whitespace and empty parts
    with patch.dict(
        os.environ,
        {"CORS_ALLOWED_ORIGINS": " http://localhost:3000 , http://myapp.com , , "},
    ):
        importlib.reload(backend.app.main)
        from backend.app.main import app

        client = TestClient(app)

        # Allowed origin (first one)
        resp = client.options(
            "/health",
            headers={
                "Origin": "http://localhost:3000",
                "Access-Control-Request-Method": "GET",
            },
        )
        assert resp.status_code == 200
        assert resp.headers.get("access-control-allow-origin") == "http://localhost:3000"

        # Allowed origin (second one)
        resp = client.options(
            "/health",
            headers={
                "Origin": "http://myapp.com",
                "Access-Control-Request-Method": "GET",
            },
        )
        assert resp.status_code == 200
        assert resp.headers.get("access-control-allow-origin") == "http://myapp.com"

        # Disallowed origin
        resp = client.options(
            "/health",
            headers={
                "Origin": "http://evil.com",
                "Access-Control-Request-Method": "GET",
            },
        )
        # When an origin is not allowed, Starlette CORSMiddleware returns 400 for preflight
        assert resp.status_code in [200, 400]
        if resp.status_code == 200:
            assert "access-control-allow-origin" not in resp.headers


def teardown_module(module):
    # Restore default state for other tests
    importlib.reload(backend.app.main)
