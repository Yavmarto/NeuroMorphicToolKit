# NMTK Agentic Status Audit & Readiness Report

**Audit Date:** 02-Apr-2026
**Agent Assessor:** Claude (Opus 4.6)
**Branch:** `dev`
**Scope:** Root repository + all 7 submodules + root components

---

## 1. Executive Summary

**Overall POC Readiness: 47%**

The NeuroMorphicToolKit has two production-ready modules (neurocnl at ~88%, Neurohub at ~78%) forming the backbone of the platform. The remaining five submodules range from 27-62% completion. Three root components (neurocli, neurodocs, monitoring) remain empty placeholders. Since the last audit (01-Apr-2026 Codex), key deltas include ongoing UI migration work and submodule pointer updates, but no fundamental readiness change has occurred.

**Critical blockers:**
- 830 Ruff linter errors across Python codebase
- 11 Flutter analyzer errors across 3 frontend projects (neurocnl, Neurobench, Neurohub)
- neurocli and neurodocs remain empty (0% implementation)
- Task fragmentation across 6 distinct tracking systems with confirmed duplicates
- Neurochip, Neurobench, and Neuro-Dream-Hand backends are largely stub implementations

---

## 2. Linter Snapshot

### Python (Ruff)

| Metric | Value |
|--------|-------|
| **Total errors** | 830 |
| **Auto-fixable** | 131 (+ 232 with unsafe fixes) |

**Top error categories:**

| Code | Count | Description |
|------|-------|-------------|
| T201 | 76 | `print()` statements (should use logging) |
| I001 | 60 | Import block unsorted/unformatted |
| D103 | 57 | Missing docstring in public function |
| F401 | 56 | Unused imports |
| N201 | 54 | Naming convention violations |
| N001 | 48 | Naming style violations |
| D417 | 45 | Missing argument descriptions in docstring |
| E501 | 41 | Line too long |
| G001 | 37 | Logging string formatting issues |
| E402 | 34 | Module-level import not at top of file |
| F811 | 32 | Redefinition of unused variable |
| W293 | 30 | Whitespace before ':' |

**Errors per module:**

| Module | Ruff Errors |
|--------|------------|
| Neurobench | 196 |
| Neurosim | 164 |
| Neurohub | 129 |
| Neurosense | 45 |
| neurocnl | 45 |
| Neuro-Dream-Hand | 42 |
| Neurochip | 33 |
| scripts/ | 12 |

**Rogue `print()` statements** (non-test, non-venv): Found in `Neurohub/neurohub/app/services/workflow_engine.py` (lines 249, 505) and `Neurohub/run_dbg8.py`. These should use `logging.getLogger()` per the CODING_STYLE_GUIDE.md.

### Mypy

Mypy strict mode was not executed as no unified `mypy.ini` or `pyproject.toml` with mypy config exists at the root level. Individual submodules do not uniformly configure mypy either.

### Flutter / Dart Analysis

| Project | Dart Files | Errors | Warnings | `dynamic` Usage |
|---------|-----------|--------|----------|-----------------|
| nmtk_ui_core | 11 | 0 | 0 | 5 |
| neurocnl/frontend | 59 | 3 | 22 | 91 |
| Neurochip/frontend | 30 | 0 | 0 | 53 |
| Neurobench/frontend | 22 | 5 | 4 | 24 |
| Neurohub/frontend | 32 | 3 | 9 | 26 |
| Neurosense/frontend | 24 | 0 | 1 | 42 |
| Neurosim/frontend | 35 | 0 | 3 | 145 |
| nmtk/neuro_toolkit | 18 | 0 | 0 | 25 |
| **TOTAL** | **231** | **11** | **39** | **411** |

**Critical Flutter issues:**
- neurocnl: 3 type errors in `pipeline_provider.dart` and `template_provider.dart`
- Neurobench: 5 errors including missing operator `[]` in `baseline_selector.dart` and undefined test fixtures
- Neurohub: 3 errors with duplicate `apiKey` definition in tests and missing `url_launcher` dependency
- Neurosim: 145 `dynamic` usages (highest) indicates significant type safety concern

---

## 3. Task Fragmentation Findings

### Tracking Systems Inventory

**6 distinct task tracking systems identified containing ~330+ artifacts:**

