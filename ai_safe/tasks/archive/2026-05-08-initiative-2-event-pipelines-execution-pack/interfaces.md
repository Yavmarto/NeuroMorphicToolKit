# Interfaces

Document only signatures, types, schemas, and stub bodies here.

## Target Surface 1: `event_encoder.py`

```python
from __future__ import annotations

from dataclasses import dataclass
from typing import Any

import numpy as np


class EventBinningError(ValueError):
    """Raised when event batches cannot be binned honestly."""


@dataclass(frozen=True, slots=True)
class BinnedEventBatch:
    spike_tensor: list[list[int]]
    addresses: list[int]
    relative_timestamps_us: list[int]
    counts: int
    n_bins: int


class EventEncoder:
    def __init__(self, width: int = 1280, height: int = 720) -> None:
        self.width = width
        self.height = height

    def configure(self, width: int, height: int) -> None:
        """Update sensor resolution."""
        raise NotImplementedError

    def map_to_neuron_address(
        self,
        x: np.ndarray[Any, Any],
        y: np.ndarray[Any, Any],
        p: np.ndarray[Any, Any],
    ) -> np.ndarray[Any, Any]:
        """Return flattened addresses for a structured event batch."""
        raise NotImplementedError

    def bin_events(
        self,
        events: np.ndarray[Any, Any],
        *,
        bin_width_us: int,
    ) -> BinnedEventBatch:
        """Convert ordered events into a dense spike-tensor summary."""
        raise NotImplementedError

    def encode_to_spike_tensor(
        self,
        events: np.ndarray[Any, Any],
        *,
        bin_width_us: int = 100,
    ) -> dict[str, Any]:
        """Return the canonical event payload for downstream consumers."""
        raise NotImplementedError
```

## Target Surface 2: `test_event_encoder.py`

Expected test themes:

- polarity normalization
- repeated-address accumulation across bins
- empty input handling
- invalid coordinate rejection
- decreasing timestamp rejection
- invalid bin-width rejection
- backward-compatible payload field preservation

## Canonical Payload Shape

The returned dict from `encode_to_spike_tensor()` should have this logical shape:

```python
{
    "addresses": list[int],
    "timestamps": list[int],
    "relative_timestamps_us": list[int],
    "counts": int,
    "n_bins": int,
    "spike_tensor": list[list[int]],
    "shape": [height, width, 2],
}
```

# Reference Notes

- The input is a structured NumPy array with fields equivalent to `x`, `y`, `p`, and `t`.
- `timestamps` in the payload are absolute timestamps from the input batch.
- `relative_timestamps_us` are derived values, not replacements for `timestamps`.
- The large execution slice should stay centered on event validation and canonicalization, not on framework-specific tensors or dataset SDK wrappers.
