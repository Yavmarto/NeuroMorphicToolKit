---
name: deerflow-safe-handoff
description: Prepare sanitized task packets for DeerFlow or other external agent services when repository context, IP, logs, or secrets must not be shared. Use this skill when the user wants to strip context, create interface-only handoff files, or outsource an isolated coding task safely via the ai_safe templates in this repo, while preserving enough behavioral truth for accurate reintegration.
allowed-tools: Read Bash
---

# DeerFlow Safe Handoff

Use this skill when preparing work for DeerFlow or another external agent service that should only receive sanitized, minimal context.

This skill is for **packet preparation**, not direct implementation in the real target files.

The preferred loop is:

1. Plan and scope locally in the real repository.
2. Build a sanitized packet that preserves the exact behavior DeerFlow must follow.
3. Let DeerFlow draft the isolated implementation outside the repo.
4. Reintegrate locally with repo-grounding, verification, and any contract-specific fixes.

## Use It For

- Isolated functions
- Small adapters with exact inputs and outputs
- Validation helpers
- Small UI components with mock data
- Test generation from explicit examples
- Narrow bug fixes with a known expected result

## Do Not Use It For

- Cross-cutting refactors
- Tasks that depend on hidden runtime behavior
- Work that requires real logs, internal architecture, or proprietary algorithms
- Broad “understand this subsystem” requests

If the task does not fit, split it into smaller packets or tell the user why this workflow will be unreliable.

## Files To Use

The starter kit already exists in this repo:

- `ai_safe/README.md`
- `ai_safe/DEERFLOW_USAGE.md`
- `ai_safe/DEERFLOW_PROMPT.md`
- `ai_safe/templates/task_context.md`
- `ai_safe/templates/interfaces.md`
- `ai_safe/templates/constraints.md`
- `ai_safe/templates/examples.md`

Read `ai_safe/DEERFLOW_USAGE.md` when you need the full workflow. Use the template files directly when creating a packet.

## Workflow

1. Inspect the real repository locally and identify the smallest isolated unit of work.
2. Extract only the minimum safe context:
   - function signatures
   - data structures
   - sanitized stubs
   - exact behavior
   - explicit examples and edge cases
   - the relevant plan or acceptance slice, rewritten in sanitized form if needed
   - the exact fail-closed, warning, or classification behavior if correctness depends on it
   - the local verification command the integrator must run after DeerFlow returns
3. Remove or replace:
   - proprietary logic
   - secrets
   - internal logs or traces
   - production data
   - customer or partner identifiers
   - IP-revealing names when neutral names would work
4. Create a task folder under `ai_safe/tasks/<date>-<slug>/`.
5. Fill these files:
   - `task_context.md`
   - `interfaces.md`
   - `constraints.md`
   - `examples.md`
6. If useful, add `notes.md` with sanitized reviewer hints only.
7. Make the packet honest about what DeerFlow can and cannot know:
   - if behavior must mirror an in-repo implementation, say so explicitly
   - if exact semantics matter, include them directly instead of summarizing loosely
   - if DeerFlow is producing a draft only, say that local reintegration will perform repo-grounding
   - if the task would still rely on hidden architecture, split it further
8. Produce a short handoff note telling the user:
   - which task folder was created under `ai_safe/tasks/`
   - to upload those files plus the prompt from `ai_safe/DEERFLOW_USAGE.md`
   - what local repo-grounding step still remains after DeerFlow returns

## Packet Rules

- Share interfaces and behavior, not implementations.
- Keep the packet small enough that a careful engineer could solve it without broader repo access.
- Prefer exact examples over long prose.
- Prefer exact repo-mirroring semantics over broad summaries when correctness depends on subtle distinctions.
- If a name reveals sensitive domain meaning, rename it in the packet and note that local reintegration must restore the real names.
- Never paste `.env` contents, credentials, raw stack traces, or database contents.
- Do not ask DeerFlow to infer the real repository architecture from neutral names alone.
- If the task depends on matching existing repo behavior, include that behavior in the packet instead of expecting DeerFlow to reconstruct it.

## Output Expectations

When using this skill, your goal is to leave the repo with a ready-to-upload sanitized packet.

Default deliverables:

- Completed packet files based on the templates
- A short summary of what was sanitized
- A short note on any assumptions or places where integration tax is likely
- A note saying whether DeerFlow is expected to produce a final isolated implementation or a draft that still needs repo alignment

## Quality Bar

Before finishing, confirm:

- The task is narrow enough for an interface-only workflow
- The packet contains no obvious secrets or proprietary implementation details
- The examples are specific enough to reduce follow-up
- The DeerFlow prompt can be used without extra explanation
- The packet includes enough behavioral truth that DeerFlow will not need to guess about exact semantics
- The local reintegration and verification step is explicitly acknowledged
