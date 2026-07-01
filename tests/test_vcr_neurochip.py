"""Tests for Neurochip adapter outgoing HTTP calls."""

from __future__ import annotations

from unittest.mock import MagicMock, patch

import pytest


def _make_urllib_ctx(body: bytes, status: int = 200) -> MagicMock:
    """Return a context-manager mock for urllib.request.urlopen."""
    m = MagicMock()
    m.read.return_value = body
    m.status = status
    m.__enter__ = lambda s: s
    m.__exit__ = MagicMock(return_value=False)
    return m


def test_akida_remote_server_dispatch_success() -> None:
    """Pin the remote-server dispatch result via mock urllib."""
    import json
    import os

    from neurochip.app.routers.akida import _dispatch_package

    stub_backend = MagicMock()
    stub_backend.current_state = "mapped"

    mock_resp = _make_urllib_ctx(b'{"status": "queued", "job_id": "akida-001"}')

    with patch.dict(os.environ, {"NEUROCHIP_AKIDA_ALLOWED_HOSTS": "akida-deploy.example.com"}), \
         patch("urllib.request.urlopen", return_value=mock_resp):
        response = _dispatch_package(
            backend=stub_backend,
            zip_bytes=b"PK\x03\x04",
            deployment_mode="remote_server",
            target_url="https://akida-deploy.example.com/upload",
        )

    body = json.loads(response.body)
    assert body["deployment_mode"] == "remote_server"
    assert body["target_url"] == "https://akida-deploy.example.com/upload"
    assert body["remote_status"] == 200


def test_akida_remote_server_dispatch_missing_url_raises_422() -> None:
    from fastapi import HTTPException

    from neurochip.app.routers.akida import _dispatch_package

    stub_backend = MagicMock()
    stub_backend.current_state = "mapped"

    with pytest.raises(HTTPException) as exc_info:
        _dispatch_package(
            backend=stub_backend,
            zip_bytes=b"PK\x03\x04",
            deployment_mode="remote_server",
            target_url=None,
        )

    assert exc_info.value.status_code == 422


def test_akida_remote_server_dispatch_invalid_scheme_raises_422() -> None:
    from fastapi import HTTPException

    from neurochip.app.routers.akida import _dispatch_package

    stub_backend = MagicMock()
    stub_backend.current_state = "mapped"

    with pytest.raises(HTTPException) as exc_info:
        _dispatch_package(
            backend=stub_backend,
            zip_bytes=b"PK\x03\x04",
            deployment_mode="remote_server",
            target_url="ftp://akida-deploy.example.com/upload",
        )

    assert exc_info.value.status_code == 422
