from __future__ import annotations

import numpy as np
import pytest

from neurosense.app.services.event_encoder import EventBinningError, EventEncoder


def _event_batch(rows: list[tuple[int, int, int, int]]) -> np.ndarray:
    return np.array(rows, dtype=[("x", "i4"), ("y", "i4"), ("p", "i4"), ("t", "i8")])


def test_map_to_neuron_address_normalizes_polarity() -> None:
    encoder = EventEncoder(width=2, height=1)
    addresses = encoder.map_to_neuron_address(
        np.array([0, 0], dtype=np.int64),
        np.array([0, 0], dtype=np.int64),
        np.array([-7, 9], dtype=np.int64),
    )

    assert addresses.tolist() == [0, 1]


def test_bin_events_produces_dense_spike_tensor_summary() -> None:
    encoder = EventEncoder(width=2, height=2)
    events = _event_batch(
        [
            (1, 0, 1, 100),
            (1, 0, 1, 140),
            (0, 1, 0, 230),
        ]
    )

    result = encoder.bin_events(events, bin_width_us=100)

    assert result.addresses == [3, 3, 4]
    assert result.relative_timestamps_us == [0, 40, 130]
    assert result.counts == 3
    assert result.n_bins == 2
    assert result.spike_tensor == [
        [0, 0, 0, 2, 0, 0, 0, 0],
        [0, 0, 0, 0, 1, 0, 0, 0],
    ]


def test_encode_to_spike_tensor_preserves_existing_fields_and_adds_binned_output() -> None:
    encoder = EventEncoder(width=2, height=2)
    events = _event_batch(
        [
            (1, 0, 1, 100),
            (1, 0, 1, 140),
            (0, 1, 0, 230),
        ]
    )

    result = encoder.encode_to_spike_tensor(events, bin_width_us=100)

    assert result["addresses"] == [3, 3, 4]
    assert result["timestamps"] == [100, 140, 230]
    assert result["relative_timestamps_us"] == [0, 40, 130]
    assert result["counts"] == 3
    assert result["n_bins"] == 2
    assert result["shape"] == [2, 2, 2]
    assert result["spike_tensor"] == [
        [0, 0, 0, 2, 0, 0, 0, 0],
        [0, 0, 0, 0, 1, 0, 0, 0],
    ]


def test_bin_events_rejects_invalid_coordinate() -> None:
    encoder = EventEncoder(width=2, height=2)
    events = _event_batch([(2, 0, 1, 0)])

    with pytest.raises(EventBinningError, match=r"x=2 outside valid range"):
        encoder.bin_events(events, bin_width_us=100)


def test_bin_events_rejects_decreasing_timestamps() -> None:
    encoder = EventEncoder(width=1, height=1)
    events = _event_batch([(0, 0, 1, 50), (0, 0, 1, 49)])

    with pytest.raises(EventBinningError, match=r"timestamp 49 < previous timestamp 50"):
        encoder.bin_events(events, bin_width_us=10)


def test_bin_events_rejects_non_positive_bin_width() -> None:
    encoder = EventEncoder(width=1, height=1)
    events = _event_batch([(0, 0, 1, 50)])

    with pytest.raises(EventBinningError, match=r"bin_width_us must be positive"):
        encoder.bin_events(events, bin_width_us=0)


def test_encode_to_spike_tensor_handles_empty_input() -> None:
    encoder = EventEncoder(width=3, height=2)
    events = _event_batch([])

    result = encoder.encode_to_spike_tensor(events)

    assert result == {
        "addresses": [],
        "timestamps": [],
        "relative_timestamps_us": [],
        "counts": 0,
        "n_bins": 0,
        "spike_tensor": [],
        "shape": [2, 3, 2],
    }