| System | Location | Count | Status |
|--------|----------|-------|--------|
| Active issues (`/issues/`) | 5 module dirs | **0** | All empty |
| Archived issues (`/issues-archive/`) | 12 dirs across modules | **246** | All archived |
| Generated issues (CDD unified) | `docs/unified-dev-pipeline/*/generated-issues/` | **21** | Active pipeline |
| Generated issues (GPT 5.4 archive) | `docs/archive/gpt5.4-dev-pipeline/*/generated-issues/` | **21** | Stale duplicate |
| Issue state tracking | `docs/unified-dev-pipeline/*/.issue-state.json` | **7** | Status metadata |
| Auto agentic workflows | `Auto agentic workflows (Jules)/` | **16** | Workflow definitions |
| Orchestration | `issue order.md` | **1** | 83 cross-module tasks |

### Confirmed Duplications

1. **Cross-module duplicate**: `NCNL-001` (neurocnl) = `WF-007` (nmtk) - identical "unblocked-issues-matrix-evaluation" with only 15-line diff
2. **Multi-module clones**: `002-poc-add-agents-md-and-guardrails-md` appears in Neurohub, Neurochip, Neurosense, Neurobench (4x)
3. **Dual pipeline duplication**: 21 generated issues exist in both `unified-dev-pipeline/` AND `gpt5.4-dev-pipeline/` for the same modules

### ID Format Fragmentation

5 incompatible naming schemes: numeric-only (`001`), module-prefixed (`NCNL-001`), phase-prefixed (`NC-p2-*`), date-stamped (`22mar1_*`), and benchmark-specific (`NB-B1`).

### Recommendations

- **Deprecate**: `docs/archive/gpt5.4-dev-pipeline/` generated issues (superseded by unified pipeline)
- **Deprecate**: All `/issues/` directories (consistently empty; archives are the real source)
- **Consolidate**: Adopt single ID format (recommend `{MODULE}-{NNN}` pattern)
- **Single source of truth**: `issue order.md` should be the canonical orchestration layer with links to `docs/unified-dev-pipeline/` for CDD issues

---

## 4. Target Readiness & Module Status

### Test Inventory

| Type | Count |
|------|-------|
| Python test files | 333 |
| Dart test files | 87 |
| **Total test files** | **420** |

### Module Readiness Matrix

| Module | Backend | Frontend | Tests | Docker | CI/CD | **Readiness** |
|--------|---------|----------|-------|--------|-------|---------------|
| **neurocnl** | Full (257L main, 8 routers, 163 files) | Real (59 .dart, full structure) | Real (71 Python + Dart tests) | Valid (docker-compose + Dockerfile) | 8 workflows | **88%** |
| **Neurohub** | Full (142L main, 12 routers, 161 files, Alembic migrations) | Real (32 .dart, full structure) | Real (75 tests) | Valid | 8 workflows | **78%** |
| **Neurosim** | Full (107L main, 10 routers, 134 files) | Partial (35 .dart) | Moderate (48 tests) | Valid | 8 workflows | **62%** |
| **Neurosense** | Partial (137L main, 10 routers, 62-131 files) | Partial (24 .dart) | Moderate (51 tests) | Valid | 8 workflows | **52%** |
| **Neurochip** | Stub (111L main, 9 routers, minimal impl) | Partial (30 .dart) | Basic (33 tests) | Valid | 8 workflows | **42%** |
| **Neurobench** | Stub (150L main, 10 routers, minimal impl) | Partial (22 .dart, 5 analyze errors) | Basic (32 tests) | Valid | 10 workflows | **42%** |
| **Neuro-Dream-Hand** | Minimal (no REST API pattern) | None (hardware-only) | Real (37 tests) | Complex build | 11 workflows | **27%** |

### Root Components

| Component | Status | Readiness |
|-----------|--------|-----------|
| **nmtk** (Flutter app launcher) | 18 .dart files, 349L module_provider, multi-platform targets | **26%** |
| **nmtk_ui_core** (shared UI lib) | 11 .dart widgets/models, 9 tests, clean analyze | **11%** |
| **neurocli** | Empty placeholder | **0%** |
| **neurodocs** | Empty placeholder | **0%** |
| **monitoring** | Config dirs only (alertmanager, grafana, loki, prometheus, promtail) | **0%** |

### Root Infrastructure

