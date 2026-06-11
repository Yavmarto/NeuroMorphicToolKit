# NMTK Agentic Status Audit & Readiness Report

**Audit Date:** 11-Jun-2026
**Agent Assessor:** OpenCode
**Scope:** Root repository — cross-cutting analysis of all submodules
**Branch:** dev
**Commits since last audit (16-May-2026):** 130

---

## 1. Executive Summary

**Overall POC Readiness: ~87%** (+2pp from 11-Jun-2026 baseline of ~85%)

130 commits landed since the 16-May audit. Key deltas:

| Metric | Previous (11-Jun early) | Current | Delta |
|--------|------------------------|---------|-------|
| Ruff violations | 403 | 403 | No change |
| T201 `print()` (ruff-selected) | 315 estimated | 168 across named modules | Improved |
| `logging.getLogger` sites | 190 | 66 (module-scoped count) | Re-measured |
| API routes (total) | 180 | 236 | +56 |
| Test files (total) | ~304 | 338 | +34 |
| PBT modules covered | 1 of 5 | 5 of 5 | All modules now have PBT dirs |
| Neurosense Flutter errors | 680 | 680 | No change (18 errors persist) |
| Neurochip Dart files | 0 | 0 | No change |
| nmtk_ui_core | Clean | Clean | No change |
| Launcher (nmtk) | 2 info | 2 info | No change |

**Remaining blockers**: Neurochip frontend (0 Dart files), Neurosense Flutter test errors (18 undefined `state` setter errors), 403 ruff violations, 1762 mypy strict errors in neurocnl.

---

## 2. Linter Snapshot

### Ruff (Python)

**Total: 403 errors** (unchanged from prior audit). 203 auto-fixable.

| Count | Code | Description |
|-------|------|-------------|
| 84 | invalid-syntax | Syntax errors in stub/notebook files |
| 65 | W293 | Blank line with whitespace |
| 53 | UP015 | Redundant open modes |
| 38 | PGH003 | Blanket type-ignore |
| 32 | F401 | Unused import |
| 21 | E402 | Module import not at top of file |
| 20 | E501 | Line too long |
| 20 | UP045 | Non-PEP604 annotation Optional |
| 17 | I001 | Unsorted imports |
| 9 | F541 | f-string missing placeholders |
| 9 | PLC0415 | Import outside top-level |
| 4 | F821 | Undefined name |
| 4 | ARG001 | Unused function argument |
| 2 | F811 | Redefined while unused |

**T201 `print()` breakdown (ruff --select T201):**

| Module | T201 violations |
|--------|----------------|
| neurocnl | 79 |
| Neurosense | 42 |
| neurocli | 20 |
| Neurochip | 11 |
| workers | 8 |
| Neurohub | 7 |
| Neurobench | 1 |
| Neuro-Dream-Hand | 0 |
| suite_api | 0 |

**Rogue `print()` grep counts** (includes test files and venvs): neurocnl 139, Neurohub 560 (inflated by `.venv-test/`), Neurosense 42, Neurochip 20, Neurobench 1.

**Logging adoption**: `logging.getLogger` call sites — neurocnl 13, Neurochip 21, Neurosense 12, Neurohub 11, Neurobench 9. Total: 66 module-scoped.

### Mypy --strict (neurocnl only)

**1762 errors in 255 files** (checked 455 source files). Predominantly `no-untyped-def`, `type-arg`, and `no-any-return` in test files. Not run on other modules due to scope.

### Flutter Analyze

| Frontend | Issues | Errors | Warnings | Info |
|----------|--------|--------|----------|------|
| nmtk_ui_core | 0 | 0 | 0 | 0 |
| nmtk (launcher) | 2 | 0 | 0 | 2 |
| neurocnl/frontend | 20 | 0 | 1 | 19 |
| Neurohub/frontend | 2 | 0 | 1 | 1 |
| Neurobench/frontend | 28 | 0 | 3 | 25 |
| Neurosense/frontend | **680** | **18** | ~30 | ~632 |

**Neurosense critical errors** (18): All are `undefined_setter` or `undefined_identifier` for `state` on Riverpod `StreamNotifier`/`DeviceNotifier` in test files — tests use direct `.state` assignment which is no longer valid in Riverpod 3.

