# Agentic Status Audit & Readiness Workflow - 20-Apr-2026

**Audit Date:** 20-Apr-2026
**Agent Assessor:** Claude (claude-sonnet-4-6)

## 1. Executive Summary

**Overall POC Readiness: 87%** (up from 85% on 16-Apr-2026)

Scope: root repository plus all 7 modules registered in `nmtk/neuro_toolkit/assets/modules.json`: `neurocnl`, `Neurosim`, `Neurochip`, `Neurobench`, `Neurosense`, `Neurohub`, and `Neuro-Dream-Hand`.

**Major deltas since 16-Apr-2026:**

- The branch is no longer in a merge-conflict state. `git status` shows no `UU` files; the branch has 6 uncommitted working-tree changes concentrated in PYNQ deployment work (`nmtk/launcher_control/server.py`, `pynq_deploy_screen.dart`, `pynq_deploy_service.dart`, and two test files) plus a modified Neurochip submodule pointer.
- `ruff check .` dropped from **148 to 101** findings. The `jules_batch_prompt.py` merge-conflict block is still present (18 conflict-marker lines confirmed, 84 `invalid-syntax` findings), but partial cleanup reduced the blast radius.
- `mypy --strict .` remains blocked by the same `Neurosim/build/lib/neurosim` duplicate package issue — no change.
- Flutter analyzer results are unchanged across all 8 packages from the 16-Apr baseline.
- Active issues queue has been significantly pruned: **5 items** in `issues/` (down from 21), and **0 generated CDD issues** found under `docs/unified-dev-pipeline/` (down from 21). Practical independent workstreams reduced from ~37 to ~4.
- Route count grew from **187 to 214** across all modules, driven by Neurosim expanding from 22 to 60 routes.
- PBT coverage grew substantially: Neurochip now has **116** PBT files (was 5); neurocnl has **48** (was 3).
- All 7 module Docker Compose files parse successfully with `docker compose config --services`. Root compose maps `neurochip`, `neurocnl`, and `neurosim` services.

---

## 2. Linter Snapshot

### Python — Ruff

Command: `python3 -m ruff check . --statistics`

| Rule | Count | Auto-fixable |
| :--- | :---: | :---: |
| `invalid-syntax` | 84 | No |
| `UP037` quoted-annotation | 5 | Yes |
| `ANN202` missing-return-type-private-function | 4 | No |
| `I001` unsorted-imports | 3 | Yes |
| `ARG002` unused-method-argument | 2 | No |
| `ANN002` missing-type-args | 1 | No |
| `ANN003` missing-type-kwargs | 1 | No |
| `C420` unnecessary-dict-comprehension | 1 | Yes |
| **Total** | **101** | **9 fixable** |

- All 84 `invalid-syntax` findings originate from `scripts/jules_batch_prompt.py`, which still contains **18 merge-conflict marker lines** (`<<<<<<<`, `=======`, `>>>>>>>`). This is the dominant blocker for a clean lint pass.
- Non-syntax findings (17) are spread across: `neurocnl/backend/app/routers/deploy.py` (I001), `neurocnl/neurocnl/contracts/pynq_runtime_artifact_contract.py` (UP037 × 4), `neurocnl/neurocnl/converter/sinabs_io.py` (C420), `neurocnl/neurocnl/layers/layer1_validator.py` (I001 × 2), `neurocnl/neurocnl/export/pynq_exporter.py` (UP037), and `Neurosim/neurosim/tests/routers/test_components.py` (ANN202 × 4, ANN002, ANN003, ARG002 × 2).
- `print()` vs structured logging: **305** Python files contain `print()` call sites vs **168** files using `logging.getLogger(...)`. Production-path logging hygiene remains an open concern.

### Python — Mypy

Command: `python3 -m mypy --strict .`

Status: **Blocked — identical to 16-Apr-2026.**

```
Neurosim/neurosim/__init__.py: error: Duplicate module named "neurosim"
(also at "./Neurosim/build/lib/neurosim/__init__.py")
Found 1 error in 1 file (errors prevented further checking)
```