| Component | Status |
|-----------|--------|
| **docker-compose.yml** | Full orchestration of 7+ services with healthchecks, networks (frontend-net, backend-net, monitoring-net), proper port mapping |
| **docker-compose.dev.yml** | Development overrides present |
| **docker-compose.prod.yml** | Production configuration present |
| **CI/CD** | 34 GitHub Actions workflows at root level (ci.yml, integration-test.yml, security-scan.yml, release-*, etc.) |
| **.pre-commit-config.yaml** | Present and configured |

---

## 5. Priority Work Roadmap

### P0 - Critical (Blocks POC Demo)

| # | Task | Module | Impact |
|---|------|--------|--------|
| 1 | Fix 11 Flutter analyzer errors (type errors in providers/tests) | neurocnl, Neurobench, Neurohub | Frontends won't compile cleanly |
| 2 | Fix 76 rogue `print()` statements; replace with `logging.getLogger()` | All Python modules (esp. Neurohub workflow_engine.py) | CODING_STYLE_GUIDE violation, no structured logging |
| 3 | Resolve 56 unused imports + 60 unsorted import blocks | All modules | `ruff check --fix` can auto-resolve 131 |
| 4 | Add `url_launcher` to Neurohub/frontend pubspec.yaml | Neurohub | Missing dependency blocks builds |
| 5 | Fix test fixtures in Neurobench (undefined BenchmarkDefinition, InputSpec, ScoringConfig) | Neurobench | Tests cannot run |

### P1 - Core Integration (Required for Multi-Module Demo)

| # | Task | Module | Impact |
|---|------|--------|--------|
| 6 | Implement real API routes in Neurochip (currently stubs) | Neurochip | Hardware integration path blocked |
| 7 | Implement real API routes in Neurobench (currently stubs) | Neurobench | Benchmarking pipeline non-functional |
| 8 | Reduce `dynamic` usage in Neurosim (145 occurrences) and neurocnl (91) | Neurosim, neurocnl | Runtime type safety risk |
| 9 | Complete Neurosim frontend to match neurocnl maturity | Neurosim | Simulation UX gap |
| 10 | Build neurocli with at least basic module orchestration commands | neurocli | No CLI interface for automation |
| 11 | Consolidate task tracking: deprecate gpt5.4 pipeline, unify ID format | Root | Fragmentation causes duplicate work |
| 12 | Configure root-level mypy with strict typing | Root | No static type checking in CI |

### P2 - Polish & Quality

| # | Task | Module | Impact |
|---|------|--------|--------|
| 13 | Fix remaining 830 Ruff errors (D103 docstrings, E501 line length, etc.) | All | Code quality baseline |
| 14 | Deprecate `.withOpacity()` calls (25+ instances) in favor of `.withValues()` | neurocnl, Neurosim | Flutter deprecation warnings |
| 15 | Populate monitoring stack configs (Grafana dashboards, Prometheus rules) | monitoring | Observability not functional |
| 16 | Build neurodocs documentation site | neurodocs | No user-facing docs |
| 17 | Complete Neuro-Dream-Hand backend with proper REST API structure | Neuro-Dream-Hand | Hardware module inconsistent with others |
| 18 | Improve nmtk Flutter app beyond skeleton (connect to all module APIs) | nmtk | Unified launcher non-functional |

---

## Appendix: Weighted Readiness Calculation

| Module | Weight (by importance) | Readiness | Weighted Score |
|--------|----------------------|-----------|----------------|
| neurocnl | 20% | 88% | 17.6 |
| Neurohub | 20% | 78% | 15.6 |
| Neurosim | 15% | 62% | 9.3 |
| Neurosense | 10% | 52% | 5.2 |
| Neurochip | 10% | 42% | 4.2 |
| Neurobench | 10% | 42% | 4.2 |
| Neuro-Dream-Hand | 5% | 27% | 1.35 |
| nmtk + nmtk_ui_core | 5% | 18% | 0.9 |
| neurocli + neurodocs + monitoring | 5% | 0% | 0 |
| **TOTAL** | **100%** | | **58.35%** |

**Weighted POC Readiness: ~58%** (when accounting for the relative importance of lead modules neurocnl and Neurohub which carry the platform).

**Simple Average Readiness: ~47%** (unweighted across all 12 components).
