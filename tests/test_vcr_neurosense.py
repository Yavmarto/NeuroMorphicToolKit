"""VCR tests for Neurosense adapter — outgoing HTTP calls.

``PipelineBridge.send_spikes`` is the sole outgoing HTTP entry point in
the Neurosense backend.  It POSTs spike-encoded data to the neurocnl
simulation API (``http://localhost:8000/api/simulate``) via
``aiohttp.ClientSession``.

The cassette at ``neurosense/test_pipeline_bridge_send_spikes.yaml``
records a pre-authored 200 JSON response.  VCRpy intercepts the aiohttp
request via its ``aiohttp_stubs`` backend, so no live neurocnl process
needs to be running during the test.

The ``PynqStreamClient.connect()`` WebSocket entry point is also covered
here.  VCRpy cannot intercept WebSocket upgrades, so that test exercises
the documented fallback path (``websockets=None``) which is guaranteed to
produce no live network calls.
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
_CASSETTE_DIR = _REPO_ROOT / "tests" / "fixtures" / "vcr_cassettes" / "neurosense"

_nmtk_vcr = _vcr_module.VCR(
    record_mode=os.getenv("NMTK_VCR_RECORD", "none"),
    match_on=["method", "scheme", "host", "port", "path", "query"],
    filter_headers=["Authorization", "X-API-Key", "Cookie"],
    filter_query_parameters=["api_key", "token"],
)

_SPIKES_CASSETTE = str(_CASSETTE_DIR / "test_pipeline_bridge_send_spikes.yaml")

_SPIKE_PAYLOAD = {
    "spike_trains": [[0.004, 0.012, 0.020], [0.008, 0.016]],
    "spike_counts": [3, 2],
    "method": "delta",
}


# ---------------------------------------------------------------------------
# 1. PipelineBridge.send_spikes — aiohttp POST (VCR cassette)
# ---------------------------------------------------------------------------


@pytest.mark.anyio
async def test_pipeline_bridge_send_spikes_cassette() -> None:
    """Pin the HTTP round-trip for PipelineBridge.send_spikes via VCR cassette.

    Creates a fresh PipelineBridge, connects it to the default neurocnl
    endpoint, then calls send_spikes.  VCRpy intercepts the aiohttp POST
    and replays the pre-authored response
    ``{"status": "simulated", "spikes_processed": 3, "latency_ms": 1.2}``.
    """
    from neurosense.app.services.pipeline_bridge import PipelineBridge

    bridge = PipelineBridge()

    with _nmtk_vcr.use_cassette(_SPIKES_CASSETTE):
        await bridge.connect()  # sets _connected=True, no HTTP
        result = await bridge.send_spikes(_SPIKE_PAYLOAD)

    assert result["status"] == "simulated"
    assert result["spikes_processed"] == 3
    assert result["latency_ms"] == 1.2


@pytest.mark.anyio
async def test_pipeline_bridge_not_connected_raises() -> None:
    """Confirm RuntimeError when send_spikes is called before connect — no network."""
    from neurosense.app.services.pipeline_bridge import PipelineBridge

    bridge = PipelineBridge()
    with pytest.raises(RuntimeError, match="Pipeline not connected"):
        await bridge.send_spikes(_SPIKE_PAYLOAD)


@pytest.mark.anyio
async def test_pipeline_bridge_disconnect_clears_state() -> None:
    """Confirm that disconnect resets connected flag — no network call."""
    from neurosense.app.services.pipeline_bridge import PipelineBridge

    bridge = PipelineBridge()
    await bridge.connect()
    assert bridge.is_connected is True

    result = await bridge.disconnect()
    assert bridge.is_connected is False
    assert result["status"] == "disconnected"


# ---------------------------------------------------------------------------
# 2. PynqStreamClient.connect — WebSocket (no-network fallback path)
# ---------------------------------------------------------------------------


@pytest.mark.anyio
async def test_pynq_stream_client_simulated_connect_no_network() -> None:
    """Exercise PynqStreamClient.connect() via the websockets=None fallback.

    When the ``websockets`` library is not installed (or not importable),
    the client enters a simulated-connect state and makes NO network call.
    This is the documented safe path used in test and CI environments.
    """
    from unittest.mock import patch

    from neurosense.app.services.pynq_stream_client import PynqStreamClient

    # Force the module-level websockets variable to None (library absent)
    with patch("neurosense.app.services.pynq_stream_client.websockets", None):
        client = PynqStreamClient("ws://pynq-node.local:9000/stream")
        await client.connect()

    assert client._connected is True
    assert client._websocket is None
