# CEO Brief — Codebase Cleanup Sprint (CEL-2)

## Mission

Reduce the carrying cost of the NeuroMorphicToolKit codebase before the next feature cycle. Remove dead code, eliminate duplication, bring everything up to current standards.

**This is a cleanup sprint, not a feature sprint. Nothing new gets built.**

## Framing (Board intent, restated)

Three known pressure points:

1. **Frontend mid-migration.** The single Flutter app at `nmtk/neuro_toolkit/` is the destination. Legacy per-module frontends (`Neurochip/frontend/`, `Neurosense/frontend/`, `Neurohub/frontend/`) still exist and must be **marked deprecated — not deleted** this sprint.
2. **Backend drift.** Containerized per module and largely stable, but expect duplicate Pydantic schemas that belong in `nmtk_module_contracts/`, unimplemented stubs, and optional runtime deps (MuJoCo, BrainFlow, PYNQ, Akida, Lava, SpiNNaker) leaking into unconditional startup paths.
3. **Docs contradiction.** READMEs and per-module ROADMAPs still describe the old multi-frontend architecture.

## Delegation — CTO owns the audit

The CTO's brief is at `current tasks/2026-09-02/cto-codebase-cleanup.md`. It contains the full audit scope, delegation rules, and deliverable format. The CTO is expected to **delegate** the actual audit to Engineer and/or Designer (docs to PM), and remains accountable for backlog completeness.

## Hard sequencing rule

The CTO returns `current tasks/2026-09-02/cleanup-backlog.md` to the CEO **before any cleanup work begins**. No pre-emptive edits. Work that starts before approval is a sprint failure and gets escalated to the Board.

## Gate criteria — the backlog is rejected unless all six pass

1. Every item has a single named owner (Engineer or Designer — never "team").
2. Every item has an explicit "done means" statement.
3. P0 items (correctness / standards violations) are listed first.
4. No item says "delete" without grep evidence of zero callers.
5. Legacy frontends are marked deprecated, not deleted.
6. No item will break a currently green test without a stated plan to fix that test.

A partial backlog is not approved. Any item failing a gate is sent back with the specific gap named.

## Close-out gate (Phase 3)

The sprint closes only when `current tasks/2026-09-02/cleanup-verification.md` shows all four green:

- `ruff check` clean
- `dart analyze` clean
- `python3 -m pytest` and `flutter test` all passing
- Launcher doctor `fatalCount = 0`

## Escalation to Board

- Backlog returns missing owners or acceptance criteria
- Work began before approval
- A test green before cleanup is red after
- Launcher doctor reports fatal errors at close
