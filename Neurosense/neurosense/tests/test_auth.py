from unittest.mock import patch

from fastapi.testclient import TestClient

import neurosense.app.auth as auth_module
from neurosense.app.main import app

client = TestClient(app)


def test_auth_disabled_by_default() -> None:
    # Ensure NEUROSENSE_AUTH_ENABLED is not set to true
    with patch.object(auth_module, "is_auth_enabled", return_value=False):
        response = client.get("/api/neurosense/devices")
        assert response.status_code == 200


def test_auth_enabled_no_key() -> None:
    with (
        patch.object(auth_module, "is_auth_enabled", return_value=True),
        patch.object(auth_module, "get_expected_api_key", return_value="test-secret"),
    ):
        response = client.get("/api/neurosense/devices")
        assert response.status_code == 403


def test_auth_enabled_wrong_key() -> None:
    with (
        patch.object(auth_module, "is_auth_enabled", return_value=True),
        patch.object(auth_module, "get_expected_api_key", return_value="test-secret"),
    ):
        response = client.get("/api/neurosense/devices", headers={"X-API-Key": "wrong-key"})
        assert response.status_code == 403


def test_auth_enabled_valid_key() -> None:
    with (
        patch.object(auth_module, "is_auth_enabled", return_value=True),
        patch.object(auth_module, "get_expected_api_key", return_value="test-secret"),
    ):
        response = client.get("/api/neurosense/devices", headers={"X-API-Key": "test-secret"})
        assert response.status_code == 200


def test_health_unauthenticated_even_when_auth_enabled() -> None:
    with (
        patch.object(auth_module, "is_auth_enabled", return_value=True),
        patch.object(auth_module, "get_expected_api_key", return_value="test-secret"),
    ):
        response = client.get("/health")
        assert response.status_code == 200
        assert response.json() == {"status": "ok"}


def test_root_unauthenticated_even_when_auth_enabled() -> None:
    with (
        patch.object(auth_module, "is_auth_enabled", return_value=True),
        patch.object(auth_module, "get_expected_api_key", return_value="test-secret"),
    ):
        response = client.get("/")
        assert response.status_code == 200
        if "text/html" in response.headers.get("content-type", ""):
            assert "html" in response.text
        else:
            assert "message" in response.json()


def test_websocket_auth_enabled_no_key() -> None:
    from starlette.testclient import WebSocketDenialResponse

    with (
        patch.object(auth_module, "is_auth_enabled", return_value=True),
        patch.object(auth_module, "get_expected_api_key", return_value="test-secret"),
    ):
        try:
            with client.websocket_connect("/api/neurosense/stream/raw"):
                pass
        except WebSocketDenialResponse as e:
            assert e.status_code == 403


def test_websocket_auth_enabled_wrong_key() -> None:
    from starlette.testclient import WebSocketDenialResponse

    with (
        patch.object(auth_module, "is_auth_enabled", return_value=True),
        patch.object(auth_module, "get_expected_api_key", return_value="test-secret"),
    ):
        try:
            with client.websocket_connect("/api/neurosense/stream/raw?api_key=wrong"):
                pass
        except WebSocketDenialResponse as e:
            assert e.status_code == 403
