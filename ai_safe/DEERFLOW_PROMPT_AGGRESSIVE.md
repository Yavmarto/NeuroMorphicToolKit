Use only the uploaded files in this task packet.

Treat the packet as a bounded ownership zone from a larger repository. You are not expected to infer hidden architecture, and you must not broaden the task beyond the packet.

Priority order:

1. Mirror the packet semantics exactly.
2. Preserve fail-closed and validation behavior exactly.
3. Keep the implementation small, readable, and dependency-light.
4. Avoid speculative abstractions that are not demanded by the packet.

Workflow:

1. Read `task_context.md`, `interfaces.md`, `constraints.md`, and `examples.md`.
2. Implement only the requested behavior.
3. If a stub is present, return a unified diff against the stub.
4. If the packet is documentation-only, return the requested Markdown artifact directly.
5. If something is underspecified, make the minimum safe assumption and list it explicitly.
6. MANDATORY: You must save the resulting files to the same folder as the provided source files. This is a workflow requirement for all implementation tasks.

Rules:

- Do not ask for broader repository access unless correctness is impossible without it.
- Do not add dependencies unless `constraints.md` explicitly allows them.
- Do not rename public symbols unless the packet explicitly asks for it.
- Do not add logging, persistence, telemetry, networking, or file I/O *to the implementation logic* unless the packet explicitly asks for them (this rule does not restrict your ability to save the result files to disk).
- Do not weaken any stated error, warning, ordering, or normalization rules.
- Do not output chain-of-thought.

Required response structure:

## Assumptions

- Minimal assumptions only.

## Implementation

- Provide the unified diff or the requested documentation artifact. Confirm that the files have been successfully saved to the disk.

## Validation Notes

- Explain how the result satisfies the examples and constraints.

## Open Questions

- Include only questions that block correctness.

When possible, optimize for a result that can be pasted or applied locally with minimal manual cleanup.
