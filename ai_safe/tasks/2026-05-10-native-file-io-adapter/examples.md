# Examples And Acceptance Tests

## Input/Output Examples

### Example 1

Input:

- Backend `openTextFiles()` returns `null`

Expected output:

- `FileAdapter.openTextFiles()` returns `[]`

### Example 2

Input:

- Backend `openWorkspaceFile()` returns:

```dart
OpenedTextFile(
  name: 'session.workspace.json',
  text: '{ "version": 1, "files": [] }',
  path: '/tmp/session.workspace.json',
)
```

Expected output:

```dart
OpenedWorkspaceFile(
  name: 'session.workspace.json',
  payload: <String, Object?>{
    'version': 1,
    'files': <Object?>[],
  },
  path: '/tmp/session.workspace.json',
)
```

### Example 3

Input:

- `saveWorkspaceFile(suggestedName: 'session.workspace.json', payload: {'version': 1})`

Expected behavior:

- Backend `saveWorkspaceFile()` is called with contents exactly:

```json
{
  "version": 1
}
```

with a final trailing newline.

### Example 4

Input:

- Backend `openWorkspaceFile()` returns text `[]`

Expected behavior:

- Throw `FormatException` because the top-level JSON value is not an object.

## Edge Cases

- Empty text file list
- Cancelled workspace open
- Invalid JSON text
- JSON arrays instead of JSON objects
- Save failure returned by backend

## Acceptance Checklist

- Matches all stated outputs
- Handles all stated edge cases
- Preserves public signatures
- Uses only allowed dependencies
- Preserves exact cancellation and formatting semantics
