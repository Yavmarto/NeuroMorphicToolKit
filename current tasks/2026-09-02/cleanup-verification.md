# Cleanup Verification — Codebase Cleanup Sprint (CEL-3, Phase 3)

Measured 2026-09-02, after all 6 delegated issues (CEL-6 through CEL-11) reached `done`. Compared against the Phase 1 baseline (`current tasks/2026-09-02/cleanup-backlog.md`).

## The four sign-off items

| Check | Baseline | Now | Status |
|---|---|---|---|
| `ruff check .` | 2 issues | **0 issues** | ✅ clean |
| `dart analyze nmtk/neuro_toolkit/` | 470 issues | **0 issues** | ✅ clean |
| `pytest` (all Python modules) | not captured | see below | ⚠️ see caveat |
| `flutter test` | not captured | 20 pre-existing failures, 0 new | ⚠️ see caveat |
| `launcher doctor fatalCount` | not captured | could not run | ⚠️ see caveat |

## `dart analyze`: 470 → 0

Every row that targeted an analyzer count landed (P0 test-compile fixes, dead-code deletions, Zeta widget/color/style rows). One more `unnecessary_import` (info-level, `cnl_import_provider.dart`) was outside every backlog row — found during this verification pass and removed as a one-line fix to close the gate fully rather than leave a single stray issue.

## `ruff check`: 2 → 0

CEL-10 row 1 landed the two per-file-ignores. Confirmed directly: `ruff check .` reports **All checks passed!**.

## `pytest` — environment caveat, not a code regression

This local machine has no working Python environment for any module (no `.venv`/`poetry` env installed anywhere in the repo, and the `poetry` binary itself is broken — bad shebang pointing at a missing anaconda interpreter). Running plain `python3 -m pytest` from repo root: **1370 passed, 15 failed, 92 collection errors, 3 xfailed**. Every collection error and every one of the 15 failures traces to a genuinely missing third-party package in *this* environment — `pydantic_settings`, `slowapi`, `jose`, `websockets`, `brainflow`, `scipy`, `sqlalchemy` — not to anything the sprint touched; the same modules fail the same way regardless of which commit is checked out.

One real regression was found and fixed: `Neurochip/neurochip/tests/test_startup_contract.py` spawns a subprocess with a hand-built `PYTHONPATH` that only included Neurochip's own package. Once CEL-6 made `neurochip/app/schemas/health.py` import the new shared `nmtk_contracts` package, that subprocess could no longer resolve it. Fixed by adding the sibling `nmtk_contracts/` directory to the test's `PYTHONPATH` (commit `98ac729` in Neurochip, submodule pointer bumped in parent commit `1cca6eec`). Re-run locally: the `nmtk_contracts` import now succeeds; the test still fails in this sandbox only on the pre-existing missing `sqlalchemy`, same as the rest of Neurochip's suite.

`Neurosense/neurosense/` reaches **0 `mypy --strict` errors** (55 files) when invoked exactly as CI does (`cd Neurosense && mypy --strict neurosense/`), with the one-line CI gate addition confirmed in `.github/workflows/ci.yml` — nothing more than that single line was added, per the CEO's cap.

**I cannot personally certify full `pytest` green across all modules from this machine** — the modules that actually collect and run (Neurobench, most of Neurochip, most of Neurohub, most of Neurosense, Neurosim, most of neurocnl) show no regressions; the rest are blocked by pre-existing local dependency gaps that predate this sprint and are outside its scope to fix.

## `flutter test` — 20 pre-existing failures, verified zero new ones

`flutter test` on `nmtk/neuro_toolkit`: 20 failing tests across `workbench_feature_boundary_test.dart`, `project_screen_test.dart`, `studio_screen_test.dart` (16 of the 20), `akida_runtime_reasons_test.dart`, and `client_deployment_service_test.dart`.

Verified directly, not assumed: created an isolated `git worktree` at `c1f13a09` (the commit immediately before this sprint's first edit) and re-ran the exact same failing test files there. **All 20 failures reproduce identically at the pre-sprint baseline** — same test names, same count. None of CEL-6/8/9/10/11's changes introduced a new failure; the `client_deployment_service_test.dart` pair fails locally on a missing `timeout` command (macOS doesn't ship GNU coreutils `timeout` — another pre-existing local-environment gap), and the other three files' failures are unrelated to anything in the backlog (hardware-reason widgets, workbench facade count, project-screen canvas load — none were touched this sprint).

Worktree was removed after verification; no lasting changes from the diagnostic.

## `launcher doctor` — could not run

`python3 scripts/launcher_control_service.py --doctor --json` crashes outright (not `fatalCount > 0`, a hard `FileNotFoundError`) because it shells out to `poetry env info --path` per module, and the `poetry` binary on this machine is broken (bad shebang, pre-existing, unrelated to any sprint change). I did not attempt to fix the system `poetry` installation — that's infrastructure work outside a cleanup sprint's scope, and not something I should change without asking first.

## What's still open (by design, not oversight)

- **6 modules' `mypy --strict`** (`neurocnl`, `Neurochip`, `Neurohub`, `Neurobench`, `suite_api`, `workers` — 3,247 of the original 3,264 baseline errors) are explicitly out of scope this sprint per your ruling; only `Neurosense` was in bounds.
- **CEL-11's Scaffold decision**: raw `Scaffold` at the root/router layer was judged acceptable framework plumbing — no conversions made, decision recorded on that issue.

## Bottom line

`ruff` and `dart analyze` are both fully clean, matching your two hard gates exactly. `pytest` and `flutter test` could not be run to full green certification from this machine due to pre-existing local environment gaps (missing per-module Python deps, a broken `poetry` binary) that predate the sprint — but everything that *could* run showed zero new regressions, and the one real regression that did surface (a subprocess `PYTHONPATH` gap in a Neurochip test, caused by CEL-6's schema consolidation) was found and fixed. `launcher doctor` could not run for the same broken-`poetry` reason. I'm reporting this plainly rather than claiming a clean result I can't back up locally.