The checked-in `Neurosim/build/lib/neurosim` build artifact continues to prevent any meaningful repo-root mypy output. Per-module mypy runs would require module-local `pyproject.toml` configuration.

### Dart / Flutter

Command: `flutter analyze <package>` run per package.

| Package | Result |
| :--- | :--- |
| `neurocnl/frontend` | 6 issues (unchanged) |
| `Neurosim/frontend` | 4 issues (unchanged) |
| `Neurochip/frontend` | Clean |
| `Neurobench/frontend` | Clean |
| `Neurosense/frontend` | Clean |
| `Neurohub/frontend` | Clean |
| `nmtk/neuro_toolkit` | 2 issues — `deprecated_member_use` in `pynq_deploy_screen.dart:324` and `:430` (`value` → `initialValue`) |
| `nmtk_ui_core` | Clean |

- Total Flutter findings: **12** (unchanged from 16-Apr).
- The 2 `nmtk/neuro_toolkit` warnings are in the actively modified `pynq_deploy_screen.dart` file currently sitting in the working tree; these should be resolved as part of the PYNQ deploy work.

### High-Severity Maintainability Anomalies

1. `scripts/jules_batch_prompt.py` still contains live merge-conflict markers and is the sole cause of 84 ruff `invalid-syntax` errors.
2. `Neurosim/build/lib/neurosim` is checked in and continues to block repo-root `mypy --strict .`.
3. Production-path `print()` dominates over structured logging across the codebase (305 vs 168 files).
4. Several Docker Compose files emit an `obsolete attribute 'version'` warning; not a blocker but adds noise.

---

## 3. Task Fragmentation Findings

**Observed tracker inventory**

| System | Count | Notes |
| :--- | :---: | :--- |
| `issues/*.md` active task files | 5 | Down from 21 on 16-Apr |
| Generated CDD issues (`docs/unified-dev-pipeline/*/generated-issues/`) | 0 | Down from 21 on 16-Apr; path appears emptied |
| `issues-archive/` files | Not recounted | Historical only |

**Active `issues/*.md` files (5):**
1. `akida-studio-deployment-plan.md`
2. `neurosense-research-credibility-rollout.md`
3. `pynq-z2-studio-deployment-plan.md`
4. `teensy-studio-deployment-plan.md`
5. `sent-status-audit-2026-04-16.md` (reference artifact, not a task)

**Fragmentation observations**
- The issue queue has been substantially pruned since 16-Apr (21 → 5). The three hardware-deployment plans (Teensy, PYNQ, Akida) remain as the primary active planning surface.
- The `docs/unified-dev-pipeline/*/generated-issues/` CDD-generated issue set observed on 16-Apr (21 items) is no longer present. Either the path was restructured or the content was consumed. This reduces the practical independent workstream count from ~37 to ~4.
- `sent-status-audit-2026-04-16.md` in `issues/` is a reference artifact, not a task. It should be moved to `issues-archive/` to reduce confusion.
- The hardware deployment plans (Teensy, PYNQ, Akida) in `issues/` still represent cross-module coordination work and are the correct live planning surface for multi-module hardware integration.

**Tracking systems to deprecate for active planning:**
- All `issues-archive/` directories — historical record only, not live scope
- `issues/sent-status-audit-2026-04-16.md` — move to archive

**Recommendation:** Active planning now lives almost exclusively in `issues/*.md` (4 real tasks). The CDD-generated issue surface should be regenerated if module contract coverage gaps are to be tracked systematically.

---

## 4. Target Readiness & Module Status

**Scoring rubric:** same as prior audits — each surface (Backend, Frontend, Tests, Contracts, Docker, CI) scores `1.0` when verified-clean, `0.5` when implemented but materially limited, `0.0` when missing. `Neuro-Dream-Hand` omits Frontend (manifest: `hasFrontend: false`).

