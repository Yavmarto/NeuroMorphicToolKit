"""Event encoder for converting event data into SNN-compatible spike tensors."""

from dataclasses import dataclass
from typing import Any, cast

import numpy as np


class EventBinningError(ValueError):
    """Raised when event batches cannot be binned honestly."""


@dataclass(frozen=True, slots=True)
class BinnedEventBatch:
    """Deterministic event-binning result used by the event encoder."""

    spike_tensor: list[list[int]]
    addresses: list[int]
    relative_timestamps_us: list[int]
    counts: int
    n_bins: int


class EventEncoder:
    """Encodes asynchronous event data (x, y, polarity, timestamp) into SNN spike formats."""

    def __init__(self, width: int = 1280, height: int = 720) -> None:
        """Initialize the encoder with the sensor resolution.

        Args:
            width: The width of the sensor in pixels.
            height: The height of the sensor in pixels.
        """
        self.width = width
        self.height = height

    def configure(self, width: int, height: int) -> None:
        """Update the sensor resolution."""
        if width <= 0 or height <= 0:
            raise EventBinningError(
                f"Sensor dimensions must be positive, got width={width}, height={height}."
            )
        self.width = width
        self.height = height

    def _validate_dimensions(self) -> None:
        if self.width <= 0 or self.height <= 0:
            raise EventBinningError(
                f"Sensor dimensions must be positive, got width={self.width}, height={self.height}."
            )

    def _validate_coordinates(self, x: np.ndarray[Any, Any], y: np.ndarray[Any, Any]) -> None:
        invalid_x = np.where((x < 0) | (x >= self.width))[0]
        if invalid_x.size:
            index = int(invalid_x[0])
            raise EventBinningError(
                f"Event {index} has x={int(x[index])} outside valid range [0, {self.width})."
            )

        invalid_y = np.where((y < 0) | (y >= self.height))[0]
        if invalid_y.size:
            index = int(invalid_y[0])
            raise EventBinningError(
                f"Event {index} has y={int(y[index])} outside valid range [0, {self.height})."
            )

    def map_to_neuron_address(
        self, x: np.ndarray[Any, Any], y: np.ndarray[Any, Any], p: np.ndarray[Any, Any]
    ) -> np.ndarray[Any, Any]:
        """Map (x, y, polarity) coordinates to a flattened 1D neuron address.

        Address format: y * (width * 2) + x * 2 + p
        This flattens the 3D space (width, height, polarity) into a 1D index compatible
        with generic SNN input layers.

        Args:
            x: NumPy array of x coordinates.
            y: NumPy array of y coordinates.
            p: NumPy array of polarities (0 or 1).

        Returns:
            NumPy array of flattened neuron addresses.
        """
        self._validate_dimensions()
        self._validate_coordinates(x, y)
        # Ensure polarities are 0 or 1
        p_norm = np.where(p > 0, 1, 0)
        return cast(np.ndarray[Any, Any], (y * self.width * 2) + (x * 2) + p_norm)

    def bin_events(
        self,
        events: np.ndarray[Any, Any],
        *,
        bin_width_us: int,
    ) -> BinnedEventBatch:
        """Convert ordered structured events into a dense spike tensor summary."""
        self._validate_dimensions()
        if bin_width_us <= 0:
            raise EventBinningError(f"bin_width_us must be positive, got {bin_width_us}.")
        if events is None or len(events) == 0:
            return BinnedEventBatch(
                spike_tensor=[],
                addresses=[],
                relative_timestamps_us=[],
                counts=0,
                n_bins=0,
            )

        x = np.asarray(events["x"], dtype=np.int64)
        y = np.asarray(events["y"], dtype=np.int64)
        p = np.asarray(events["p"], dtype=np.int64)
        timestamps = np.asarray(events["t"], dtype=np.int64)

        self._validate_coordinates(x, y)
        if timestamps.size > 1 and np.any(np.diff(timestamps) < 0):
            index = int(np.where(np.diff(timestamps) < 0)[0][0] + 1)
            raise EventBinningError(
                "Event "
                f"{index} has timestamp {int(timestamps[index])} < previous timestamp "
                f"{int(timestamps[index - 1])}."
            )

        relative_timestamps = timestamps - timestamps[0]
        addresses = self.map_to_neuron_address(x, y, p).astype(np.int64, copy=False)

        n_bins = int(relative_timestamps[-1] // bin_width_us) + 1
        address_space_size = self.height * self.width * 2
        spike_tensor = np.zeros((n_bins, address_space_size), dtype=np.int64)
        bin_indices = relative_timestamps // bin_width_us
        np.add.at(spike_tensor, (bin_indices, addresses), 1)

        return BinnedEventBatch(
            spike_tensor=spike_tensor.tolist(),
            addresses=addresses.tolist(),
            relative_timestamps_us=relative_timestamps.tolist(),
            counts=int(len(events)),
            n_bins=n_bins,
        )

    def encode_to_spike_tensor(
        self, events: np.ndarray[Any, Any], *, bin_width_us: int = 100
    ) -> dict[str, Any]:
        """Convert a batch of structured events into a spike tensor dict.

        Args:
            events: A structured NumPy array containing fields 'x', 'y', 'p', 't'.
            bin_width_us: Width of one time bin in microseconds for the dense tensor.

        Returns:
            A dictionary containing the SNN-compatible spike representation.
        """
        self._validate_dimensions()
        if events is None or len(events) == 0:
            return {
                "addresses": [],
                "timestamps": [],
                "relative_timestamps_us": [],
                "counts": 0,
                "n_bins": 0,
                "spike_tensor": [],
                "shape": [self.height, self.width, 2],
            }

        binned = self.bin_events(events, bin_width_us=bin_width_us)
        timestamps = np.asarray(events["t"], dtype=np.int64)

        return {
            "addresses": binned.addresses,
            "timestamps": timestamps.tolist(),
            "relative_timestamps_us": binned.relative_timestamps_us,
            "counts": binned.counts,
            "n_bins": binned.n_bins,
            "spike_tensor": binned.spike_tensor,
            "shape": [self.height, self.width, 2],
        }


# Module-level singleton
event_encoder = EventEncoder()
