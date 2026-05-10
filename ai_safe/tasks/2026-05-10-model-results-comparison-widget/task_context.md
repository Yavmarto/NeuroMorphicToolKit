# Goal

Implement a standalone Flutter widget that compares multiple model summaries and highlights the active row.

# Deliverable

Return a unified diff against the provided stub files if possible.

# Task Summary

Build a presentational comparison widget for a Flutter app. The widget receives a list of model summary rows, shows cached or uncached state for each row, and exposes a callback when a row is selected. The task is UI-only and must not depend on application state libraries or backend services.

# Required Semantics To Mirror

- Rows with cached results display summary metrics.
- Rows without cached results display a clear “not run” state.
- The active model is visually distinct.
- Row tap invokes the provided callback with the selected id.

# What You Are Allowed To Use

- Only the files and interfaces included in this packet
- Flutter framework
- `flutter_test`

# What You Must Not Assume

- Riverpod exists
- Design system helpers exist
- Hidden theme extensions exist

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
