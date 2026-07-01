"""Tests for Neurosense pipeline bridge service."""

from __future__ import annotations

import pytest


@pytest.mark.anyio
async def test_pipeline_bridge_not_connected_raises() -> None:
    from neurosense.app.services.pipeline_bridge import PipelineBridge

    bridge = PipelineBridge()
    with pytest.raises(RuntimeError, match="Pipeline not connected"):
        await bridge.send_spikes({"spike_trains": []})


@pytest.mark.anyio
async def test_pipeline_bridge_disconnect_clears_state() -> None:
    from neurosense.app.services.pipeline_bridge import PipelineBridge

    bridge = PipelineBridge()
    await bridge.connect()
    assert bridge.is_connected is True

    result = await bridge.disconnect()
    assert bridge.is_connected is False
    assert result["status"] == "disconnected"


@pytest.mark.anyio
async def test_pynq_stream_client_simulated_connect_no_network() -> None:
    from unittest.mock import patch

    from neurosense.app.services.pynq_stream_client import PynqStreamClient

    with patch("neurosense.app.services.pynq_stream_client.websockets", None):
        client = PynqStreamClient("ws://pynq-node.local:9000/stream")
        await client.connect()

    assert client._connected is True
    assert client._websocket is None
