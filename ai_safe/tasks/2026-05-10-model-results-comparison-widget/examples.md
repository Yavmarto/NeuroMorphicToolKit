# Examples And Acceptance Tests

## Input/Output Examples

### Example 1

Input rows:

```dart
const <ModelResultSummaryRow>[
  ModelResultSummaryRow(
    id: 'a',
    label: 'Model A',
    hasCachedResult: true,
    durationSeconds: 1.0,
    motorSpikeCount: 12,
    latencyMs: 18.5,
  ),
  ModelResultSummaryRow(
    id: 'b',
    label: 'Model B',
    hasCachedResult: false,
  ),
]
```

Expected behavior:

- Both model labels render.
- Row A shows summary metrics.
- Row B shows `Not run`.

### Example 2

Input:

- `activeId == 'a'`

Expected behavior:

- The row for `a` is visually distinct from row `b`.

### Example 3

Input:

- User taps row `b`

Expected behavior:

- `onSelected('b')` is invoked exactly once.

### Example 4

Input:

- `rows == const []`

Expected behavior:

- Render an empty state message such as `No models to compare`.

## Edge Cases

- Empty rows
- Null metrics on cached rows
- Narrow layout widths
- Long model labels

## Acceptance Checklist

- Matches all stated outputs
- Handles all stated edge cases
- Preserves public signatures
- Uses only allowed dependencies
- Keeps widget presentation-only
