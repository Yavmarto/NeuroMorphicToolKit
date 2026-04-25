"""Root test suite configuration.

Provides a shared VCR instance (``nmtk_vcr``) consumed by all VCR-decorated
tests across the monorepo.  The instance is pre-configured to:

  * Strip ``Authorization`` and ``X-API-Key`` headers from every cassette so
    that secrets are never committed to source control.
  * Remove the ``api_key`` query parameter for the same reason.
  * Default to ``record_mode="none"`` — pre-authored cassettes are replayed
    but no live network calls are issued during a normal ``pytest`` run.
    Set ``NMTK_VCR_RECORD=new_episodes`` in the environment to record a
    missing cassette against a live service.
  * Match requests on method, scheme, host, port, path, and query — body is
    intentionally excluded from matching so that inter-service call cassettes
    survive minor spec-text variation.
"""

from __future__ import annotations

import os
import pathlib
import socket

import pytest
import vcr as _vcr_module

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
CASSETTE_DIR = REPO_ROOT / "tests" / "fixtures" / "vcr_cassettes"

# ---------------------------------------------------------------------------
# Shared VCR instance
# ---------------------------------------------------------------------------

#: Record mode: "none" for CI safety, override with env var for local recording.
_RECORD_MODE: str = os.getenv("NMTK_VCR_RECORD", "none")

nmtk_vcr = _vcr_module.VCR(
    record_mode=_RECORD_MODE,
    match_on=["method", "scheme", "host", "port", "path", "query"],
    filter_headers=[
        "Authorization",
        "X-API-Key",
        "Cookie",
        "Set-Cookie",
    ],
    filter_query_parameters=["api_key", "token"],
    decode_compressed_response=True,
    # Persist cassettes as YAML (human-readable, diff-friendly)
    serializer="yaml",
)

# ---------------------------------------------------------------------------
# Network-blocking fixture
# ---------------------------------------------------------------------------


@pytest.fixture(autouse=True)
def _block_live_network_in_vcr_tests(
    request: pytest.FixtureRequest,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Block raw socket connections when NMTK_VCR_BLOCK_NETWORK=1.

    Tests decorated with ``@vcr.use_cassette(...)`` rely entirely on
    pre-recorded cassettes, so any attempt to open a live socket is a sign
    of a cassette miss and should fail loudly.
    """
    if os.getenv("NMTK_VCR_BLOCK_NETWORK") != "1":
        return

    def _blocked(*_args: object, **_kwargs: object) -> None:
        raise AssertionError(
            "Unexpected live network call detected during VCR replay. "
            "Check that a cassette file exists for every HTTP call in this test."
        )

    monkeypatch.setattr(socket, "create_connection", _blocked)
