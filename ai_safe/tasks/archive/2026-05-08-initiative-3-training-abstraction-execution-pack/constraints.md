# Constraints

## Allowed Dependencies

- Python standard library only

## Behavior Rules

- Do not change public method names given in this packet.
- Normalize backend names and training modes with `strip().lower()`.
- Reject duplicate normalized backend registrations.
- Reject explicit blank backend names after normalization.
- Reject explicit blank training modes after normalization.
- Keep dispatch side-effect free.
- Preserve payload passthrough without mutation.

## Scope Rules

- Do not import external training frameworks.
- Do not add I/O, telemetry, networking, or filesystem scanning.
- Do not implement real ANN-to-SNN conversion logic in this slice.
- Do not invent auto-fallback behavior for unsupported modes.

## Style Rules

- Prefer small helpers for normalization and validation.
- Keep control flow explicit and readable.
- Add comments only where validation order is non-obvious.

## Safety Rules

- Fail clearly for unsupported backends or modes.
- If requirements conflict, report the conflict instead of guessing.

## Output Rules

- Return unified diffs.
- State whether the repo-mirroring semantics were followed exactly.
