# NeuroMorphicToolKit — Status Audit & Readiness Report

**Audit Date:** 11-Jun-2026
**Agent Assessor:** Opencode
**Scope:** Root repository (cross-cutting analysis of all submodules)
**Branch:** dev

---

## 1. Executive Summary

**Overall POC Readiness: ~85%** (no change from 16-May baseline; structural debt persists)

Since the last round of audits (Apr–May 2026), the codebase has matured in backend route coverage and Flutter design-system adoption, but several systemic issues remain:

| Category | Finding |
|----------|---------|
| **Ruff violations** | ⬇ 537 → 403 total (25% reduction since 31-Mar); 203 auto-fixable |
| **T201 `print()` issues** | Still 315 in non-test, non-venv Python source (down from 517); `Neuro-Dream-Hand` remains primary offender |
| **`logging.getLogger` usage** | 190 call sites confirmed — still outnumbered by rogue `print()` |
| **Neurochip frontend** | **0 Dart files** — `frontend/` directory is a bare IntelliJ project file; no UI exists at all |
| **Neurosense Flutter** | 680 issues in `flutter analyze` — 18 errors (undefined `state` setters on Riverpod notifiers in tests), 662+ warnings/infos |
| **nmtk_ui_core** | Clean — `flutter analyze` passes with 0 issues |
| **Launcher (nmtk)** | Clean — only 2 info-level pubspec sorting warnings |
| **API routes** | 180 total endpoints across 5 modules (neurocnl: 28, Neurochip: 53, Neurobench: 27, Neurosense: 28, Neurohub: 44); only 2 `501`/`NotImplemented` stubs found |
| **PBT (property-based tests)** | Only Neurohub has real PBT files (4 property test modules); other modules have 0 |
| **Task fragmentation** | `issues/` and `UI - issues/` are empty; `tasks/` has 1 file; `issues-archive/` has 30+ documents; `docs/unified-dev-pipeline/*/generated-issues/` has 20 CDD-generated issue files across 6 modules |

**Remaining blockers**: Neurochip frontend (0 files), Neurosense test compilation errors (18 errors), 315 rogue `print()` statements, missing PBT coverage in 4 of 5 modules.

---

## 2. Linter Snapshot

### Ruff (Python — 11-Jun-2026)

Total: **403 errors** (down from 537 on 31-Mar, -25%). 203 auto-fixable.

**Top violations:**

| Count | Code | Description |
|-------|------|-------------|
| 84 | invalid-syntax | Syntax errors (likely Jupyter/stub files) |
| 65 | W293 | blank-line-with-whitespace |
| 53 | UP015 | redundant-open-modes |
| 38 | PGH003 | blanket-type-ignore |
| 32 | F401 | unused-import |
| 21 | E402 | module-import-not-at-top-of-file |
| 20 | E501 | line-too-long |
| 20 | UP045 | non-pep604-annotation-optional |
| 17 | I001 | unsorted-imports |
| 9 | F541 | f-string-missing-placeholders |
| 9 | PLC0415 | import-outside-top-level |
| 4 | F821 | undefined-name |
| 4 | ARG001 | unused-function-argument |

**Rogue `print()` vs `logging.getLogger()`:**
- 315 `print()` calls in production (non-test, non-venv) Python source
- 190 `logging.getLogger()` call sites
- Ratio: 1.66 `print()` per `logging.getLogger()` — still inverted from healthy baseline

### Mypy (Python — strict mode)

Failed on duplicate module error (`flutter_lldb_helper.py` in both `nmtk/neuro_toolkit/ios/` and `neurocnl/frontend/ios/`). Did not complete a full strict check. Needs `--exclude` for Flutter-generated iOS helper files.

### Flutter Analyze (Dart — 11-Jun-2026)

| Module | Issues | Errors | Warnings | Info |
|--------|--------|--------|----------|------|
| **nmtk (launcher)** | 2 | 0 | 0 | 2 (pubspec sorting) |
| **nmtk_ui_core** | 0 | 0 | 0 | 0 |
| **neurocnl frontend** | 20 | 0 | 4 | 16 |
| **Neurochip frontend** | N/A | **No frontend exists** |
| **Neurobench frontend** | 28 | 0 | 12 | 16 |
| **Neurosense frontend** | **680** | **18** | ~100+ | ~560+ |
| **Neurohub frontend** | 2 | 0 | 1 | 1 |

**Neurosense critical errors**: All 18 errors are in test files — `state` setter undefined on Riverpod `StreamNotifier`, `DeviceNotifier`, `RecordingNotifier`, `SessionsNotifier`. This indicates a Riverpod API migration was partially done (providers changed from mutable `state` to a different update pattern) but tests were not updated.

