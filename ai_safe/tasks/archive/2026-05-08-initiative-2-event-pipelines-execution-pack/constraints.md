# Constraints

## Allowed Dependencies

- Python standard library
- `numpy`

## Behavior Rules

- Do not change public method names given in this packet.
- Do not silently clip invalid coordinates.
- Do not silently sort or reorder events.
- Do not silently coerce non-monotonic timestamps into valid order.
- Preserve backward-compatible payload keys.
- Return count tensors as integers.
- Keep empty input handling explicit and stable.

## Scope Rules

- Do not add real dataset SDK dependencies.
- Do not add network calls, telemetry, persistence, or filesystem scanning.
- Do not attempt to implement every downstream replay or benchmark consumer in this task.
- Stay within the event canonicalization and event-batching slice.

## Style Rules

- Prefer explicit validation helpers over clever vectorized one-liners when control flow becomes unclear.
- Add brief comments only where fail-closed behavior is non-obvious.
- Keep the implementation honest about what is validated versus what is simply transformed.

## Safety Rules

- If a required field is missing from the structured batch, fail clearly instead of guessing alternate field names.
- If dimensions are invalid or non-positive, fail clearly.
- If requirements conflict, report the conflict instead of guessing.

## Output Rules

- Return unified diffs.
- State whether the repo-mirroring semantics were followed exactly.
