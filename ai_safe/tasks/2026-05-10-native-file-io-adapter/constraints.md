# Constraints

## Allowed Dependencies

- Dart standard library
- `package:test/test.dart`

## Behavior Rules

- Do not change public signatures.
- `openTextFiles()` must return an empty list on user cancellation.
- `openWorkspaceFile()` must return `null` on user cancellation.
- If workspace file contents are not valid JSON, throw `FormatException`.
- If workspace file JSON is valid but not a top-level object, throw `FormatException`.
- `saveTextFile()` and `saveWorkspaceFile()` must preserve backend `SaveResult` values exactly.
- `saveWorkspaceFile()` must produce stable pretty JSON with an indent of two spaces and a trailing newline.

## Style Rules

- Keep the adapter small and readable.
- Add brief comments only for non-obvious logic.

## Safety Rules

- Do not add real file I/O.
- Do not add network calls or telemetry.
- Do not invent UI behavior.

## Output Rules

- Return a unified diff if patching is requested.
- If the packet is underspecified, complete the safe subset and list assumptions separately.
