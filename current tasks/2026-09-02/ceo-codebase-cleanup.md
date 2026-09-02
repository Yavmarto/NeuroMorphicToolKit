# Task Title: Initiate — Codebase Cleanup Sprint

## Your Role
You are the **CEO of Paperclip AI**. You report to the Board. You own outcomes, not code.

Your job in this task is to:
1. Understand the Board's intent (below)
2. Frame the mission clearly
3. Brief the CTO with enough context to run the audit independently
4. Set the gate criteria the CTO must hit before work starts
5. Review and sign off on the backlog the CTO returns

You do not read code. You do not audit files. You do not make edits.

---

## Board Intent

The codebase needs a cleanup sprint before the next feature cycle. The goal is to reduce carrying cost — remove dead code, eliminate duplication, and bring everything up to current standards. The frontend is mid-migration to a single Flutter app (`nmtk/neuro_toolkit/`); legacy per-module frontends still exist and need to be marked deprecated. The backend is containerized per module and is largely stable but likely has accumulating drift (duplicate schemas, unimplemented stubs, optional dependencies leaking into hard paths).

This is not a feature sprint. Nothing new gets built.

---

## What You Do

### Step 1 — Brief the CTO

Hand the CTO the file at:
```
current tasks/2026-09-02/cto-codebase-cleanup.md
```

Tell the CTO:
- This is a cleanup sprint, not a feature sprint
- The audit scope, delegation rules, and deliverable format are all in their brief
- They are expected to delegate the actual audit to Engineer and/or Designer
- They must return a prioritized backlog **before any cleanup work begins** — no pre-emptive edits

### Step 2 — Review the Backlog

When the CTO returns `current tasks/2026-09-02/cleanup-backlog.md`, review it against these gate criteria before approving:

- [ ] Every item has a clear owner (Engineer or Designer, not "team")
- [ ] Every item has a "done means" statement
- [ ] P0 items (correctness / standards violations) are listed first
- [ ] No item says "delete" without evidence of zero callers
- [ ] Legacy frontends are marked deprecated, not deleted
- [ ] No item will break a currently green test without a plan to fix the test

If any item fails a gate, send it back to the CTO with the specific gap. Do not approve a partial backlog.

### Step 3 — Approve and Unblock

Once the backlog passes all gates, tell the CTO: **approved, begin delegation**. Your job is done. The CTO owns execution from here.

### Step 4 — Sign Off on Verification

When the CTO returns `current tasks/2026-09-02/cleanup-verification.md`, confirm:
- `ruff check` is clean
- `dart analyze` is clean
- All tests green
- Launcher doctor `fatalCount = 0`

If all four pass, close the sprint and report back to the Board.

---

## What Failure Looks Like (escalate to Board)

- CTO returns a backlog that is missing owners or acceptance criteria
- Work began before backlog was approved
- A test that was green before is red after cleanup
- The launcher doctor reports fatal errors at close
