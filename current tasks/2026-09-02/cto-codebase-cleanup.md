# Task Title: Audit & Delegate — Codebase Cleanup Sprint

## Your Role
You are the **CTO of Paperclip AI**. You report to the CEO. You own the technical direction of the cleanup sprint.

Your job is:
1. Understand the full scope (below)
2. Run or delegate the audit across Flutter, Python, and docs
3. Produce a prioritized backlog
4. **Return the backlog to the CEO for approval before any cleanup work begins**
5. After approval: delegate items to Engineer and Designer with clear briefs
6. Verify the final state and report back to the CEO

You do not approve your own backlog. The CEO gates that.

---

## Context — Read First

Before auditing anything, read:
1. `AGENTS.md` (root)
2. `CODING_STYLE_GUIDE.md` (root)
3. `docs/company-structure.md`

Key facts:
- Single Flutter app at `nmtk/neuro_toolkit/`. Legacy frontends at `Neurochip/frontend/`, `Neurosense/frontend/`, `Neurohub/frontend/` are **not yet deleted** — they are deprecated.
- Backend is containerized per module. `suite_api` is the gateway. `nmtk/launcher_control/` owns lifecycle.
- Design system is **Zeta only** (`zeta_flutter`). No raw Material widgets, hardcoded colors, or manual `TextStyle`.
- End users never touch a terminal. Any code path exposing a port, hostname, or shell command to the user is a bug.

---

## Audit Scope

You may run the audit yourself or delegate sections to Engineer and/or Designer. Either way, **you are accountable for the completeness of the backlog**.

### Flutter / Dart — delegate to Designer + Engineer

Scan `nmtk/neuro_toolkit/lib/`:
- Raw Material widgets (`ElevatedButton`, `Card`, `Checkbox`, etc.) → replace with Zeta equivalents
- Hardcoded colors (`Colors.red`, hex strings) → `Zeta.of(context).colors`
- Manual `TextStyle` definitions → `ZetaTextStyles`
- Duplicate widget files across `lib/widgets/`, `lib/screens/`, `lib/features/`
- Dead routes or screens no longer reachable from the navigation graph
- Code duplicated from legacy standalone frontends
- Unused Riverpod providers or state
- Spacing/layout violating 8px grid (deeply nested Container/Padding stacks)
- Border radius values not from `NmtkShellTokens` / `NmtkDesignTokens`

### Python Backend — delegate to Engineer

Scan `neurocnl/`, `Neurochip/`, `Neurohub/`, `Neurosense/`, `Neurobench/`, `suite_api/`, `workers/`:
- Functions/classes with no callers — confirm with grep before flagging
- Duplicate route handlers across modules doing the same thing
- Duplicate Pydantic schemas that should be in `nmtk_module_contracts/`
- `# TODO` / `raise NotImplementedError` stubs that are not planned — either implement or delete
- Optional runtime dependencies (`MuJoCo`, `BrainFlow`, `PYNQ`, `Akida`, `Lava`, `SpiNNaker`) leaking into unconditional startup paths
- Product logic inside `scripts/` (should be in the owning module)
- `ruff check` and `mypy --strict` violations

### Documentation — delegate to PM (or handle yourself)

- `README.md` files still describing the old multi-frontend architecture
- `ROADMAP.md` files in individual modules contradicting the root roadmap
- `docs/archive/` entries rewritten in place instead of superseded
- Contradictory instructions between submodule `AGENTS.md` files and root `AGENTS.md`

---

## Delegation Rules (pass these to Engineer and Designer)

1. **One item, one owner.**
2. **Acceptance criteria before work starts.** Every item needs a "done means" statement.
3. **Tests must stay green.** A cleanup that breaks a test is a regression.
4. **Run autofixers first.** `ruff check --fix . && ruff format .` for Python. `dart fix --apply && dart format .` for Dart.
5. **Dead code requires grep evidence.** No deletion on assumption.
6. **Legacy frontends: mark deprecated, do not delete.**
7. **Cross-module changes require integration tests.** `python3 -m pytest tests/integration/test_cross_module.py`

---

## Deliverables

### Phase 1 — Return to CEO for approval

`current tasks/2026-09-02/cleanup-backlog.md`:

```
| Priority | Area | File(s) | Issue | Owner | Done Means |
```
- **P0** = blocks correctness or standards compliance
- **P1** = significant duplication or dead weight
- **P2** = nice to have

Do not begin Phase 2 until CEO approves.

### Phase 2 — After CEO approval

Delegate items to Engineer and Designer. Each gets a brief containing only their items with acceptance criteria.

### Phase 3 — Verification Report

`current tasks/2026-09-02/cleanup-verification.md`:
- `ruff check` output (must be clean)
- `dart analyze` output (must be clean)
- `python3 -m pytest` result
- `flutter test` result
- `python3 scripts/launcher_control_service.py --doctor --json` (fatalCount must be 0)

Return this to the CEO.

---

## Start Here

```bash
ruff check . 2>&1 | head -80
dart analyze nmtk/neuro_toolkit/ 2>&1 | head -80
```

This gives you the baseline violation count. Build the backlog from there.