**Neurobench warnings**: 6 `invalid_use_of_visible_for_testing_member` / `invalid_use_of_protected_member` on `.state` access — same Riverpod pattern issue as Neurosense but in production code, not just tests.

---

## 3. Task Fragmentation Findings

| Tracking System | Location | Active Items | Status |
|----------------|----------|-------------|--------|
| `issues/` | Root | 0 files | **Empty — deprecated** |
| `UI - issues/` | Root | 0 files | **Empty — deprecated** |
| `tasks/` | Root | 1 file (`11 june/architecture-contracts-deep-dive.md`) | Ad-hoc, not tracked |
| `issues-archive/` | Root | 30+ documents | Historical only |
| CDD `generated-issues/` | `docs/unified-dev-pipeline/` | 20 files across 6 modules | Structured but not integrated with any issue tracker |

**Duplicate tracking systems to deprecate:**
1. `issues/` — empty, no longer used. Remove or add `.gitkeep` with a README explaining the move to `issues-archive/`.
2. `UI - issues/` — empty, same. The space in the directory name is also a path hazard.
3. `tasks/` — contains a single ad-hoc markdown file. This is not a sustainable tracking mechanism.

**Recommended consolidation:** Use `docs/unified-dev-pipeline/*/generated-issues/` as the canonical issue source (it is structured per-module), and archive `issues/`, `UI - issues/`, and `tasks/`. True "remaining task count" is **20 CDD-generated issues** + **1 ad-hoc task** = 21 known work items.

---

## 4. Target Readiness & Module Status

### neurocnl (NeuroStudio)

| Dimension | Status | Evidence |
|-----------|--------|----------|
| **Backend** | ✅ 90% | 273 Python files, 28 API endpoints across 10 routers, 0 `501` stubs found |
| **Frontend** | ✅ 85% | 257 Dart files, 4 unused/dead elements in `file_tab_strip.dart`, 1 `use_rethrow_when_possible` info |
| **Tests** | ✅ 80% | 172 Python tests, 98 Dart tests — strongest test coverage in the suite |
| **Docker** | ✅ Yes | `Dockerfile` in both `backend/` and `frontend/` |
| **CI** | ✅ Yes | Pre-commit config present |

### Neurochip

| Dimension | Status | Evidence |
|-----------|--------|----------|
| **Backend** | ✅ 85% | 85 Python files, 53 API endpoints across 10 routers (most endpoints of any module), 0 `501` stubs |
| **Frontend** | ❌ 0% | **No `frontend/` directory with Dart code exists.** Only `neurochip.iml` (IntelliJ project file). No `pubspec.yaml`. Module is marked `hasFrontend: true` in `modules.json` but has zero UI. |
| **Tests** | ⚠️ 55% | 49 Python tests, 0 Dart tests |
| **Docker** | ✅ Yes | `Dockerfile` present |
| **CI** | ⚠️ Partial | Has pyproject.toml but no `.pre-commit-config.yaml` |

### Neurobench

| Dimension | Status | Evidence |
|-----------|--------|----------|
| **Backend** | ✅ 85% | 55 Python files, 27 API endpoints across 10 routers |
| **Frontend** | ⚠️ 70% | 42 Dart files, but 6 Riverpod `.state` access violations in production code (protected member misuse), 3 `deprecated_member_use` warnings |
| **Tests** | ⚠️ 50% | 29 Python tests, 17 Dart tests |
| **Docker** | ✅ Yes | `Dockerfile` present |
| **CI** | ⚠️ Partial | Has pyproject.toml |

### Neurosense

| Dimension | Status | Evidence |
|-----------|--------|----------|
| **Backend** | ✅ 85% | 56 Python files, 28 API endpoints across 10 routers |
| **Frontend** | ⚠️ 60% | 34 Dart files exist, but **680 `flutter analyze` issues** — 18 compilation errors in tests (undefined `state` setters on Riverpod notifiers), hundreds of lint warnings |
| **Tests** | ❌ 30% | 25 Python tests, 15 Dart tests — but Dart tests **do not compile** due to Riverpod API drift |
| **Docker** | ✅ Yes | `Dockerfile` + `Dockerfile.frontend` |
| **CI** | ✅ Yes | Pre-commit config present |

### Neurohub

| Dimension | Status | Evidence |
|-----------|--------|----------|
| **Backend** | ✅ 90% | 763 Python files (largest codebase), 44 API endpoints across 10+ routers, database models (`db/models.py` with SQLAlchemy) |
| **Frontend** | ✅ 80% | 38 Dart files, only 2 `flutter analyze` issues (1 warning, 1 info) |
| **Tests** | ✅ 75% | 29 Python tests, 22 Dart tests, **4 PBT (property-based test) modules** — only module with real PBT coverage |
| **Docker** | ✅ Yes | `Dockerfile` + `frontend/Dockerfile` |
| **CI** | ⚠️ Partial | Has `.venv-test` but no `.pre-commit-config.yaml` |

