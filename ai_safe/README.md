# AI-Safe Task Kit

This directory contains templates and instructions for preparing sanitized task packets for external agent systems such as DeerFlow when the backing model or service should not receive proprietary repository context.

The workflow is intentionally split into stages:

1. Private planning and scoping in the real repository.
2. Sanitized execution in DeerFlow.
3. Local reintegration, repo-grounding, and verification after DeerFlow returns.

Use this kit when you want help writing isolated code without exposing implementation details, internal architecture, logs, secrets, or domain-specific language.

## Files

- `templates/task_context.md`: Main task packet template for DeerFlow.
- `templates/interfaces.md`: Public signatures, data shapes, and stubs only.
- `templates/constraints.md`: Non-negotiable coding and behavior requirements.
- `templates/examples.md`: Input/output examples and acceptance tests.
- `DEERFLOW_PROMPT.md`: Reusable DeerFlow handoff prompt.
- `DEERFLOW_USAGE.md`: Step-by-step workflow for preparing and using sanitized task packets.

## Core Rules

- Never copy real secrets, internal logs, stack traces, or production data into these files.
- Replace proprietary names with neutral placeholders when names reveal IP.
- Share interfaces and behavior, not implementations.
- Prefer isolated tasks that can be expressed with exact input/output expectations.
- Preserve the exact semantics DeerFlow must mirror when the task depends on subtle behavior distinctions.
- Review DeerFlow output locally before integrating it into the real codebase.

## Recommended Packet Layout

For each task, create a dedicated folder such as:

```text
ai_safe/tasks/2026-05-08-filter-normalization/
  task_context.md
  interfaces.md
  constraints.md
  examples.md
  notes.md
```

Keep each packet narrowly scoped. If a task needs hidden architectural context to succeed, it is probably too large for this workflow and should be split further.

When a task must match existing in-repo behavior, pack that behavior explicitly into the task packet instead of expecting DeerFlow to infer it from a stub alone. In practice, the best packets include:

- the exact acceptance slice from the local plan
- the precise examples and edge cases that define correctness
- any fail-closed or warning semantics that must be preserved
- the local verification command that will be used after reintegration
