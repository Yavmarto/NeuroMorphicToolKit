# Constraints

## Allowed Dependencies

- Python standard library only

## Behavior Rules

- Do not change the canonical metric key set.
- Do not mutate input payloads.
- Ignore unknown keys.
- Default missing canonical keys to `0.0`.
- Reject present invalid metric values with a clear error.
- Reject booleans for canonical numeric fields.
- Keep the runner's returned metric dict shape stable.

## Scope Rules

- Do not redesign report generation.
- Do not modify frontend models.
- Do not introduce new persistence or network behavior beyond the existing runner call path.

## Style Rules

- Keep the helper pure.
- Prefer explicit control flow.
- Add comments only where fail-closed behavior is non-obvious.

## Safety Rules

- Do not invent extra precedence rules.
- Do not silently coerce obviously invalid values.
- If requirements conflict, report the conflict instead of guessing.

## Output Rules

- Return unified diffs.
- State whether the repo-mirroring semantics were followed exactly.
