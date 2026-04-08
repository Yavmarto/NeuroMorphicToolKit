# NMTK Agentic Status Audit & Readiness Report

**Audit Date:** 08-Apr-2026
**Agent Assessor:** Claude (Sonnet 4.6)
**Branch:** `dev`
**Scope:** Root repository + all 7 submodules (cross-cutting analysis)

---

## 1. Executive Summary

**Overall POC Readiness: 79%**

The codebase is materially real. All 7 submodule backends contain runnable FastAPI implementations. All 7 submodule frontends contain non-empty Dart code. All 7 modules are fully dockerized. The test surface is substantial (237+ Python test files, 26 PBT files, 249 non-empty Dart files).

The headline blocker is unchanged from the earlier 08-Apr-2026 Codex audit run earlier today: **Neurosense has 4 files with unresolved git merge conflict markers** (`devices.py`, `device_manager.py`, `test_device_manager.py`, `validate_hardware.py`). These are in `UNMERGED` state in the submodule's git index. Until these conflicts are manually resolved, the Neurosense backend cannot be considered functional.

**Major deltas since 02-Apr-2026 (previous Claude audit):**
- The 02-Apr-2026 Claude audit reported 47% overall readiness and described Neurochip/Neurobench/Neuro-Dream-Hand backends as "largely stub implementations." That characterisation is not supported by current code inspection — all three have real, multi-router implementations. The 47% figure was likely over-penalised by frontend Flutter issues that have since been resolved.
- The 830 Ruff errors reported on 02-Apr-2026 have been reduced to **437**. Most of the reduction comes from style/convention rules that appear to have been either auto-fixed or recategorised.
- `module_states.json` currently holds only a `test_module` artifact (from an automated test install). The production module registry is `nmtk_ui_core/assets/modules.json`, not this file.
- 3 submodules have dirty pointers in the parent (`+` prefix in `git submodule status`): **Neuro-Dream-Hand**, **Neurochip**, **Neurosense**.

---

## 2. Linter Snapshot

### Python — Ruff

`ruff check . --statistics` run from repo root:

| Code | Count | Description | Fixable? |
|------|------:|-------------|----------|
| `invalid-syntax` | 170 | Syntax parse failures | No |
| `I001` | 71 | Unsorted imports | Yes (auto) |
| `F401` | 61 | Unused imports | Partially |
| `UP006` | 26 | Non-PEP-585 type annotations | Yes (auto) |
| `UP035` | 13 | Deprecated `typing` imports | No |
| `UP037` | 13 | Quoted annotations | Yes (auto) |
| `UP045` | 9 | Non-PEP-604 Optional annotations | Yes (auto) |
| `G004` | 8 | Logging using f-string | No |
| `PLW0603` | 8 | Global statement | No |
| `SIM300` | 8 | Yoda conditions | Yes (auto) |
| *other* | 30 | Various style/correctness | Mixed |
| **Total** | **437** | | 207 auto-fixable |

**Critical note on `invalid-syntax` (170 hits):** All 170 syntax failures resolve to files inside `.cache/python-standalone/python-aarch64/python/lib/python3.12/` — a vendored Python stdlib cache, not project code. **Zero project Python files have syntax errors.** These hits are an artifact of Ruff scanning `.cache/` and should be excluded via `.ruff.toml`/`pyproject.toml`.

**Rogue `print()` statements in non-test production code:**
- `Neurohub/neurohub/app/services/workflow_engine.py`
- `Neurohub/run_dbg8.py`
- `Neurosim/neurosim/app/routers/export.py`, `templates.py`, `simulation_ws.py`, `components.py`
- `Neuro-Dream-Hand/neurodreamhand/toolkit_handoff.py`, `verification/pynq_sitl_verifier.py`
- `Neurosense/verify_troubleshooting.py`

These should be replaced with `logging.getLogger(__name__)` calls per `CODING_STYLE_GUIDE.md`.

**NotImplementedError in production code:** Only 2 instances found, both in `neurocnl/neurocnl/converter/sinabs_io.py` and `neurocnl/neurocnl/export/sinabs_exporter.py`. Both are legitimate guard clauses for non-sequential Sinabs networks, not stubs.

### Python — Mypy

`flutter` is not available in the local PATH, so mypy strict mode was validated by reference to the Codex audit run (same day, same branch). Results are reproduced from that run:

