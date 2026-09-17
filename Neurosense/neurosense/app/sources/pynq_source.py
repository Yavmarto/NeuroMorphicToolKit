"""PYNQ Z2 edge sensor data acquisition source."""

import asyncio
import logging
from collections.abc import AsyncGenerator
from typing import Any

from ..services.pynq_stream_client import PynqStreamClient

logger = logging.getLogger(__name__)


class PYNQSensorSource:
    """Connects to a PYNQ Z2 running as a remote sensor node.

    This class handles the ingestion of processed spike data streamed
    from a lightweight FastAPI service running on the PYNQ Z2's ARM cores.
    """

    def __init__(self, uri: str, simulated: bool = False) -> None:
        """Initialize the PYNQ sensor source.

        Args:
            uri: The WebSocket URI to connect to the PYNQ service.
            simulated: If True, uses synthetic data instead of actual network connection.
        """
        self.uri = uri
        self.simulated = simulated
        self.client = PynqStreamClient(uri=self.uri)
        self._is_streaming = False

        if self.simulated:
            logger.info("Initializing PYNQSensorSource in simulated mode.")
        else:
            logger.info(f"Initializing PYNQSensorSource pointing to {self.uri}")

    async def start_stream(self) -> AsyncGenerator[dict[str, Any], None]:
        """Establish local streaming websockets using existing PynqStreamClient.

        Yields:
            Data frames containing spike data from the PYNQ Z2 board.
        """
        self._is_streaming = True
        if self.simulated:
            logger.info("Starting simulated PYNQ stream...")
            while self._is_streaming:
                await asyncio.sleep(0.05)
                yield {"spikes": [0, 1, 0, 1], "simulated": True}
        else:
            logger.info("Starting real PYNQ stream...")
            async for data in self.client.stream_data():
                if not self._is_streaming:
                    break
                yield data

    async def stop_stream(self) -> None:
        """Stop streaming data from the remote PYNQ node."""
        self._is_streaming = False
        if not self.simulated:
            await self.client.disconnect()
        logger.info("PYNQ stream stopped.")
