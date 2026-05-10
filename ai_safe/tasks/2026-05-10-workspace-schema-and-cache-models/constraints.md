# Constraints

## Allowed Dependencies

- Dart standard library
- `package:test/test.dart`

## Behavior Rules

- Do not change public signatures.
- Use only manual JSON mapping.
- Missing optional fields must decode to the default constructor values.
- Missing required collection fields should decode as empty collections where the interface allows it.
- `scrollOffset` and `durationSeconds` must accept integer or floating JSON numbers.
- Preserve `simulationCache` exactly when round-tripping.
- Keep output JSON deterministic.

## Style Rules

- Keep model code simple and explicit.
- Avoid code generation.

## Safety Rules

- Do not add provider logic, file I/O, or UI code.
- Do not create global state.

## Output Rules

- Return a unified diff if patching is requested.
- If the packet is underspecified, complete the safe subset and list assumptions separately.
