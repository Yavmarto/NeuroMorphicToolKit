"""Prophesee source for event-based neuromorphic cameras."""

import importlib
import logging
from typing import Any, cast

import numpy as np

logger = logging.getLogger(__name__)


def _load_events_iterator() -> Any:
    """Load Metavision lazily so type checking does not require SDK stubs."""
    module = cast(Any, importlib.import_module("metavision_core.event_io"))
    return module.EventsIterator


try:
    _EVENTS_ITERATOR = _load_events_iterator()
    METAVISION_AVAILABLE = True
except ImportError:
    _EVENTS_ITERATOR = None
    METAVISION_AVAILABLE = False


class PropheseeSource:
    """Data source for Prophesee event cameras.

    Can read from a live EVK camera or from an offline recording (.raw, .hdf5).
    Integrated with Metavision SDK.
    """

    def __init__(self, mode: str = "live", path: str | None = None) -> None:
        """Initialize the Prophesee source.

        Args:
            mode: "live" for live camera, "offline" for a recorded file.
            path: Path to the .raw or .hdf5 file for offline mode.
        """
        if not METAVISION_AVAILABLE:
            logger.warning(
                "metavision_core is not available. PropheseeSource will not function properly."
            )

        self.mode = mode
        self.path = path
        self._iterator: Any = None
        self._is_open = False
        self.width = 0
        self.height = 0

    def open(self, delta_t: int = 10000) -> None:
        """Open the camera or file and start the stream.

        Args:
            delta_t: Time window in microseconds for batching events.
        """
        if not METAVISION_AVAILABLE:
            raise RuntimeError("metavision-sdk is required but not installed.")

        if self._is_open:
            return

        if self.mode == "live":
            self._iterator = _EVENTS_ITERATOR(input_path="", delta_t=delta_t)
        elif self.mode == "offline":
            if not self.path:
                raise ValueError("Path must be provided for offline mode.")
            self._iterator = _EVENTS_ITERATOR(input_path=self.path, delta_t=delta_t)
        else:
            raise ValueError(f"Unknown mode: {self.mode}")

        self._is_open = True

        # Get geometry
        _, height, width = self._iterator.get_size()
        self.height = height
        self.width = width
        logger.info(f"Opened Prophesee source with resolution {self.width}x{self.height}")

    def read_events(self) -> np.ndarray[Any, Any] | None:
        """Read a batch of events from the stream.

        Returns:
            A structured NumPy array with fields (x, y, p, t) or None if end of stream.
        """
        if not self._is_open or not self._iterator:
            return None

        try:
            events = next(self._iterator)
            return np.array(events)  # Ensure it's a numpy array
        except StopIteration:
            logger.info("End of Prophesee event stream reached.")
            return None

    def close(self) -> None:
        """Close the camera or file."""
        if not self._is_open:
            return

        if self._iterator and hasattr(self._iterator, "reader"):
            # The EventsIterator's internal reader is what holds the file/device handle
            self._iterator = None

        self._is_open = False
        logger.info("Closed Prophesee source.")

    @property
    def is_open(self) -> bool:
        return self._is_open