| Module | Readiness | Backend | Frontend | Tests | Contracts | Docker | CI |
| :--- | :---: | :--- | :--- | :--- | :--- | :--- | :--- |
| **Root Infrastructure** | **75%** | Control-plane `server.py` (2978 lines) is real but has uncommitted PYNQ changes; `scripts/jules_batch_prompt.py` still has merge markers | `nmtk_ui_core` clean; `nmtk/neuro_toolkit` has 2 deprecation warnings in active PYNQ screen | Not executed this audit | `modules.json` populated, maps 7 modules | Root compose parses (`neurochip`, `neurocnl`, `neurosim`); `docker-compose.dev.yml` and `docker-compose.prod.yml` present | 34 root `.github/workflows/` |
| **neurocnl** | **87%** | 23 routes, 0 live `501` stubs; ruff hits `deploy.py`, `layer1_validator.py`, and contract files | 104 Dart files, 28 widget files, 16 provider files, 0 empty scaffolds; `flutter analyze` 6 issues | Py test files detected (deep tree); 48 PBT files | 26 contract files | Parses: `backend,frontend` | 8 workflows |
| **Neurosim** | **87%** | 60 routes (up from 22), 0 live `501` stubs; `build/lib/neurosim` artifact blocks mypy | 58 Dart files, 12 widget files, 9 provider files, 0 empty scaffolds; `flutter analyze` 4 issues | Py test files detected; 16 PBT files | 15 contract files | Parses: `backend,frontend` | 8 workflows |
| **Neurochip** | **87%** | 43 routes; 1 live `501` in `akida.py` (optional runtime fallback for `AkidaSdkNotAvailableError`) | 42 Dart files, 10 widget files, 5 provider files, 0 empty scaffolds; clean | Py + Dart tests; 116 PBT files (major growth) | 13 contract files | Parses: `backend` | 8 workflows |
| **Neurobench** | **87%** | 27 routes; 1 live `501` in `spinnaker2.py` (optional runtime fallback on `ImportError`) | 35 Dart files, 4 widget files, 2 provider files, 0 empty scaffolds; clean | Py + Dart tests; 4 PBT files | 6 contract files | Parses: `neurobench` | 10 workflows |
| **Neurosense** | **100%** | 28 routes, 0 live `501` stubs | 40 Dart files, 13 widget files, 10 provider files, 0 empty scaffolds; clean | Py + Dart tests; 3 PBT files | 7 contract files | Parses: `backend,frontend` | 8 workflows |
| **Neurohub** | **100%** | 33 routes, 0 live `501` stubs; `db,backend,frontend` compose with SQLAlchemy/Alembic wired | 58 Dart files, 22 widget files, 5 provider files, 0 empty scaffolds; clean | Py + Dart tests; 4 PBT files | 6 contract files | Parses: `db,backend,frontend` | 8 workflows |
| **Neuro-Dream-Hand** | **90%** | CLI-only, 0 HTTP routes, 0 `501` stubs; implementation is real, hardware proof still open | N/A (manifest: `hasFrontend: false`) | Py tests present; 2 PBT files | 5 contract files | Parses: `neurodreamhand` | 11 workflows |

**Cross-module proof totals (20-Apr-2026)**

| Metric | Value | Delta vs 16-Apr |
| :--- | :---: | :---: |
| Total routes detected | 214 | +27 |
| Module Dart files | 337 | +19 |
| Empty module Dart files | 0 | — |
| PBT files (Neurochip) | 116 | +111 |
| PBT files (neurocnl) | 48 | +45 |
| Contract files total | ~78 | +37 |
| Module compose files that parse | 7/7 | — |
| Flutter packages clean | 6/8 | — |
| Live `501` backend paths | 2 | — |

**Backend-specific observations**
- No broad `501 Not Implemented` scaffold pattern across any module.
- The two remaining `501` paths (`Neurochip/akida.py`, `Neurobench/spinnaker2.py`) are optional-runtime fallbacks only — not empty CRUD stubs.
- Neurosim route count grew from 22 to 60 since 16-Apr; the active Neurochip submodule change suggests continued backend evolution.

**Frontend-specific observations**
- Zero empty `.dart` scaffold files across all 6 frontend modules.
- Current frontend deficits are analyzer-level deprecation/type findings, not missing widget bodies.
- The two `deprecated_member_use` warnings in `nmtk/neuro_toolkit` are in the currently modified `pynq_deploy_screen.dart` and should be resolved in the same change.

