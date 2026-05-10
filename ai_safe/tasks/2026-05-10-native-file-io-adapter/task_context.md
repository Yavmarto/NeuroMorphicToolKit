# Goal

Implement a small Flutter/Dart adapter surface for opening and saving text files and JSON workspace files on native platforms, with tests driven by an injectable backend interface.

# Deliverable

Return a unified diff against the provided stub files if possible.

# Task Summary

Implement a narrow file adapter layer for a desktop/mobile Flutter app. The adapter must support opening one or more text files, opening a workspace JSON file, saving plain text, and saving workspace JSON. The real repository will connect this adapter to platform-specific picker APIs later, so this packet focuses on interfaces, return types, validation, and testable control flow only.

# Required Semantics To Mirror

- Opening text files may return zero, one, or many files.
- Opening a workspace file returns either a parsed JSON payload or `null` when the user cancels.
- Saving returns a result object that records whether the operation succeeded, was cancelled, or failed.
- Do not silently write to an implicit app-documents location.
- If the backend reports cancellation, preserve it as cancellation instead of treating it as failure.

# What You Are Allowed To Use

- Only the files and interfaces included in this packet
- Dart standard library
- `package:test/test.dart`

# What You Must Not Assume

- Hidden repository helpers exist
- A specific picker plugin exists
- UI widgets are available

# Required Output Format

Use this exact structure:

## Assumptions

- List any assumption that was necessary.

## Implementation

Provide the code or patch.

## Validation Notes

- Explain how the implementation satisfies the examples and constraints.

## Open Questions

- List only questions that block correctness.

# Completion Criteria

- The code matches the interfaces exactly.
- The code satisfies the examples exactly.
- The code respects all constraints.
- Any required repo-mirroring semantics are preserved exactly.
- The response does not request additional repository context unless correctness is impossible without it.
