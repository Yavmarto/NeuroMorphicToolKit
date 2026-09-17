"""Client for streaming data from a remote PYNQ Z2 node."""

import asyncio
import importlib
import json
import logging
from collections.abc import AsyncGenerator
from typing import Any, cast

try:
    websockets = cast(Any, importlib.import_module("websockets"))
except ImportError:
    websockets = None

logger = logging.getLogger(__name__)


class PynqStreamClient:
    """Manages the network connection to the remote PYNQ node's FastAPI service."""

    def __init__(self, uri: str) -> None:
        """Initialize the client.

        Args:
            uri: The WebSocket URI to connect to.
        """
        self.uri = uri
        self._connected = False
        self._websocket: Any = None

    async def connect(self) -> None:
        """Establish a WebSocket connection to the PYNQ node."""
        if not websockets:
            logger.warning("websockets library not installed. Connection simulated.")
            self._connected = True
            return

        logger.info(f"Connecting to PYNQ node at {self.uri}")
        try:
            self._websocket = await websockets.connect(self.uri)
            self._connected = True
            logger.info("Connected to PYNQ node stream.")
        except Exception as exc:
            logger.error(f"Failed to connect to PYNQ node: {exc}")
            raise

    async def stream_data(self) -> AsyncGenerator[dict[str, Any], None]:
        """Stream data from the PYNQ node.

        Yields:
            Parsed JSON payloads containing spike data.
        """
        if not self._connected:
            await self.connect()

        if self._websocket is not None:
            try:
                while True:
                    data = await self._websocket.recv()
                    yield json.loads(data)
            except websockets.exceptions.ConnectionClosed:
                logger.warning("Connection to PYNQ node closed.")
            finally:
                self._connected = False
        else:
            # Simulated data generation if websockets is not available
            while self._connected:
                await asyncio.sleep(0.05)
                yield {"spikes": [1, 0, 1, 0], "simulated": True}

    async def disconnect(self) -> None:
        """Close the WebSocket connection."""
        self._connected = False
        if self._websocket is not None:
            await self._websocket.close()
            self._websocket = None
        logger.info("Disconnected from PYNQ node.")

    async def connect_and_stream(self) -> None:
        """Connect to the PYNQ node and stream data (legacy compatibility)."""
        await self.connect()
        async for _ in self.stream_data():
            pass
