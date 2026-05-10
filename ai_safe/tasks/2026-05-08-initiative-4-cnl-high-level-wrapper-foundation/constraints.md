# Constraints

## Allowed Dependencies

- Python standard library only

## Behavior Rules

- Do not implement real `fit()` behavior in this slice.
- Do not bypass the existing unified pipeline.
- Do not claim success when the underlying pipeline failed.
- Keep wrapper return types small and honest.
- Preserve useful error text where available.

## Scope Rules

- Do not redesign the parser, IR, planner, or exporter.
- Do not add framework-specific training execution.
- Do not change frontend flows.

## Style Rules

- Keep wrappers thin.
- Prefer explicit result shaping over magical convenience.
- Add comments only where the truth-preserving mapping is non-obvious.

## Safety Rules

- If the underlying result shape is ambiguous, use the smallest safe interpretation and state assumptions.
- If requirements conflict, report the conflict instead of guessing.

## Output Rules

- Return unified diffs.
- State whether the repo-mirroring semantics were followed exactly.