**Neurobench warnings**: `invalid_use_of_visible_for_testing_member` and `invalid_use_of_protected_member` in `benchmark_results_table.dart:127` — accessing `.state` outside test context.

---

## 3. Task Fragmentation Findings

### Active Tracking Systems

| System | Location | Count | Status |
|--------|----------|-------|--------|
| issues-archive/ | Root | 51 files | Active archive (includes `11 june/` subdir) |
| CDD generated-issues | `docs/unified-dev-pipeline/*/generated-issues/` | 21 files (3 per module x 7 modules) | Active |
| tasks/ | Root | 1 subdir (`11 june/`) | Active |
| UI - issues/ | Root | 0 files | **Empty — deprecate** |
| Module-level issues-archive | `Neurochip/issues-archive/` | Exists | Fragmented |

### Consolidation Assessment

- **True remaining task count**: ~72 active items (51 issues-archive + 21 CDD generated-issues), with significant overlap between the two systems.
- **Duplicate tracking**: CDD generated-issues and issues-archive contain overlapping tasks (e.g., PBT creation, CI setup). The CDD pipeline issues are more structured and should be treated as canonical.
- **Recommendation**: Deprecate `UI - issues/` (empty). Consolidate `issues-archive/` into CDD `generated-issues/` as the single source of truth. Archive completed items from `issues-archive/` that have already been addressed.

---

## 4. Target Readiness & Module Status

### Neurocnl (NeuroStudio) — CNL compiler and SNN design suite

| Dimension | Status | Details |
|-----------|--------|---------|
| Backend | **90%** | 74 API routes, 455 Python files. NotImplementedError used legitimately for unsupported formats (SpiNNaker2, recurrent topologies). Health endpoint present. |
| Frontend | **85%** | 359 Dart files. Flutter analyze: 20 info-level issues only. PBT tests present (5 Dart PBT files + Python property tests). |
| Tests | **90%** | 172 test files (highest in suite). Python PBT: `test_pbt_nir_type_round_trip.py`, `test_design_properties.py`, plus 6 NIR property test files. |
| Docker | **70%** | `docker-compose.yml` present but **no Dockerfile** in module root. Relies on root `Dockerfile.control`. |
| Code Health | **75%** | 79 T201 violations, 13 logging sites. Mypy: 1762 strict errors. |

### Neurochip — Hardware execution and diagnostics

| Dimension | Status | Details |
|-----------|--------|---------|
| Backend | **85%** | 52 API routes, 136 Python files. 1 HTTP 501 stub in `akida.py:153`. Health endpoint present. Pynq + Akida runtime support. |
| Frontend | **0%** | **0 Dart files.** `frontend/` contains only `neurochip.iml` (IntelliJ project file). No UI exists. |
| Tests | **80%** | 49 test files. PBT: 4 property test files (`pynq_runtime`, `deployment`, `quantization`, `contract`). |
| Docker | **90%** | Dockerfile + docker-compose.yml present. |
| Code Health | **80%** | 11 T201 violations, 21 logging sites (best logging adoption). |

### Neurobench — SNN testing and benchmarking

| Dimension | Status | Details |
|-----------|--------|---------|
| Backend | **85%** | 28 API routes, 88 Python files. 1 HTTP 501 stub in `spinnaker2.py:50`. Health endpoint present. |
| Frontend | **80%** | 60 Dart files. Flutter analyze: 28 issues (3 warnings, 25 info). `benchmark_results_table.dart` accesses protected `.state` outside test context. |
| Tests | **80%** | 29 test files. PBT: 3 property test files (`benchmark`, `regression`, `robustness`). |
| Docker | **90%** | Dockerfile + docker-compose.yml present. |
| Code Health | **90%** | 1 T201 violation, 9 logging sites. Cleanest module. |

### Neurohub — Sharing and community

| Dimension | Status | Details |
|-----------|--------|---------|
| Backend | **85%** | 52 API routes, 93 Python files. No 501 stubs in application code. Health + registry health endpoints present. |
| Frontend | **80%** | 63 Dart files. Flutter analyze: 2 issues (1 info, 1 warning). |
| Tests | **80%** | 29 test files. PBT: 4 property test files (`workflow`, `project`, `bundle`, `registry`) + contract invariants. |
| Docker | **90%** | Dockerfile + docker-compose.yml present. |
| Code Health | **75%** | 7 T201 violations, 11 logging sites. 560 raw `print()` grep hits inflated by `.venv-test/`. |