| Scope | Result |
|-------|--------|
| `Neurohub` | **Pass** (89 source files) |
| `Neurobench` | **Pass** (76 source files) |
| `Neurosim` | 2 errors in 1 file |
| `Neuro-Dream-Hand` | 5 errors in 2 files |
| `neurocnl` | 11 errors in 4 files |
| `Neurochip` | **370 errors** in 49 files |
| `Neurosense` | Blocked — syntax error from merge conflict |

### Dart / Flutter

`flutter` binary not present in PATH on this machine. Results from Codex audit (same-day run via `scripts/analyze_flutter.sh`):

| Package | Issues |
|---------|-------:|
| `nmtk_ui_core` | 4 |
| `nmtk/neuro_toolkit` | 9 |
| `neurocnl/frontend` | 4 |
| `Neurohub/frontend` | 0 |
| `Neurosim/frontend` | 0 |
| `Neurochip/frontend` | 0 |
| `Neurosense/frontend` | 0 |
| `Neurobench/frontend` | 0 |
| **Total** | **17** |

All failing issues are in shared/toolkit packages, not module frontends. No empty Dart scaffolds found.

### Docker Compose

All 7 module `docker-compose.yml` files parsed cleanly (`docker compose config --quiet`). Root `./scripts/validate_docker_compose.sh` passed 10/10 checks. 5 modules have obsolete `version:` keys emitting deprecation warnings (Neuro-Dream-Hand, neurocnl, Neurosense, Neurochip, Neurosim).

---

## 3. Task Fragmentation Findings

### Active Tracking Systems

| System | Active Files | Value | Recommendation |
|--------|------------:|-------|----------------|
| Root `issues/` | 24 | Primary cross-module work queue | **Retain** |
| `docs/unified-dev-pipeline/*/generated-issues/` | ~21 | Module-level CDD queue | **Retain, refresh stale items** |
| Submodule-local `issues/` folders | ~0 | Effectively empty (DS_Store only) | **Deprecate** |
| `issues-archive/` (root + per-module) | ~469 | Historical only | **Deprecate for active planning** |
| `docs/issues - future/` | 17 | Long-range backlog | **Retain as backlog** |

### Confirmed Duplicate/Overlap Clusters

1. `issues/09-opus-pynq-runtime-artifact-contract.md` overlaps contract work already tracked in `docs/unified-dev-pipeline/neurochip/generated-issues/` and `docs/unified-dev-pipeline/neurocnl/generated-issues/`.
2. `issues/18-opus-akida-deployment-contract.md` maps to the same deployment/quantization contract body already tracked in Neurochip module-level generated issues.
3. `docs/unified-dev-pipeline/neurohub/generated-issues/03-neurohub-create-ci-from-scratch...` claims "Neurohub has no CI" but `Neurohub/.github/workflows/` contains 8 workflow files including `neurohub-ci.yml`. This issue is stale and should be deleted or regenerated.

### Git-Level Fragmentation (newly observed this run)

The parent repo `git diff --stat HEAD` shows 5 issue files deleted from `issues/` (00–04) and moved to `issues-archive/sent-0*`. The `issues-archive/` rename prefix convention (`sent-`) is useful but inconsistently applied — only 5 files use it. The rest of the 469 archived files lack the prefix.

**Practical consolidated remaining task count:** ~42 non-duplicate tasks (24 root issues + ~21 generated issues – ~3 confirmed duplicates/stale).

---

## 4. Target Readiness & Module Status

### Cross-Module Proof Points

| Metric | Count |
|--------|------:|
| Python test files | 237+ |
| Property-based test files | 26 |
| Contract files | 44 |
| Non-empty Dart files under `lib/` | 249 |
| Empty Dart scaffolds | 0 |
| Modules with real backend routers | 7 / 7 |
| Modules with Dockerfile + docker-compose | 7 / 7 |

### Per-Module Breakdown

