"""VCR tests for the neurocnl → Neurochip PYNQ handoff HTTP client.

Covers both ``get_status`` (GET via urllib) and ``post_deploy`` (POST via
urllib), the two outgoing HTTP entry points in
``neurocnl.handoff.neurochip_pynq_handoff.NeurochipPynqClient``.
"""

from __future__ import annotations

import os
import socket

import pytest
import vcr

from neurocnl.handoff.neurochip_pynq_handoff import NeurochipPynqClient

# ---------------------------------------------------------------------------
# Cassette paths and target URLs
# ---------------------------------------------------------------------------

_GET_CASSETTE = "tests/fixtures/vcr_cassettes/test_neurocnl_pynq_client_get_status.yaml"
_POST_CASSETTE = "tests/fixtures/vcr_cassettes/neurocnl/test_pynq_handoff_post_deploy.yaml"

# Use jsonplaceholder as a stable, well-known test API so the cassettes
# remain meaningful regardless of whether local services are running.
STATUS_URL = "https://jsonplaceholder.typicode.com/todos/1"
DEPLOY_URL = "https://jsonplaceholder.typicode.com/posts"


# ---------------------------------------------------------------------------
# GET — get_status
# ---------------------------------------------------------------------------


@vcr.use_cassette(_GET_CASSETTE)
def test_neurochip_pynq_client_get_status_replays_recorded_response(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Pin the response shape of NeurochipPynqClient.get_status().

    The cassette was recorded against jsonplaceholder.typicode.com.
    On replay, no live network call is made; any regression in field names
    or types causes an immediate assertion failure.
    """
    if os.getenv("NMTK_VCR_BLOCK_NETWORK") == "1":
        monkeypatch.setattr(
            socket,
            "create_connection",
            lambda *_args, **_kwargs: (_ for _ in ()).throw(
                AssertionError("unexpected live network call during VCR replay")
            ),
        )

    client = NeurochipPynqClient()
    result = client.get_status(
        STATUS_URL,
        headers={"Accept": "application/json"},
        timeout=10.0,
    )

    assert result["id"] == 1
    assert result["userId"] == 1
    assert result["completed"] is False


# ---------------------------------------------------------------------------
# POST — post_deploy
# ---------------------------------------------------------------------------


@vcr.use_cassette(_POST_CASSETTE)
def test_neurochip_pynq_client_post_deploy_replays_recorded_response(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Pin the response shape of NeurochipPynqClient.post_deploy().

    The cassette was recorded against jsonplaceholder.typicode.com/posts.
    On replay, no live network call is made.
    """
    if os.getenv("NMTK_VCR_BLOCK_NETWORK") == "1":
        monkeypatch.setattr(
            socket,
            "create_connection",
            lambda *_args, **_kwargs: (_ for _ in ()).throw(
                AssertionError("unexpected live network call during VCR replay")
            ),
        )

    client = NeurochipPynqClient()
    result = client.post_deploy(
        DEPLOY_URL,
        payload={"network_id": "lif_reflex_v1", "target": "pynq_z2"},
        headers={"Accept": "application/json"},
        timeout=10.0,
    )

    # jsonplaceholder echoes back the body and assigns a new id
    assert "id" in result
    assert result["id"] == 101
