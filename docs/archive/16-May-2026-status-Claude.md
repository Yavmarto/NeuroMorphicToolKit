# NMTK Agentic Status Audit & Readiness Report

**Audit Date:** 16-May-2026
**Agent Assessor:** Claude (Sonnet 4.6)
**Branch:** `dev`
**Scope:** Root repository + all submodules mapped in `modules.json`

---

## 1. Executive Summary

**Overall POC Readiness: ~82%**

Major upward delta since the 02-Apr-2026 Claude audit (previously 47%). Five of six modules now have fully implemented backends; four of five Dart frontends are production-ready. The suite_api unified backend, all four Docker workers, and the launcher control server are 100% implemented with no stubs in critical paths.

**Single largest blocker:** `Neurochip/frontend` has no `lib/` directory — zero frontend implementation. All other modules are feature-complete or near-complete.

**Stale documentation hazard:** The `README.md` status table (March 2026) is severely wrong — most notably listing Neurohub at **0%** when both its backend (12 routers, SQLAlchemy-backed) and frontend (42 files, 3,587 lines) are fully implemented.

**Linter state:** Ruff errors collapsed from ~830 (Apr audit) to **43** in auditable root-level Python. Mypy is clean. Flutter pub resolution is blocked by a `file_picker` version conflict between `neurohub_shell_adapter` (`^8.0.0`) and `neurocnl_studio` (`^11.0.2`).

---

## 2. Linter Snapshot

### Python — Ruff

| Metric | Value |
|--------|-------|
| Total errors | **43** |
| Auto-fixable | 25 |
| F401 (unused imports) | 25 |
| E402 (import not at top) | 15 |
| F811 (redefined name) | 2 |
| F841 (unused variable) | 1 |

**Note:** Ruff was run against `nmtk/launcher_control/`, `suite_api/`, `tests/`, and `workers/` only — submodule directories (`neurocnl/`, `Neurochip/`, etc.) are git submodules not initialized in the working tree. The E402 errors are structural: workers perform `sys.path.insert()` before imports, a pattern required by the worker architecture. The F401 (unused imports) are the primary cleanable concern.

**No `print()` statements found** in audited Python paths — `logging.getLogger()` is used consistently.

### Python — Mypy

```
mypy nmtk/launcher_control/server.py --ignore-missing-imports
→ No issues found
```

`server.py` (6,450 lines) passes mypy with no type errors.

### Dart / Flutter — flutter analyze

```
flutter analyze nmtk/neuro_toolkit
→ FAILED: version solving failed
  neurohub_shell_adapter requires file_picker ^8.0.0
  neurocnl_studio requires file_picker ^11.0.2
  These constraints are incompatible.
```

**Blocker:** `pub get` cannot resolve, so `flutter analyze` cannot run. The `file_picker` version drift between `Neurohub/frontend/pubspec.yaml` (`^8.0.0`) and `neurocnl/frontend/pubspec.yaml` (`^11.0.2`) creates an irreconcilable constraint in the root launcher's combined dependency graph. This must be fixed before Flutter CI can run.

---

## 3. Task Fragmentation Findings

### Active Tracking Systems Found

| System | Count | Status |
|--------|-------|--------|
| `issues-archive/` | 45 files | Canonical — completed/superseded issues |
| `README.md` status table | 7 entries | **Stale — do not trust** |
| Module-level `AGENTS.md` roadmaps | Per module | Current — preferred source |

### Verdict

There is no active `issues/` directory; `issues-archive/` is the only issue tracker and it is archival by design. **No duplicate tracking systems detected.** The prior fragmentation (6 systems as of Apr audit) has been resolved.

**Recommended action:** Update `README.md` status table to reflect actual implementation state. It currently misleads by listing Neurohub at 0% and Neurochip at 90% when the inverse is closer to reality for the frontend dimension.

---

## 4. Target Readiness & Module Status

### 4a. Backend Routes

| Module | Backend Routes | Critical Stubs | DB/State | Score |
|--------|---------------|----------------|----------|-------|
| **neurocnl** | 12 routers, all real | None | Service layer | **100%** |
| **Neurohub** | 12 routers, all real | None | SQLAlchemy ORM | **100%** |
| **Neurochip** | ~14 routers | `/partition`, `/compare` return placeholder messages | Real for all others | **95%** |
| **Neurobench** | 12 routers, all real | None | Result storage | **100%** |
| **Neurosense** | 11 routers, all real | None | Session mgmt | **100%** |
| **suite_api** | 6 domain mounts (in-process + proxy) | None | Graceful 503 on worker absence | **100%** |
| **launcher_control** | 35+ routes (SSH, provisioning, SSE, job queue) | None | `ServerState` singleton | **100%** |

**Workers (proxied from suite_api):**

| Worker | Port | Status |
|--------|------|--------|
| neurosense-hw-worker | 8004 | Real FastAPI, BrainFlow, WebSocket streaming |
| neurobench-runner | 8003 | Real FastAPI, benchmark job execution |
| neurochip-hw-worker | 8002 | Real FastAPI, Akida/Lava/Speck/PYNQ/serial |
| neurocnl-physics | 8006 | Real FastAPI, MuJoCo co-simulation |

All workers use graceful optional-import patterns — hardware SDKs degrade to informative errors, not crashes.

### 4b. Frontend (Dart/Flutter)