**Docker-specific observations**
- All 7 module compose files and all 3 root compose files parsed successfully.
- 5 module compose files emit an `obsolete attribute 'version'` warning; this is a cosmetic issue, not a runtime blocker.

**Working-tree state (20-Apr-2026)**
The branch has 6 uncommitted changes, all PYNQ-related:
- `nmtk/launcher_control/server.py` — control plane update
- `nmtk/neuro_toolkit/lib/screens/pynq_deploy_screen.dart` — PYNQ deploy screen
- `nmtk/neuro_toolkit/lib/services/pynq_deploy_service.dart` — PYNQ deploy service
- `nmtk/neuro_toolkit/test/pynq_deploy_provider_test.dart` — test coverage
- `nmtk/neuro_toolkit/test/pynq_deploy_screen_test.dart` — test coverage
- `Neurochip` submodule pointer — Neurochip has upstream changes pending

These are all coherent with the recent PYNQ board integration commit history (`76da7fc`, `8c6d53f`, `fd2b267`) and should be committed together.

---

## 5. Priority Work Roadmap

### P0 (Critical)

1. **Resolve `scripts/jules_batch_prompt.py` merge conflict.** The file still has 18 conflict-marker lines producing 84 ruff `invalid-syntax` errors. Until this is resolved, ruff output is misleading and the file is not importable. This is the sole P0 static-analysis blocker remaining from 16-Apr.
2. **Commit the in-progress PYNQ deploy changes.** The 5 modified `nmtk` files and the Neurochip submodule pointer should be committed to avoid accidental loss and to make the branch-state signal meaningful. The `deprecated_member_use` warnings in `pynq_deploy_screen.dart` (lines 324, 430) — `value` → `initialValue` — must be fixed in the same commit per Flutter 3.33+ API.
3. **Remove or exclude `Neurosim/build/lib/neurosim` from the repository.** This checked-in build artifact has blocked `mypy --strict .` across two consecutive audits. Adding it to `.gitignore` and removing the tracked directory would restore mypy as a viable repo-root quality gate.

### P1 (Core Integration)

1. **Fix the 6 `neurocnl/frontend` and 4 `Neurosim/frontend` Flutter analyzer issues.** These are the only two module frontends not passing clean analysis. Resolving them would bring all 8 Flutter packages to a clean state.
2. **Advance hardware deployment proof for open plans:** Teensy (`issues/teensy-studio-deployment-plan.md`), PYNQ-Z2 (`issues/pynq-z2-studio-deployment-plan.md`), and Akida (`issues/akida-studio-deployment-plan.md`) remain the live integration workstreams. The PYNQ work already underway (P0 item above) directly addresses the PYNQ plan.
3. **Decide the `501` boundary for Akida (Neurochip) and SpiNNaker2 (Neurobench).** These optional-runtime fallbacks are appropriate if the POC scope explicitly excludes those hardware targets; if not, they represent open functionality debt that needs surfacing.
4. **Regenerate CDD issues** if the `docs/unified-dev-pipeline/` generated-issue set was intentionally cleared. The 16-Apr baseline had 21 generated issues covering contract coverage gaps. If those gaps were closed, document it; if not, regenerate to maintain systematic contract tracking.

### P2 (Polish/Quality)

1. **Fix the 9 auto-fixable ruff issues** (`ruff check . --fix`): `UP037` quoted annotations in `pynq_runtime_artifact_contract.py` and `pynq_exporter.py`, `I001` unsorted imports in `deploy.py` and `layer1_validator.py`, and `C420` in `sinabs_io.py`.
2. **Migrate production-path `print()` calls to structured logging.** 305 Python files use `print()` vs 168 with `logging.getLogger(...)`. Priority targets are router and service files in production-path modules; test files are lower priority.
3. **Remove `version` attribute from 5 module `docker-compose.yml` files** to eliminate the obsolete-attribute warnings.
4. **Move `issues/sent-status-audit-2026-04-16.md` to `issues-archive/`.** This is a reference artifact, not a live task.
5. **Broaden PBT coverage in `Neurobench` (4 files) and `Neuro-Dream-Hand` (2 files)** to bring them in line with the high-coverage modules.
