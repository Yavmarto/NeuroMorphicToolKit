# STATUS: PARTLY IMPLEMENTED (2026-05-10) - Simulate route pending
# Goal


Implement the requested behavior using only the sanitized context in this packet.

# Deliverable

Return a unified diff or a small set of unified diffs against the provided stub files.

# Task Summary

Normalize how CNL diagnostics are surfaced across user-facing backend routes. The current parser already emits structured error details with fields such as `code`, `message`, `hint`, `examples`, `line`, and `raw`, but several routes collapse failures into plain strings or `messages` arrays. This packet asks for a bounded implementation slice that preserves structured diagnostics consistently across route-level failure paths without redesigning the parser, validator, or lowering stack.

# Required Semantics To Mirror

- Parse failures already have a richer structured shape and that truth must be preserved.
- The implementation must not convert a structured parse failure into a less informative string if the route can return the structured form safely.
- The implementation must not invent success when parsing, validation, or lowering failed.
- The implementation must distinguish at least these error families:
  - parse failure
  - validation failure
  - lowering failure
  - backend-support or deployability failure
- Existing route semantics may stay fail-closed, but the payload shape should become more consistent and more actionable.

# What You Are Allowed To Use

- Only the files and interfaces included in this packet
- Python standard library
- FastAPI and Pydantic types already referenced in the stubbed interfaces

# What You Must Not Assume

- Hidden UI behavior exists to repair an inconsistent backend payload
- A full architecture rewrite is allowed
- Parser heuristics or validation logic should be redesigned in this slice

# Required Output Format

Use this exact structure:

## Assumptions

- List any assumption that was necessary.

## Implementation

Provide the patch or patches.

## Validation Notes

- Explain how the implementation satisfies the examples and constraints.

## Open Questions

- List only questions that block correctness.

# Completion Criteria

- Structured parse diagnostics survive through the targeted routes.
- Lowering and validation failures use a stable, inspectable error shape rather than ad hoc strings where possible.
- The patch is route-level and helper-level only, not a broad parser or planner redesign.
- The implementation stays fail-closed.
