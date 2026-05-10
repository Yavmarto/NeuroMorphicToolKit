# Goal

Implement versioned Dart data models for a multi-file workspace document and per-file simulation cache, with JSON round-trip coverage.

# Deliverable

Return a unified diff against the provided stub files if possible.

# Task Summary

Create pure data models for a workspace JSON format that contains multiple editable files plus cached simulation results per file. This packet is limited to model classes, JSON encoding/decoding, copy helpers, and deterministic round-trip tests. Real app state management and provider wiring are out of scope.

# Required Semantics To Mirror

- The workspace document is versioned.
- Each file entry may or may not have cached simulation data.
- Simulation cache belongs to a file entry, not to the workspace globally.
- Missing optional fields must decode safely using documented defaults.
- Unknown top-level keys may be ignored.

# What You Are Allowed To Use

- Only the files and interfaces included in this packet
- Dart standard library
- `package:test/test.dart`

# What You Must Not Assume

- Riverpod exists
- Generated serializers exist
- Additional hidden models exist

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
