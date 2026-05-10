# Goal

Implement the requested behavior using only the sanitized context in this packet.

# Deliverable

Return a unified diff or a small set of unified diffs against the provided stub files.

# Task Summary

Implement a coherent first execution slice for the SNN Training Abstraction Layer. This slice should create the stable local foundation for “bring your own training” without pretending to integrate every framework end-to-end. The key behaviors are:

- adapter capability modeling
- case-insensitive backend selection
- normalized training-mode validation
- deterministic dispatch to the selected adapter
- fail-closed handling for unknown backends, duplicate registrations, and unsupported modes
- a minimal example adapter seam that remains side-effect free
- focused unit coverage for registry semantics

This task should stop before real framework imports, real model execution, or broad ANN-to-SNN pipeline orchestration.

# Required Semantics To Mirror

- Backend names are normalized with `strip().lower()`.
- Training modes are normalized with `strip().lower()`.
- Unknown backends fail closed.
- Duplicate backend registrations after normalization fail closed.
- Explicit blank backend names or training modes fail closed.
- If no training mode is supplied, the adapter default mode is used.
- Dispatch must call the selected adapter with a request whose `training_mode` is the resolved normalized mode.
- Capability listing should be deterministic and sorted by normalized backend name.
- Payload passthrough should remain untouched.

# What You Are Allowed To Use

- Only the files and interfaces included in this packet
- Python standard library

# What You Must Not Assume

- Hidden plugin discovery exists
- Framework-specific training libraries are available
- Runtime model execution is part of this task
- ANN-to-SNN conversion implementation is in scope for this slice

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

- Adapter selection and mode validation are deterministic.
- The registry is side-effect free.
- A minimal adapter seam is present without importing external frameworks.
- Unit tests cover the fail-closed semantics and normalization rules.
- The implementation stays within the bounded foundation slice for Initiative 3.
