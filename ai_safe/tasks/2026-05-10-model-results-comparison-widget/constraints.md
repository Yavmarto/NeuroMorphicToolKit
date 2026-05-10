# Constraints

## Allowed Dependencies

- Flutter framework
- `flutter_test`

## Behavior Rules

- Do not change public signatures.
- If `rows` is empty, render an empty state message.
- Each row must show the model label.
- Cached rows must show at least duration, motor spikes, and latency when values are available.
- Uncached rows must show a plain “Not run” label.
- Tapping a row must call `onSelected` with the row id.
- The active row must be visually distinct using only basic Material styling.

## Style Rules

- Keep layout straightforward and testable.
- Avoid custom painters.
- Prefer composition of simple widgets.

## Safety Rules

- No app-specific dependencies.
- No network or file I/O.
- No state management packages.

## Output Rules

- Return a unified diff if patching is requested.
- If the packet is underspecified, complete the safe subset and list assumptions separately.