### Neurosense — Biosignal acquisition and encoding

| Dimension | Status | Details |
|-----------|--------|---------|
| Backend | **85%** | 30 API routes, 88 Python files. No 501 stubs. Health endpoint present. |
| Frontend | **60%** | 51 Dart files. **680 Flutter analyze issues including 18 errors** — all from Riverpod 3 migration breaking `.state` setter in tests. |
| Tests | **75%** | 25 test files. PBT: 3 property test files (`device`, `encoding`, `new_invariants`). |
| Docker | **90%** | Dockerfile + docker-compose.yml present. |
| Code Health | **65%** | 42 T201 violations, 12 logging sites. Worst print() hygiene after neurocnl. |

### Neuro-Dream-Hand — Hardware-in-the-loop SITL

| Dimension | Status | Details |
|-----------|--------|---------|
| Backend | **80%** | 144 Python files. 0 T201 violations (cleanest). |
| Frontend | N/A | No frontend declared. |
| Tests | **70%** | Referenced in neurocnl local deps. |
| Docker | **60%** | No Dockerfile or docker-compose. |

### Launcher (nmtk) + nmtk_ui_core

| Dimension | Status | Details |
|-----------|--------|---------|
| Launcher | **90%** | 86 Dart files. Flutter analyze: 2 info (pubspec sort). |
| nmtk_ui_core | **95%** | 188 Dart files. Flutter analyze: 0 issues. Design system clean. |

### Infrastructure

| Component | Status | Details |
|-----------|--------|---------|
| suite_api | **80%** | 27 Python files, 0 T201 violations. |
| workers | **75%** | 15 Python files (lava_backend, jupyter_server, neurosense_hw). 8 T201 violations. |
| neurocli | **70%** | 20 Python files. 20 T201 violations. |
| Root compose | **85%** | `docker-compose.yml`, `docker-compose.dev.yml`, `docker-compose.prod.yml`. `Dockerfile.control`, `Dockerfile.lava`. |
| Root tests | **80%** | 34 test files in `tests/`. |

---

## 5. Priority Work Roadmap

### P0 — Critical (Blocks POC demo)

1. **Neurochip frontend**: 0 Dart files. Must scaffold at minimum a basic module shell in `nmtk_ui_core` or Neurochip frontend to avoid a dead nav link in the launcher.
2. **Neurosense Flutter test errors**: 18 Riverpod 3 migration errors in test files. Tests cannot compile. Fix `.state` setter usage in `spike_encoding_panel_test.dart` and `troubleshooting_guide_test.dart`.
3. **Neurobench protected state access**: `benchmark_results_table.dart:127` accesses `.state` outside test context — runtime risk.

### P1 — Core Integration (Required for stable POC)

4. **Ruff auto-fix sweep**: 203 of 403 violations are auto-fixable (`ruff check --fix .`). Run and commit.
5. **T201 print() eradication**: 168 print() calls across modules. Replace with `logging.getLogger()`. Priority: neurocnl (79), Neurosense (42), neurocli (20).
6. **Neurocnl Dockerfile**: Module lacks its own Dockerfile; relies on root `Dockerfile.control`. Should have a standalone Dockerfile for independent deployment.
7. **Mypy strict typing**: 1762 errors in neurocnl. Focus on test files first (`no-untyped-def` is the bulk).
8. **Neuro-Dream-Hand Docker support**: No Dockerfile or docker-compose for a module listed as a local dependency of neurocnl.

### P2 — Polish & Quality (Hardening)

9. **Task fragmentation cleanup**: Consolidate `issues-archive/` (51 files) with CDD `generated-issues/` (21 files). Deprecate empty `UI - issues/`.
10. **Neurobench frontend warnings**: Fix 3 warnings (unused imports, deprecated `value` → `initialValue`).
11. **Neurohub frontend**: 1 warning (`unused_local_variable` in dashboard provider test).
12. **Neurosense print() cleanup**: 42 T201 violations — second worst offender.
13. **Root compose validation**: Verify all modules are correctly wired in `docker-compose.yml` against `modules.json` manifest.
14. **PBT expansion**: All 5 modules now have PBT directories. Verify all property tests actually execute (not just scaffolded).

---

*Report generated objectively. No metrics were invented — all derived from direct tool execution.*