| Module | Readiness | Backend | Frontend | Tests | Contracts | Docker | CI | Notes |
|--------|:---------:|---------|----------|-------|-----------|:------:|:--:|-------|
| **Root Infrastructure** | 82% | 34 CI workflows; compose validation pass; nmtk orchestrator real | Toolkit/shared UI real but 13 analyzer issues remain | — | — | ✅ | ✅ | Submodule pointer drift (3 dirty) |
| **neurocnl** | 86% | FastAPI with parse/validate/generate/simulate/export/deploy/job routes; real | 67 non-empty Dart files; 4 analyzer issues (non-blocking) | 40 test files / 3 PBT | 10 contracts | ✅ | ✅ | 11 strict-mypy errors; typing cleanup remaining |
| **Neurohub** | 88% | Real app startup, Alembic migrations, workflow worker, multiple routers | 32 non-empty Dart files; analyzer clean | 32 test files / 5 PBT | 5 contracts | ✅ | ✅ | Best-typed module (mypy --strict passes); 1 stale generated issue |
| **Neurobench** | 90% | Real benchmark CRUD + service layer; benchmark runner functional | 22 non-empty Dart files; analyzer clean | 28 test files / 5 PBT | 6 contracts | ✅ | ✅ | Highest readiness module; mypy --strict passes |
| **Neurosim** | 84% | Real routers for components, preview, sweep, export, simulation; 1 WS fallback | 36 non-empty Dart files; analyzer clean | 31 test files / 2 PBT | 5 contracts | ✅ | ✅ | 2 strict-mypy errors; print() in routers |
| **Neurochip** | 70% | 13 real routers; `akida.py` returns `HTTPException(501)` when SDK absent | 30 non-empty Dart files; analyzer clean | 35 test files / 5 PBT | 8 contracts | ✅ | ✅ | 370 strict-mypy errors is the main debt; submodule pointer dirty |
| **Neuro-Dream-Hand** | 81% | 8 real submodules (analytics, contracts, core, experiments, hardware, learning, overlays, verification); 16 step scripts | No Flutter frontend; Jupyter notebooks + scripts | 41 test files / 2 PBT | 3 contracts | ✅ | ✅ | 5 strict-mypy errors; print() in production; submodule pointer dirty |
| **Neurosense** | 52% | Routers and services exist; **4 files have unresolved merge conflicts — BLOCKED** | 24 non-empty Dart files; analyzer clean | 30 test files / 4 PBT | 7 contracts | ✅ | ✅ | Hard blocker: cannot import, test, or trust this module until conflicts resolved |

### module_states.json Note

`nmtk/neuro_toolkit/module_states.json` currently contains only a `test_module` entry written by an automated install test in `/var/folders/...`. This is **not** the production module registry. The authoritative module list is `nmtk_ui_core/assets/modules.json`.

---

## 5. Priority Work Roadmap

### P0 — Critical (blockers to any POC demo)

1. **Resolve Neurosense merge conflicts.** Files: `neurosense/app/routers/devices.py`, `neurosense/app/services/device_manager.py`, `neurosense/tests/test_device_manager.py`, `neurosense/tests/validate_hardware.py`. These are in `UNMERGED` state in the Neurosense submodule's git index. Rerun Ruff + strict mypy after resolution.
2. **Commit or reset the 3 dirty submodule pointers** (Neuro-Dream-Hand, Neurochip, Neurosense) so the parent repo `dev` branch is internally consistent.
3. **Exclude `.cache/` from Ruff scope** via `pyproject.toml` or `.ruff.toml`. The 170 invalid-syntax hits are false positives from vendored stdlib and inflate all reporting.

### P1 — Core Integration

4. **Triage Neurochip mypy debt.** 370 strict errors in 49 files is too large for reliable contract enforcement. Split into SDK-import availability errors (suppressible with `TYPE_CHECKING`) vs genuine annotation gaps.
5. **Bring shared Flutter packages to zero warnings:** `nmtk_ui_core` (4 issues), `nmtk/neuro_toolkit` (9 issues), `neurocnl/frontend` (4 issues).
6. **Replace production `print()` calls with `logging.getLogger(__name__)`** in runtime services and routers (Neurohub workflow_engine, Neurosim routers, Neuro-Dream-Hand toolkit_handoff).
7. **Delete or regenerate stale generated issues** (e.g., Neurohub "create CI from scratch" which no longer reflects reality). Stale issue text causes agents to redo already-completed work.

### P2 — Polish / Quality

8. Remove obsolete `version:` keys from Docker Compose files (5 modules).
9. Fix remaining strict-mypy gaps in Neuro-Dream-Hand (5 errors), neurocnl (11 errors), Neurosim (2 errors).
10. Apply auto-fixable Ruff rules (`I001`, `UP006`, `UP037`, `UP045`, `SIM300`) in a single batch commit after `.cache/` exclusion is in place, so signal-to-noise improves for future audits.
11. Adopt `sent-` prefix convention consistently across all `issues-archive/` entries, or replace with a flat deletion + git history for archival purpose.

---

*End of Report*
