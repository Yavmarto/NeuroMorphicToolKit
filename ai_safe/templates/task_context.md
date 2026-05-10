# Goal

Implement the requested behavior using only the sanitized context in this packet.

# Deliverable

Return one of the following:

- A standalone implementation file
- A unified diff against the provided stub file
- A Markdown explanation plus code block if file patching is not available

# Task Summary

Describe the isolated task in one paragraph. Focus on behavior, not domain-specific background.

Example:
Implement `process_data` so it computes the 95th percentile of the provided values and returns the result as a float.

# Required Semantics To Mirror

List any exact behavior that must match the real repository after reintegration.

Examples:

- Classify connection lowering into the exact buckets listed below.
- Preserve fail-closed behavior for unsupported structured patterns.
- Emit warnings only for the approximate cases listed in `examples.md`.

If there is no existing behavior to mirror, say:

`No additional repo-mirroring semantics beyond the interfaces, constraints, and examples.`

# What You Are Allowed To Use

- Only the files and interfaces included in this packet
- Standard library unless the constraints file explicitly allows more

# What You Must Not Assume

- Hidden repository helpers exist
- Unshown business rules exist
- Proprietary architecture should be inferred from names

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
