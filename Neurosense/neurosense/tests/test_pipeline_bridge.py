from __future__ import annotations

import pytest

from neurosense.app.services.pipeline_bridge import PipelineBridge


@pytest.mark.anyio
async def test_bridge_lifecycle() -> None:
    bridge = PipelineBridge()
    result = await bridge.connect("http://test:8000")

    assert bridge.is_connected is True
    assert result["target"] == "http://test:8000"

    await bridge.disconnect()
    assert bridge.is_connected is False


@pytest.mark.anyio
async def test_send_spikes_no_connection() -> None:
    bridge = PipelineBridge()
    with pytest.raises(RuntimeError, match="Pipeline not connected"):
        await bridge.send_spikes({"spikes": []})


@pytest.mark.anyio
async def test_send_spikes_acknowledgement() -> None:
    bridge = PipelineBridge()
    await bridge.connect()

    spike_data = {"spikes": [1, 2, 3]}

    result = await bridge.send_spikes(spike_data)

    assert result["status"] == "sent"
    assert "not actually forwarded" in result["note"]
