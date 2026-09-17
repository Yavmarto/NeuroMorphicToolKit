import importlib
import os

from fastapi.testclient import TestClient

from neurochip.app import main


def test_cors_headers():
    # Set environment variable for allowed origins
    os.environ["ALLOWED_ORIGINS"] = "http://localhost:8080,http://localhost:3000"

    # Reload the module to pick up the new environment variable if it's used at module level
    # In our case, we'll probably put the middleware setup in main.py
    importlib.reload(main)
    client = TestClient(main.app)

    # Test allowed origin
    response = client.options(
        "/health",
        headers={
            "Origin": "http://localhost:8080",
            "Access-Control-Request-Method": "GET",
        },
    )
    assert response.status_code == 200
    assert response.headers.get("access-control-allow-origin") == "http://localhost:8080"

    # Test another allowed origin
    response = client.options(
        "/health",
        headers={
            "Origin": "http://localhost:3000",
            "Access-Control-Request-Method": "GET",
        },
    )
    assert response.status_code == 200
    assert response.headers.get("access-control-allow-origin") == "http://localhost:3000"

    # Test disallowed origin
    response = client.options(
        "/health",
        headers={
            "Origin": "http://disallowed.com",
            "Access-Control-Request-Method": "GET",
        },
    )
    # FastAPI CORS middleware returns 400 or just doesn't include the header for disallowed origins on OPTIONS
    # Actually, it often returns 200 but without the CORS headers.
    assert response.headers.get("access-control-allow-origin") is None
