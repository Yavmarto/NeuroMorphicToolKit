# Using Sanitized Task Packets With DeerFlow

This guide explains how to plan a task locally, send only sanitized context to DeerFlow, and integrate the result back into the real repository.

## Goal

Use DeerFlow for implementation work without exposing unnecessary repository context to a non-zero-data-retention model or service, while still preserving enough behavioral truth that the returned draft can be reintegrated reliably.

## When This Workflow Fits

Use it for:

- Pure functions
- Adapters with strict inputs and outputs
- Small UI components with mock data
- Validation helpers
- Test generation from explicit examples
- Bug fixes with a known reproduction and expected result

Avoid it for:

- Cross-cutting refactors
- Large architecture changes
- Tasks that depend on hidden runtime behavior
- Debugging that requires real logs or production traces

## Folder Structure

Create a per-task directory under `ai_safe/tasks/`.

Example:

```text
ai_safe/tasks/2026-05-08-signal-transform/
  task_context.md
  interfaces.md
  constraints.md
  examples.md
  notes.md
```

`notes.md` is optional and should contain only sanitized reviewer notes.

## Step 1: Prepare The Packet Locally

From the real repository, extract only the information DeerFlow needs:

- Function signatures
- Data structures
- Minimal stub files
- Exact behavioral requirements
- Input/output examples
- Allowed libraries and constraints
- The exact acceptance slice from the local plan, rewritten in sanitized form if needed
- Any fail-closed, warning, or classification behavior that must match local semantics
- The verification command that will be run locally after reintegration

Remove or replace:

- Proprietary algorithms
- Domain-specific internal names
- Secrets and credentials
- Internal logs and stack traces
- Production data
- Customer or partner identifiers

If naming leaks business meaning, rename symbols in the sanitized packet to neutral names such as `SignalPayload`, `Processor`, `transform_value`, or `compute_metric`.

## Step 2: Fill In The Templates

Use the templates in `ai_safe/templates/`.

Suggested order:

1. Copy `templates/interfaces.md` and paste sanitized stubs.
2. Copy `templates/examples.md` and write exact examples plus edge cases.
3. Copy `templates/constraints.md` and define allowed dependencies and non-negotiable rules.
4. Copy `templates/task_context.md` and summarize the task plus required output format.

Keep the packet short. If the packet exceeds what a careful human would need to solve the task, it is probably still too broad.

At the same time, do not under-pack behavior. A small packet is only useful if it still tells DeerFlow what must be preserved exactly. If correctness depends on subtle distinctions, include those distinctions directly rather than hoping DeerFlow reconstructs them from a stub.

## Step 3: Open DeerFlow Locally

Run DeerFlow in your trusted local environment when possible. If you are using a hosted model provider through DeerFlow, remember that uploaded packet contents still go to that provider.

Recommended practice:

- Use a fresh thread per task
- Disable unnecessary tools for the thread
- Avoid attaching any files outside the packet directory
- Delete the thread when the task is complete if your DeerFlow deployment supports cleanup
- Treat DeerFlow as a draft implementation worker, not the final authority on repo-conformant behavior

## Step 4: Upload Only The Sanitized Files

Upload these files:

- `task_context.md`
- `interfaces.md`
- `constraints.md`
- `examples.md`

Optionally upload:

- One or more sanitized stub files
- `notes.md` with sanitized reviewer hints

Do not upload:

- Real source files with proprietary internals
- Real `.env` files
- Real debug logs
- Database dumps
- Architecture documents that reveal more than the task needs

## Step 5: Send The Handoff Prompt

Paste the contents of `ai_safe/DEERFLOW_PROMPT.md` into DeerFlow, then ask it to use the uploaded files only.

A minimal handoff message:

```text
Use the uploaded task packet only. Read task_context.md, interfaces.md, constraints.md, and examples.md. Return a unified diff against the stub if possible.
```

## Step 6: Review The Result Locally

Before integrating DeerFlow output:

- Check that assumptions are acceptable
- Check that DeerFlow followed the exact semantics in the packet instead of approximating them
- Verify no hidden dependencies were introduced
- Verify the code respects your naming and interface rules
- Run local tests in the real repository
- Reapply real domain names only after review if you had obfuscated them

## Step 7: Integrate Into The Real Repository

Use the DeerFlow result as draft implementation material, not as trusted final code.

Recommended integration flow:

1. Apply the patch or copy the code into the real target file.
2. Restore real names if you used neutral names in the packet.
3. Compare the result against the real in-repo implementation, plan, or contract surfaces it was meant to mirror.
4. Run tests and linters locally.
5. Fix any integration gaps caused by stripped context.
6. Commit only after the real repository passes its own checks.

This last local step is not optional. The best workflow is:

1. local planning
2. external DeerFlow drafting
3. local repo-grounding and verification

## A Good Packet

A good packet is:

- Small
- Explicit
- Testable
- Free of secrets
- Focused on one behavior
- Precise about any semantics that must match existing repo behavior

## A Bad Packet

A bad packet:

- Includes real implementation logic
- Pastes production logs
- Depends on hidden helpers
- Asks for broad refactors
- Leaves expected behavior vague

## Example Packet Checklist

- Interfaces included
- Constraints included
- At least two examples included
- Edge cases listed
- Exact repo-mirroring semantics included when needed
- Local verification command included when useful
- Public symbol names reviewed for IP leakage
- No secrets or logs included
- Task narrow enough for one isolated implementation
