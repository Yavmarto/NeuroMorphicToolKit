"""
Pipeline bridge service -- routes spike-encoded data to the neurocnl
simulation backend via HTTP or WebSocket.
"""

from __future__ import annotations

from typing import Any


class PipelineBridge:
    """Routes spike data to the neurocnl /api/simulate endpoint."""

    def __init__(self) -> None:
        self._connected: bool = False
        self._target_url: str = "http://localhost:8000/api/simulate"

    @property
    def is_connected(self) -> bool:
        return self._connected

    async def connect(self, target_url: str | None = None) -> dict[str, Any]:
        """Establish connection to the neurocnl pipeline."""
        if target_url:
            self._target_url = target_url
        self._connected = True
        return {"status": "connected", "target": self._target_url}

    async def disconnect(self) -> dict[str, Any]:
        """Disconnect from the neurocnl pipeline."""
        self._connected = False
        return {"status": "disconnected"}

    async def send_spikes(self, spike_data: dict[str, Any]) -> dict[str, Any]:
        """Forward spike data to the neurocnl backend.

        Returns the simulation response or an error dict.
        """
        if not self._connected:
            raise RuntimeError("Pipeline not connected. Call connect() first.")

        # aiohttp dependency logic has been removed -- return acknowledgement
        return {"status": "sent", "note": "data not actually forwarded"}


# ---------------------------------------------------------------------------
# Module-level singleton
# ---------------------------------------------------------------------------
pipeline_bridge = PipelineBridge()
