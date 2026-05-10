# Examples And Acceptance Tests

## Input/Output Examples

### Example 1: Deterministic Address Mapping

Input:

```python
encoder = EventEncoder(width=2, height=1)
addresses = encoder.map_to_neuron_address(
    np.array([0, 0]),
    np.array([0, 0]),
    np.array([-7, 9]),
)
```

Expected output:

```python
addresses.tolist() == [0, 1]
```

### Example 2: Two Bins With Repeated Address Hits

Input:

```python
events = np.array(
    [
        (1, 0, 1, 100),
        (1, 0, 1, 140),
        (0, 1, 0, 230),
    ],
    dtype=[("x", "i4"), ("y", "i4"), ("p", "i4"), ("t", "i8")],
)
result = encoder.bin_events(events, bin_width_us=100)
```

Expected output:

```python
result.addresses == [3, 3, 4]
result.relative_timestamps_us == [0, 40, 130]
result.counts == 3
result.n_bins == 2
result.spike_tensor == [
    [0, 0, 0, 2, 0, 0, 0, 0],
    [0, 0, 0, 0, 1, 0, 0, 0],
]
```

### Example 3: Canonical Payload Preserves Old And New Fields

Input:

```python
payload = encoder.encode_to_spike_tensor(events, bin_width_us=100)
```

Expected output:

```python
payload["addresses"] == [3, 3, 4]
payload["timestamps"] == [100, 140, 230]
payload["relative_timestamps_us"] == [0, 40, 130]
payload["counts"] == 3
payload["n_bins"] == 2
payload["shape"] == [2, 2, 2]
payload["spike_tensor"] == [
    [0, 0, 0, 2, 0, 0, 0, 0],
    [0, 0, 0, 0, 1, 0, 0, 0],
]
```

### Example 4: Empty Input

Input:

```python
empty = np.array([], dtype=[("x", "i4"), ("y", "i4"), ("p", "i4"), ("t", "i8")])
payload = encoder.encode_to_spike_tensor(empty)
```

Expected output:

```python
payload == {
    "addresses": [],
    "timestamps": [],
    "relative_timestamps_us": [],
    "counts": 0,
    "n_bins": 0,
    "spike_tensor": [],
    "shape": [2, 2, 2],  # adjust width/height to the encoder instance used in the test
}
```

### Example 5: Invalid Coordinate Fails Closed

Input:

```python
bad_events = np.array(
    [(2, 0, 1, 0)],
    dtype=[("x", "i4"), ("y", "i4"), ("p", "i4"), ("t", "i8")],
)
encoder.bin_events(bad_events, bin_width_us=100)
```

Expected behavior:

```text
Raise EventBinningError with a clear message naming the invalid coordinate.
```

### Example 6: Decreasing Timestamp Fails Closed

Input:

```python
bad_events = np.array(
    [(0, 0, 1, 50), (0, 0, 1, 49)],
    dtype=[("x", "i4"), ("y", "i4"), ("p", "i4"), ("t", "i8")],
)
encoder.bin_events(bad_events, bin_width_us=10)
```

Expected behavior:

```text
Raise EventBinningError with a clear message about timestamp ordering.
```

### Example 7: Invalid Bin Width Fails Closed

Input:

```python
encoder.bin_events(events, bin_width_us=0)
```

Expected behavior:

```text
Raise EventBinningError because bin width must be positive.
```

## Edge Cases

- Events exactly on a bin boundary land in the later bin except for the first event, which always has relative timestamp `0`.
- Negative polarity values normalize to `0`.
- Positive polarity values normalize to `1`.
- Multiple events may increment the same address in the same bin.
- Structured batches missing required fields should fail clearly.

## Acceptance Checklist

- Matches all stated outputs
- Uses only allowed dependencies
- Preserves exact address mapping
- Preserves fail-closed validation behavior
- Preserves backward-compatible payload fields
