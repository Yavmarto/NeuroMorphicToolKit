# ADR 0003: Workflow Engine

## Status
Deprecated — feature removed (see Status Update below)

## Context
Neurohub orchestrates multi-step workflows that span the NMTK suite (e.g., "design in Neurosim, benchmark in Neurobench, deploy via Neurochip"). These workflows must persist across server restarts and execute steps asynchronously.

## Decision
Implement a workflow engine persisted in PostgreSQL (`WorkflowTemplateDB` for definitions, `WorkflowRunDB` for execution state) with an async background worker loop started as an `asyncio.create_task` in the FastAPI lifespan handler. The worker executes steps by calling other NMTK module APIs via `suite_client.py`. Graceful shutdown cancels the worker task.

## Consequences
- **Positive:** Database-backed persistence survives server restarts; async worker enables non-blocking workflow execution alongside API request handling.
- **Negative:** Single-worker design limits throughput; inter-module HTTP calls in workflow steps are fragile if target services are unavailable.

## Status Update (2026-07-16 audit)
This feature is fully removed. `WorkflowTemplateDB` and `WorkflowRunDB` no longer exist in
`neurohub/db/models.py`, and their backing tables (`workflow_templates`, `workflow_runs`) were
dropped by migration `c2d4e5f60002_drop_pm_workflow_tables.py` (see the 0001 status update).
There is no `asyncio.create_task` anywhere under `neurohub/app/` — confirmed via grep; the
FastAPI `lifespan` handler in `neurohub/app/main.py` only runs `alembic_command.upgrade(...)`
on startup, no background worker loop. `suite_client.py` has no callers left inside `app/` —
`grep -rln "suite_client" neurohub/app/` finds only `suite_client.py` itself, and the only
other reference in the codebase is `neurohub/tests/test_suite_client.py`; it is dead code kept
alive solely by its own test.
