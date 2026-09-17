"""Suite API connection and authentication helpers for integration tests."""

from __future__ import annotations

import os
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

import httpx
import pytest

DEFAULT_SUITE_API_URL = "http://192.168.2.90:9000"


def suite_api_url() -> str:
    """Return the configured Suite API, defaulting to the supported dev host."""
    return os.getenv("SUITE_API_URL", DEFAULT_SUITE_API_URL).rstrip("/")


def _service_label(url: str) -> str:
    parsed = urlparse(url)
    return parsed.netloc or parsed.path or url


def _admin_token() -> str:
    token = os.getenv("NMTK_ADMIN_TOKEN", "").strip()
    token_file = os.getenv("NMTK_ADMIN_TOKEN_FILE", "").strip()
    if token or not token_file:
        return token
    try:
        return Path(token_file).read_text(encoding="utf-8").strip()
    except OSError as exc:
        pytest.fail(f"Cannot read NMTK_ADMIN_TOKEN_FILE: {exc}")


async def request_suite_api(
    client: httpx.AsyncClient,
    method: str,
    url: str,
    **kwargs: Any,
) -> httpx.Response:
    """Call Suite API with app credentials and actionable boundary checks."""
    headers = dict(kwargs.pop("headers", {}) or {})
    admin_token = _admin_token()
    if admin_token:
        headers.setdefault("X-NMTK-Admin-Token", admin_token)
    try:
        response = await client.request(method, url, headers=headers, **kwargs)
    except httpx.RequestError as exc:
        pytest.fail(f"Required Suite API {_service_label(url)} unavailable: {exc}")
    if response.headers.get("server", "").lower() == "minio":
        pytest.fail(
            f"SUITE_API_URL points to MinIO at {_service_label(url)}, not Suite API. "
            "Set SUITE_API_URL to the backend shown in Backend Setup."
        )
    if response.status_code == 401 and not admin_token:
        pytest.fail(
            "Suite API requires administrator authentication. Set NMTK_ADMIN_TOKEN "
            "or NMTK_ADMIN_TOKEN_FILE to the app-provisioned test credential."
        )
    return response