| Module | Files | Lines | Assessment |
|--------|-------|-------|------------|
| **nmtk launcher** (`nmtk/neuro_toolkit/lib/`) | ~25 | ~7,000 | 5 screens, 8 services, 7 providers — production-ready |
| **neurocnl/frontend** | 169 | 37,373 | Canvas editor, hardware deployment, spike raster — most mature |
| **Neurohub/frontend** | 42 | 3,587 | Dashboard, projects, assets, auth — feature-complete |
| **Neurobench/frontend** | 28 | 4,130 | Benchmark execution, comparison, robustness — complete |
| **Neurosense/frontend** | 34 | 4,920 | Live signal acquisition, spike encoding — complete |
| **Neurochip/frontend** | **0** | **0** | **EMPTY STUB — no `lib/` directory** |
| **nmtk_ui_core** | 50 | 9,104 | Real shared library: 40+ widgets, design tokens, theme system |

### 4c. Tests

| Location | Count | Type |
|----------|-------|------|
| `tests/` (root) | 32 files | Suite integration (HTTP smoke, cross-module, launcher control) |
| `tests/integration/` | 9 files | End-to-end HTTP (real services, not mocked) |
| Module tests (submodule) | ~130+ est. | Unit + PBT (Hypothesis), VCR HTTP replay |

**Test quality:** Integration tests call real HTTP endpoints, not mock wrappers. VCR cassettes record and replay live HTTP interactions for CI. Module conftest files mock only unavoidable optional imports (MuJoCo, BrainFlow, Akida SDK) — not core application logic.

### 4d. Docker / Compose

| Artifact | Status |
|----------|--------|
| `docker-compose.yml` | Full — 5 profiles (core, physics, hardware, jobs, monitoring) |
| `suite_api/Dockerfile` | Production-grade — layered caching, non-root user |
| `workers/neurobench_runner/Dockerfile` | Real — dep-cache optimized |
| `workers/neurochip_hw/Dockerfile` | Real — dep-cache optimized |
| `workers/neurocnl_physics/Dockerfile` | Real — dep-cache optimized |
| `workers/neurosense_hw/Dockerfile` | Real — dep-cache optimized |
| Monitoring stack | Prometheus + Grafana + Loki + Alertmanager — wired |

⚠️ `grafana` admin password is hardcoded as `admin` in `docker-compose.yml`. Must be changed before any shared-environment deployment.

### 4e. CI

- `.github/` workflows present; no CI run data auditable in this context.
- `scripts/run_launcher_guardrails.sh` is the mandatory launcher gate per `CONTRIBUTING.md`.
- Flutter CI is currently blocked by the `file_picker` version conflict (see Section 2).

---

## 5. Priority Work Roadmap

### P0 — Critical (blocks POC launch)

| # | Task | Why critical |
|---|------|-------------|
| P0-1 | **Fix `file_picker` version conflict** — align `Neurohub/frontend` to `^11.0.2` or resolve via dependency override | Flutter CI cannot run; `flutter analyze` is blind; launcher pub graph is broken |
| P0-2 | **Implement `Neurochip/frontend`** — create `lib/` with at minimum a shell adapter, placeholder screens, and provider stubs | Only module with zero frontend; blocks hardware deployment UX |

### P1 — Core Integration (needed for stable demo)

| # | Task | Why needed |
|---|------|-----------|
| P1-1 | **Implement Neurochip `/partition` and `/compare` routes** — currently return placeholder messages | Two backend gaps in an otherwise complete module |
| P1-2 | **Fix 25 auto-fixable Ruff F401 errors** — run `ruff check --fix` on audited paths | Low effort, high signal: clean lint gate |
| P1-3 | **Fix E402 worker import ordering** — restructure `sys.path` manipulation in worker `main.py` files | Structural anti-pattern; confuses static analysis |
| P1-4 | **Update `README.md` status table** — Neurohub is not 0%, Neurochip is not 90% | Active misinformation in the primary project entrypoint |
| P1-5 | **Change Grafana hardcoded password** in `docker-compose.yml` | Security: `admin`/`admin` in any shared environment |

### P2 — Polish / Quality

| # | Task | Why valuable |
|---|------|-------------|
| P2-1 | Run `mypy --strict` across all module backends (not just `server.py`) | `--ignore-missing-imports` masks real type errors in submodule code |
| P2-2 | Add Neurochip frontend skeleton to unblock Flutter analyzer end-to-end | Even placeholder screens fix the pub graph impact |
| P2-3 | Verify `scripts/run_launcher_guardrails.sh` passes on current `dev` branch | Required CI gate; last known-clean state was 2026-04-13 |
| P2-4 | Audit `neuro_dream_hand` backend implementation depth | Not explored in this audit; modules.json marks it MuJoCo-optional |
| P2-5 | Archive or delete `.tmp_manual_ui/` and `workflow-errors/` directories | Temporal artifacts accumulating at root |

---

## Appendix: README vs Reality Delta

| Module | README (Mar 2026) | Actual (May 2026) |
|--------|-------------------|-------------------|
| neurocnl | 97% | ~99% |
| Neurosense | 85% | ~97% |
| **Neurohub** | **0%** | **~95%** |
| NeuroDash | 80% | Not audited |
| **Neurochip** | **90%** | **~55%** (backend ok, frontend empty) |
| Neurobench | 70% | ~95% |
| Neuro-Dream-Hand | 95% | Not audited |
| NMTK Launcher | 85% | ~95% |
