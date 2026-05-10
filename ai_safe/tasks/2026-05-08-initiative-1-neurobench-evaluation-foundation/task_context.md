# STATUS: PARTLY IMPLEMENTED (2026-05-10)
# Goal


Implement the requested behavior using only the sanitized context in this packet.

# Deliverable

Return a unified diff or a small set of unified diffs against the provided stub files.

# Task Summary

Implement a coherent foundation slice for Native NeuroBench Integration. This slice should improve evaluation plumbing and result handling without attempting a full product rewrite. The key behaviors are:

- canonical metric normalization from heterogeneous backend payloads
- deterministic precedence rules for nested result containers
- safer fail-closed handling for invalid present metrics
- small benchmark runner cleanup to use the canonical helper
- consistent target-comparison metric extraction behavior
- focused unit coverage for precedence, defaults, string numerics, and invalid values

This task should stop before frontend redesign, report-generation overhaul, or suite-wide contract changes.

# Required Semantics To Mirror

- If `results` exists and is a mapping, it wins over `metrics`.
- Else if `metrics` exists and is a mapping, use it.
- Else use the top-level payload.
- Canonical output keys are exactly:
  - `assertions_passed`
  - `assertions_failed`
  - `latency_ms`
  - `energy_uj`
  - `accuracy`
  - `mujoco_steps`
- Missing canonical keys default to `0.0`.
- Present invalid numeric values fail closed.
- Boolean values are invalid metrics even though they are numeric-like in Python.
- Unknown keys may exist in input payloads but must not appear in canonical output.
- Runner integration should keep returning the same canonical metric dict shape to callers.

# What You Are Allowed To Use

- Only the files and interfaces included in this packet
- Python standard library

# What You Must Not Assume

- Hidden benchmark helpers exist
- Schema changes outside the provided surfaces are allowed
- Frontend or report layers are part of this task

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

- Metric normalization is canonical and deterministic.
- Benchmark-runner integration uses the helper rather than inlining the same logic repeatedly.
- Tests cover precedence, defaults, invalid values, and integration behavior.
- The task stays within the bounded evaluation-foundation slice.
