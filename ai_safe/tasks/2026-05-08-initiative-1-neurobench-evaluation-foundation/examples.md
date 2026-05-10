# Examples And Acceptance Tests

## Input/Output Examples

### Example 1: Flat Payload

Input:

```python
payload = {
    "assertions_passed": 3,
    "assertions_failed": 1,
    "latency_ms": 12.5,
    "energy_uj": "42.0",
    "accuracy": 0.97,
}
result = normalize_metrics(payload)
```

Expected output:

```python
result.values == {
    "assertions_passed": 3.0,
    "assertions_failed": 1.0,
    "latency_ms": 12.5,
    "energy_uj": 42.0,
    "accuracy": 0.97,
    "mujoco_steps": 0.0,
}
```

### Example 2: `results` Beats `metrics`

Input:

```python
payload = {
    "results": {"assertions_passed": "2", "latency_ms": 8, "accuracy": 0.5},
    "metrics": {"assertions_passed": 999},
}
result = normalize_metrics(payload)
```

Expected output:

```python
result.values["assertions_passed"] == 2.0
result.values["latency_ms"] == 8.0
result.values["accuracy"] == 0.5
```

### Example 3: `metrics` Fallback

Input:

```python
payload = {"metrics": {"energy_uj": 7, "mujoco_steps": "18"}}
result = normalize_metrics(payload)
```

Expected output:

```python
result.values == {
    "assertions_passed": 0.0,
    "assertions_failed": 0.0,
    "latency_ms": 0.0,
    "energy_uj": 7.0,
    "accuracy": 0.0,
    "mujoco_steps": 18.0,
}
```

### Example 4: Invalid Present Metric Fails Closed

Input:

```python
payload = {"metrics": {"latency_ms": "fast"}}
normalize_metrics(payload)
```

Expected behavior:

```text
Raise MetricNormalizationError with a clear message naming `latency_ms`.
```

### Example 5: Boolean Metric Is Invalid

Input:

```python
payload = {"accuracy": True}
normalize_metrics(payload)
```

Expected behavior:

```text
Raise MetricNormalizationError because booleans are not valid numeric metrics.
```

### Example 6: Runner Integration

Input:

```python
raw_response = {
    "results": {"assertions_passed": "2", "latency_ms": 8, "accuracy": 0.5},
    "metrics": {"assertions_passed": 999},
}
```

Expected behavior:

```text
The runner returns a plain canonical metric dict with normalized float values and defaults for missing keys.
```

## Edge Cases

- `results` or `metrics` keys that are present but not mappings are ignored for container selection.
- Empty payload returns all canonical keys with `0.0`.
- Unknown keys do not appear in output.

## Acceptance Checklist

- Matches all stated outputs
- Uses only allowed dependencies
- Preserves exact container precedence
- Preserves runner-facing canonical dict behavior
