# Examples And Acceptance Tests

Provide exact examples whenever possible. The better this file is, the less follow-up and token waste you will have.

## Input/Output Examples

### Example 1

Input:

```python
DataPayload(identifier="a", values=[1.0, 2.0, 3.0, 4.0])
```

Expected output:

```python
3.85
```

### Example 2

Input:

```python
DataPayload(identifier="b", values=[])
```

Expected behavior:

```text
Raise ValueError with a clear message that values cannot be empty.
```

## Edge Cases

- Empty collections
- Duplicate values
- Null or non-finite values if relevant
- Ordering guarantees if relevant
- Minimum and maximum supported sizes
- Fail-closed cases that must raise instead of approximating
- Warning-producing cases if the implementation distinguishes exact vs approximate behavior

## Acceptance Checklist

- Matches all stated outputs
- Handles all stated edge cases
- Preserves public signatures
- Uses only allowed dependencies
- Preserves any exact classification, warning, or fail-closed behavior listed in the packet