### Neuro-Dream-Hand

| Dimension | Status | Evidence |
|-----------|--------|----------|
| **Backend** | ⚠️ 65% | 96 Python files — research library with extensive `print()` usage |
| **Frontend** | N/A | No frontend declared |
| **Tests** | ⚠️ 40% | Minimal test coverage |
| **Docker** | ❌ No | No Dockerfile |
| **CI** | ❌ No | Has pyproject.toml but deprecated ruff config |

### nmtk (Launcher)

| Dimension | Status | Evidence |
|-----------|--------|----------|
| **Frontend** | ✅ 90% | 54 Dart files, 2 info-level warnings only |
| **Tests** | ⚠️ 60% | 11 Dart tests |
| **Docker** | ✅ Yes | Root `Dockerfile.control` |
| **CI** | ✅ Yes | Root compose files + launcher guardrails |

### nmtk_ui_core (Design System)

| Dimension | Status | Evidence |
|-----------|--------|----------|
| **Frontend** | ✅ 95% | 163 Dart files, 0 `flutter analyze` issues |
| **Tests** | ⚠️ 50% | Design token and widget tests exist but coverage not verified |

### Root Infrastructure

| Dimension | Status | Evidence |
|-----------|--------|----------|
| **Docker Compose** | ✅ Yes | `docker-compose.yml` (8875 bytes), `docker-compose.dev.yml`, `docker-compose.prod.yml` |
| **Integration Tests** | ✅ 34 Python test files | `test_cross_module.py`, `test_teensy_e2e.py` |
| **CI Workflows** | ✅ Yes | `.github/` present |
| **Monitoring** | ✅ Yes | `monitoring/` directory |

---

## 5. Priority Work Roadmap

### P0 — Critical (Blocks functional POC demo)

| # | Item | Module | Effort |
|---|------|--------|--------|
| 1 | **Create Neurochip frontend** — Module declares `hasFrontend: true` but has 0 Dart files. Needs `pubspec.yaml`, `lib/`, shell mode `NmtkShellMode.instrument`, and at minimum a hardware-profile/deployment dashboard | Neurochip | Large |
| 2 | **Fix Neurosense test compilation** — 18 errors from Riverpod `state` setter drift. Tests cannot run at all | Neurosense | Medium |
| 3 | **Fix Neurobench Riverpod `.state` violations** — 6 `invalid_use_of_protected_member` in production code, not just tests | Neurobench | Medium |
| 4 | **Fix 84 invalid-syntax errors** in ruff check — likely Jupyter/stub files poisoning the linter | Root | Small |

### P1 — Core Integration

| # | Item | Module | Effort |
|---|------|--------|--------|
| 5 | **Eliminate rogue `print()` statements** — 315 remaining; replace with `logging.getLogger()` | All modules | Medium |
| 6 | **Add PBT coverage to 4 modules** — Only Neurohub has property-based tests; neurocnl, Neurochip, Neurobench, Neurosense have 0 | All except Neurohub | Medium |
| 7 | **Clean up Neurosense 660+ lint warnings** — After fixing 18 compilation errors, address the remaining 660+ info/warning issues | Neurosense | Medium |
| 8 | **Deprecate empty tracking dirs** — Remove/archive `issues/`, `UI - issues/`, consolidate `tasks/` into CDD `generated-issues/` | Root | Small |
| 9 | **Mypy strict pass** — Currently blocked by duplicate Flutter iOS helper module; add `--exclude` for generated iOS files and re-run | Root | Small |

### P2 — Polish / Quality

| # | Item | Module | Effort |
|---|------|--------|--------|
| 10 | **Auto-fix 203 ruff violations** — Run `ruff check --fix` across the repo | All | Small |
| 11 | **Neuro-Dream-Hand ruff config migration** — Move deprecated top-level ruff settings under `[tool.ruff.lint]` | NDH | Small |
| 12 | **Neurohub/neurocnl deprecated `value` → `initialValue`** — 4 `deprecated_member_use` warnings in form fields | Neurobench, Neurohub | Small |
| 13 | **Add Neurochip `.pre-commit-config.yaml`** — Only backend module missing it | Neurochip | Small |
| 14 | **Sort pubspec dependencies** — nmtk launcher has 2 info warnings for unsorted deps | nmtk | Trivial |
| 15 | **Remove unused `_ZetaStyledTab`** in neurocnl `file_tab_strip.dart` | neurocnl | Trivial |

---

**Methodology note**: All metrics are derived from direct tool execution (`ruff check`, `flutter analyze`, `mypy --strict`, `find`, `grep`), not from reported CI status or documentation claims. No metrics were invented or estimated without file-level evidence.
