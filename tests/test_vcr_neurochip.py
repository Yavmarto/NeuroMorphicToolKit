"""VCR tests for Neurochip adapter — outgoing HTTP calls.

The only outgoing HTTP call from the Neurochip backend app is in
``neurochip.app.routers.akida._dispatch_package`` when
``deployment_mode=remote_server``.  It POSTs a ZIP payload to a
caller-supplied ``target_url`` via ``urllib.request``.

The cassette at ``neurochip/test_akida_remote_dispatch_success.yaml``
records a POST to ``https://akida-deploy.example.com/upload`` and
returns a pre-authored 200 JSON response.  No live connection is made
during replay.

No HTTP calls exist in the remaining Neurochip routers
(deployments, analysis, estimation, quantization, faults, targets,
export, lava, pynq, serial) — they are pure in-process computation.
"""

from __future__ import annotations

import os
import pathlib
from unittest.mock import MagicMock

import pytest
import vcr as _vcr_module

# ---------------------------------------------------------------------------
# Module-local VCR config (avoids PYTHONPATH collision with module conftest)
# ---------------------------------------------------------------------------

_REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
_CASSETTE_DIR = _REPO_ROOT / "tests" / "fixtures" / "vcr_cassettes" / "neurochip"

_nmtk_vcr = _vcr_module.VCR(
    record_mode=os.getenv("NMTK_VCR_RECORD", "none"),
    match_on=["method", "scheme", "host", "port", "path", "query"],
    filter_headers=["Authorization", "X-API-Key", "Cookie"],
    filter_query_parameters=["api_key", "token"],
)

_DISPATCH_CASSETTE = str(_CASSETTE_DIR / "test_akida_remote_dispatch_success.yaml")

# Target URL recorded in the cassette
_REMOTE_URL = "https://akida-deploy.example.com/upload"


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------


def test_akida_remote_server_dispatch_replays_cassette() -> None:
    """Pin the remote-server dispatch result via VCR cassette.

    ``_dispatch_package`` is called with ``deployment_mode="remote_server"``
    and a stub AkidaBackend.  urllib.request.urlopen is intercepted by VCRpy;
    the cassette response ``{"status": "queued", "job_id": "akida-001"}``
    is returned without making a live network call.
    """
    from neurochip.app.routers.akida import _dispatch_package

    # Minimal stub — only current_state is inspected for remote_server mode
    stub_backend = MagicMock()
    stub_backend.current_state = "mapped"

    # Minimal ZIP payload (content irrelevant; cassette matches on URI/method only)
    dummy_zip = b"PK\x03\x04"  # ZIP magic bytes

    with _nmtk_vcr.use_cassette(_DISPATCH_CASSETTE):
        response = _dispatch_package(
            backend=stub_backend,
            zip_bytes=dummy_zip,
            deployment_mode="remote_server",
            target_url=_REMOTE_URL,
        )

    # The router returns a JSONResponse; decode the body
    import json

    body = json.loads(response.body)
    assert body["deployment_mode"] == "remote_server"
    assert body["target_url"] == _REMOTE_URL
    assert body["remote_status"] == 200


def test_akida_remote_server_dispatch_missing_url_raises_422() -> None:
    """Confirm that omitting target_url raises HTTP 422 — no network call needed."""
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
    """Confirm that a non-HTTP target_url raises HTTP 422 before any network call."""
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
