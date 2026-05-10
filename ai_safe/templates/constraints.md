# Constraints

List the rules DeerFlow must follow exactly.

Suggested categories:

## Allowed Dependencies

- Standard library only

## Behavior Rules

- Do not change public signatures.
- Do not mutate input objects unless explicitly allowed.
- Handle empty inputs explicitly.
- Fail with clear errors for invalid inputs if required.
- Preserve any explicitly stated fail-closed behavior instead of silently approximating it.
- Preserve any explicitly stated warning or classification semantics exactly.

## Style Rules

- Keep functions pure where possible.
- Prefer readable control flow over clever optimizations.
- Add brief comments only for non-obvious logic.

## Safety Rules

- Do not invent missing hidden systems.
- Do not add telemetry, network calls, file I/O, or persistence unless requested.
- If requirements conflict, report the conflict instead of guessing.

## Output Rules

- Return a unified diff if patching is requested.
- If the task is underspecified, complete the safe subset and list assumptions separately.
- If the packet includes repo-mirroring semantics, say whether the implementation follows them exactly in the validation notes.
