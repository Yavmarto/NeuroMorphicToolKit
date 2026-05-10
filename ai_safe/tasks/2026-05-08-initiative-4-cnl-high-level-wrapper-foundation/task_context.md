# Goal

Implement the requested behavior using only the sanitized context in this packet.

# Deliverable

Return a unified diff or a small set of unified diffs against the provided stub files.

# Task Summary

Implement a coherent foundation slice for CNL High-Level Abstractions. This slice should provide thin, honest, high-level wrappers over the existing unified pipeline rather than inventing a full training runtime. The key behaviors are:

- a small façade class or helper surface for compile/evaluate-style workflows
- wrapper methods that call the existing pipeline rather than bypassing it
- stable result shaping for the wrapper return values
- clear error propagation or lightweight error shaping
- one or two example-oriented usage surfaces or tests
- focused unit coverage for wrapper behavior

This task should stop before introducing real `fit()` semantics, backend-specific training logic, or broad parser/IR redesign.

# Required Semantics To Mirror

- High-level methods must remain thin wrappers over the existing unified pipeline.
- Wrapper methods must not bypass validation, planning, or export checks already performed by the underlying pipeline.
- Wrapper naming may be simple and user-oriented, but the behavior must stay honest about the underlying execution.
- If the underlying pipeline reports failure, the wrapper must not transform that into a false success.
- The wrapper should make compile/evaluate flows easier to call, not semantically different.
- Return values may be shaped for convenience, but they must preserve the truth of the underlying pipeline result.

# What You Are Allowed To Use

- Only the files and interfaces included in this packet
- Python standard library

# What You Must Not Assume

- Hidden high-level API surfaces already exist
- Real training loop semantics are required
- Broad CLI or frontend rewrites are part of this slice

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

- The wrapper is honest, thin, and deterministic.
- Compile/evaluate-style calls are easier to invoke than the raw pipeline entrypoint.
- The wrapper does not claim semantics beyond the underlying pipeline.
- Tests or examples prove the façade behavior.
