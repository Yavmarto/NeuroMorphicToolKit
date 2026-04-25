"""VCR tests for Neurohub adapter — outgoing inter-service HTTP calls.

``neurohub.app.services.suite_client`` contains all outgoing HTTP
entry points from the Neurohub backend:

  * ``check_service_health`` — async GET to ``{base_url}/health``
  * ``call_app_api``         — async GET or POST to ``{base_url}{endpoint}``
  * ``fetch_activity``       — async GET to ``{base_url}/api/{app}/activity``
  * ``send_bundle_handoff``  — delegates to ``call_app_api`` (POST)

All four functions use ``httpx.AsyncClient``.  VCRpy intercepts the
calls via its httpcore stubs, so no live suite services need to be
running during the test.

Cassettes are pre-authored in ``neurohub/`` and use ``record_mode="none"``
so no accidental live requests escape to localhost.
"""

from __future__ import annotations

import os
import pathlib

import pytest
import vcr as _vcr_module

# ---------------------------------------------------------------------------
# Module-local VCR config (avoids PYTHONPATH collision with module conftest)
# ---------------------------------------------------------------------------

_REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
_CASSETTE_DIR = _REPO_ROOT / "tests" / "fixtures" / "vcr_cassettes" / "neurohub"

_nmtk_vcr = _vcr_module.VCR(
    record_mode=os.getenv("NMTK_VCR_RECORD", "none"),
    match_on=["method", "scheme", "host", "port", "path", "query"],
    filter_headers=["Authorization", "X-API-Key", "Cookie"],
    filter_query_parameters=["api_key", "token"],
)

_HEALTH_ONLINE_CASSETTE = str(_CASSETTE_DIR / "test_check_health_online.yaml")
_HEALTH_DEGRADED_CASSETTE = str(_CASSETTE_DIR / "test_check_health_degraded.yaml")
_CALL_API_GET_CASSETTE = str(_CASSETTE_DIR / "test_call_api_get.yaml")
_CALL_API_POST_CASSETTE = str(_CASSETTE_DIR / "test_call_api_post.yaml")
_FETCH_ACTIVITY_CASSETTE = str(_CASSETTE_DIR / "test_fetch_activity.yaml")

# The URLs must exactly match the ``uri`` fields in the cassette files
_BASE = "http://localhost:8001"


# ---------------------------------------------------------------------------
# 1. check_service_health — GET /health
# ---------------------------------------------------------------------------


@pytest.mark.anyio
async def test_check_service_health_online_cassette() -> None:
    """Pin the 'online' branch of check_service_health via VCR cassette.

    The cassette returns HTTP 200 with ``{"status": "ok", "version": "1.0.0"}``.
    Asserts that the function parses status, version, and response_time_ms.
    """
    from neurohub.app.services.suite_client import check_service_health

    with _nmtk_vcr.use_cassette(_HEALTH_ONLINE_CASSETTE):
        result = await check_service_health("neurosim", _BASE)

    assert result["status"] == "online"
    assert result["version"] == "1.0.0"
    assert result["error"] is None
    assert result["response_time_ms"] is not None


@pytest.mark.anyio
async def test_check_service_health_degraded_cassette() -> None:
    """Pin the 'degraded' branch when the health endpoint returns HTTP 500."""
    from neurohub.app.services.suite_client import check_service_health

    with _nmtk_vcr.use_cassette(_HEALTH_DEGRADED_CASSETTE):
        result = await check_service_health("neurosim", _BASE)

    assert result["status"] == "degraded"
    assert result["error"] == "HTTP 500"
    assert result["version"] is None


# ---------------------------------------------------------------------------
# 2. call_app_api — GET and POST
# ---------------------------------------------------------------------------


@pytest.mark.anyio
async def test_call_app_api_get_cassette() -> None:
    """Pin a GET call to an arbitrary API endpoint via VCR cassette."""
    from neurohub.app.services.suite_client import call_app_api

    with _nmtk_vcr.use_cassette(_CALL_API_GET_CASSETTE):
        result = await call_app_api(_BASE, "/api/test", method="GET")

    assert result == {"result": "ok"}


@pytest.mark.anyio
async def test_call_app_api_post_cassette() -> None:
    """Pin a POST call with JSON body via VCR cassette."""
    from neurohub.app.services.suite_client import call_app_api

    with _nmtk_vcr.use_cassette(_CALL_API_POST_CASSETTE):
        result = await call_app_api(
            _BASE, "/api/test", method="POST", params={"key": "value"}
        )

    assert result == {"created": True}


# ---------------------------------------------------------------------------
# 3. fetch_activity — GET /api/{app}/activity
# ---------------------------------------------------------------------------


@pytest.mark.anyio
async def test_fetch_activity_cassette() -> None:
    """Pin the activity list returned from a suite app via VCR cassette.

    The cassette returns a single activity entry.  Verifies that the
    function injects the ``app`` tag into each entry.
    """
    from neurohub.app.services.suite_client import fetch_activity

    with _nmtk_vcr.use_cassette(_FETCH_ACTIVITY_CASSETTE):
        entries = await fetch_activity("neurosim", _BASE)

    assert len(entries) == 1
    assert entries[0]["action"] == "create_project"
    # fetch_activity injects the app name into each entry
    assert entries[0]["app"] == "neurosim"


# ---------------------------------------------------------------------------
# 4. Utility — no HTTP
# ---------------------------------------------------------------------------


def test_build_health_endpoint_strips_trailing_slash() -> None:
    """Confirm URL building logic — pure function, no network call."""
    from neurohub.app.services.suite_client import build_health_endpoint

    assert build_health_endpoint("http://neurosim:8001/") == "http://neurosim:8001/health"
    assert build_health_endpoint("http://neurosim:8001") == "http://neurosim:8001/health"


def test_get_app_urls_returns_defaults_without_db_config() -> None:
    """Confirm default URL map when no SuiteConfig row exists."""
    from unittest.mock import MagicMock

    from neurohub.app.services.suite_client import get_app_urls

    mock_db = MagicMock()
    mock_db.query.return_value.first.return_value = None  # no config in DB

    urls = get_app_urls(mock_db)
    assert urls["neurosim"] == "http://localhost:8001"
    assert urls["neurochip"] == "http://localhost:8002"
    assert len(urls) == 5
