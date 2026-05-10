# Examples And Acceptance Tests

## Input/Output Examples

### Example 1

Input JSON:

```json
{
  "version": 1,
  "savedAt": "2026-05-10T10:15:00Z",
  "files": [
    {
      "id": "file-a",
      "name": "A.cnl",
      "content": "alpha",
      "isDirty": false,
      "isUntitled": false
    },
    {
      "id": "file-b",
      "name": "B.cnl",
      "content": "beta",
      "simulationCache": {
        "status": "completed",
        "savedAt": "2026-05-10T10:16:00Z",
        "durationSeconds": 1.5,
        "resultPayload": {
          "summary": {
            "motorSpikeCount": 12
          }
        }
      }
    }
  ],
  "activeFileId": "file-b"
}
```

Expected behavior:

- Decodes successfully.
- `files[1].simulationCache` is not null.
- `files[0].simulationCache` is null.
- `activePanel` defaults to `parsed_specs`.
- `selectedTarget` defaults to `teensy`.

### Example 2

Input object:

```dart
const WorkspaceDocument(
  version: 1,
  savedAtIso8601: '2026-05-10T10:15:00Z',
  files: <WorkspaceEntry>[
    WorkspaceEntry(
      id: 'file-a',
      name: 'A.cnl',
      content: 'alpha',
    ),
  ],
  activeFileId: 'file-a',
)
```

Expected behavior:

- `toJson()` includes `files`, `activeFileId`, `activePanel`, and `selectedTarget`.

### Example 3

Input JSON:

```json
{
  "version": 1,
  "savedAt": "2026-05-10T10:15:00Z",
  "files": [],
  "activeFileId": "missing",
  "activePanel": "comparison",
  "selectedTarget": "teensy"
}
```

Expected behavior:

- Decodes successfully with an empty `files` list.

## Edge Cases

- Empty workspace
- Integer JSON values for floating fields
- Missing optional fields
- Missing `simulationCache`
- Nested `resultPayload` maps

## Acceptance Checklist

- Matches all stated outputs
- Handles all stated edge cases
- Preserves public signatures
- Uses only allowed dependencies
- Keeps simulation data file-scoped
