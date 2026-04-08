# Agentic Status Audit & Readiness Workflow - 08-Apr-2026

**Audit Date:** 08-Apr-2026
**Agent Assessor:** Codex

---

## 1. Executive Summary
**Overall POC Readiness: 79%**

This audit was executed from the repository root, so it covers root infrastructure plus all 7 modules defined in `nmtk/neuro_toolkit/assets/modules.json`. The codebase is materially more real than the task trackers imply: all 7 modules have runnable backend entrypoints, all 7 module frontends contain non-empty Dart code, all 7 modules have Docker coverage, and every module has CI workflow files. The strongest technical proof is structural: 237 Python test files, 26 property-test files, 44 contract files, and 249 non-empty Dart files were found across the audited scope.

The biggest gap between perceived and actual status is now concentrated in code health rather than missing scaffolds. `./scripts/analyze_flutter.sh` completed across 8 Flutter packages and found only **17 issues total** across 3 packages (`nmtk_ui_core`: 4, `nmtk/neuro_toolkit`: 9, `neurocnl/frontend`: 4); the other 5 packages analyzed cleanly. By contrast, repo-scope Python health is much rougher than prior reports suggested: `ruff check . --statistics` found **437 issues**, led by **170 invalid-syntax hits**, and `mypy --strict` only passed cleanly in `Neurohub` and `Neurobench`.

The most severe readiness blocker is **Neurosense**, which currently contains unresolved merge conflict markers in runtime code and tests. `mypy --strict` stops immediately on `Neurosense/neurosense/app/routers/devices.py`, and conflict markers are also present in `device_manager.py`, `validate_hardware.py`, and `test_device_manager.py`. Until those conflicts are resolved, Neurosense cannot be treated as POC-ready despite having meaningful implementation depth elsewhere.

**Major Deltas Since Last Run (compared with 02-Apr-2026 audit files):**
- **Frontend reality improved sharply:** this run found 17 total Flutter analyzer issues, not the 13,935 issues reported on 02-Apr-2026.
- **Docker remains solid:** root `./scripts/validate_docker_compose.sh` passed 10/10 checks, and all 7 module compose files parsed with `docker compose config --quiet`.
- **Neurosense regressed or was previously misreported:** unresolved merge conflicts now make one module syntactically broken.
- **Repo-wide Python lint debt is higher than the last report claimed:** 437 Ruff issues at repo scope versus the previously reported 72.
- **Tracking is slightly more consolidated at the active layer:** active markdown work now lives primarily in root `issues/` (24 files) plus unified CDD `generated-issues/` (21 files), but 469 archived issue files still pollute planning context.

---

## 2. Linter Snapshot

### Python (Ruff & Mypy)
- **Ruff:** `ruff check . --statistics` found **437 issues**.
  - Top categories: `invalid-syntax` 170, `I001` unsorted-imports 71, `F401` unused-import 61, `UP006` non-pep585-annotation 26.
- **Logging vs. print:** `rg` found **679** `print()` call sites versus **71** `logging.getLogger()` call sites.
- **Conflict markers:** `rg` found **22** merge-conflict marker hits, with live code/test blockers in Neurosense.

### Mypy (`--strict`)
| Scope | Result |
| :--- | :--- |
| `Neuro-Dream-Hand` | **5 errors** in 2 files |
| `neurocnl` | **11 errors** in 4 files |
| `Neurosense` | **1 syntax error** in 1 file, further checking blocked |
| `Neurohub` | **Pass** (`89` source files checked) |
| `Neurochip/neurochip` | **370 errors** in 49 files |
| `Neurobench/neurobench` | **Pass** (`76` source files checked) |
| `Neurosim/neurosim` | **2 errors** in 1 file |

### Dart / Flutter
- **Packages analyzed:** 8
- **Clean packages:** `Neurohub/frontend`, `Neurosim/frontend`, `Neurochip/frontend`, `Neurosense/frontend`, `Neurobench/frontend`
- **Failing packages:** `nmtk_ui_core` (4 issues), `nmtk/neuro_toolkit` (9 issues), `neurocnl/frontend` (4 issues)
- **Total Flutter issues observed:** **17**
- **Important note:** the isolation exception did not apply here because `nmtk_ui_core` exists locally and was analyzed directly.

### Docker Compose Validation
- Root validation via `./scripts/validate_docker_compose.sh`: **10 passed, 0 failed**
- Module-level `docker compose config --quiet`: **all 7 modules passed**
- Compose warnings remain in `Neuro-Dream-Hand`, `neurocnl`, `Neurosense`, `Neurochip`, and `Neurosim` due to obsolete `version` keys

---

## 3. Task Fragmentation Findings

| System | Count | Current Value | Recommendation |
| :--- | ---: | :--- | :--- |
| Root `issues/` | 24 active markdown files | Primary cross-module work queue | **Retain** |
| Unified CDD `generated-issues/` | 21 active markdown files | Primary module-level CDD queue | **Retain, but refresh stale items** |
| Submodule `issues/` folders | 0 active markdown files | Mostly empty, with stray `.DS_Store` files | **Deprecate for planning** |
| `issues-archive/` across repo | 469 archived markdown files | Historical record only | **Deprecate for active planning** |
| `issues-future/` | 17 markdown files | Long-range backlog | **Retain as backlog only** |

**Fragmentation analysis:**
1. Active tracking is not duplicated by filename, but it is duplicated by **theme**. For example, `issues/09-opus-pynq-runtime-artifact-contract.md` overlaps the contract extraction work already represented in `docs/unified-dev-pipeline/neurochip/generated-issues/01-...` and `docs/unified-dev-pipeline/neurocnl/generated-issues/01-...`.
2. `issues/18-opus-akida-deployment-contract.md` also overlaps the existing Neurochip deployment/quantization contract track rather than representing a cleanly separate body of work.
3. Some generated issues are stale against current repo reality. `docs/unified-dev-pipeline/neurohub/generated-issues/03-neurohub-create-ci-from-scratch-and-add-cdd-pbt-verification.md` still claims "Neurohub has no CI at all", but `Neurohub/.github/workflows/` already contains 8 workflow files including `neurohub-ci.yml`.
4. Submodule-local `issues/` directories are effectively dead but still add noise. During this audit, the only files found there were `.DS_Store` placeholders or nothing at all.

**Consolidated remaining task count:**
- Verified active tracked files: **45** (`24` root issues + `21` unified generated issues)
- Verified overlap clusters: **at least 2**
- Practical remaining count: **low 40s**, not 45 independent tasks

**Tracking systems that should be deprecated for active planning:**
- All submodule-local `issues/` folders
- All `issues-archive/` folders
- Any generated CI issue that no longer matches actual workflow state until it is regenerated

---

## 4. Target Readiness & Module Status

**Cross-module implementation proof**
- Python test files: **237**
- Property-test files: **26**
- Contract files: **44**
- Dart files under `lib/`: **249**
- Empty Dart scaffolds: **0**

| Scope | Readiness | Backend | Frontend | Tests | Contracts | Docker | CI | Status Notes |
| :--- | :---: | :--- | :--- | :--- | :--- | :---: | :---: | :--- |
| **Root Infrastructure** | **82%** | 34 root workflows; root compose validation passed | Toolkit/shared UI are real but not analyzer-clean (`13` issues across `nmtk_ui_core` + `nmtk/neuro_toolkit`) | N/A | N/A | ✅ | ✅ | Infra is strong; tracker sprawl is the main root-level drag |
| **Neuro-Dream-Hand** | **81%** | No `501` stubs found; Docker + CLI backend present | N/A | 41 test files / 2 PBT files | 3 contract files | ✅ | ✅ | Good implementation depth, but `mypy --strict` still reports 5 errors |
| **neurocnl** | **86%** | Multi-router FastAPI backend with parse/validate/generate/simulate/export/deploy/job routes | 67 non-empty Dart files; analyzer has 4 test-only inference warnings | 40 test files / 3 PBT files | 10 contract files | ✅ | ✅ | Strongest mixed backend/frontend module after Neurobench; typing cleanup remains |
| **Neurosense** | **52%** | Many routers and services exist, but merge conflicts break trust in current runtime state | 24 non-empty Dart files; analyzer clean | 30 test files / 4 PBT files | 7 contract files | ✅ | ✅ | Hard blocker: unresolved conflict markers in runtime code and tests |
| **Neurohub** | **88%** | Real app startup, Alembic migration hookup, workflow worker loop, and multiple routers | 32 non-empty Dart files; analyzer clean | 32 test files / 5 PBT files | 5 contract files | ✅ | ✅ | One of the healthiest modules; generated "create CI from scratch" task is stale |
| **Neurochip** | **70%** | Broad API surface is implemented, but Akida routes still return `501` when SDK is unavailable | 30 non-empty Dart files; analyzer clean | 35 test files / 5 PBT files | 8 contract files | ✅ | ✅ | Biggest typing debt in the repo: 370 strict-mypy errors |
| **Neurobench** | **90%** | Benchmark CRUD and service layer are implemented; backend is real, not stub-only | 22 non-empty Dart files; analyzer clean | 28 test files / 5 PBT files | 6 contract files | ✅ | ✅ | Best current module; `mypy --strict` passes cleanly |
| **Neurosim** | **84%** | Real router/service surface for components, preview, sweep, export, and simulation | 36 non-empty Dart files; analyzer clean | 31 test files / 2 PBT files | 5 contract files | ✅ | ✅ | Close to ready; only 2 strict-mypy errors remain |

**Module-specific backend notes**
- **Neurobench:** `app/routers/benchmarks.py` implements real list/get/create behavior; this is not a `501` placeholder.
- **Neurochip:** the module is broadly real, but `app/routers/akida.py` still raises `HTTPException(status_code=501)` when the Akida SDK is absent.
- **Neurosense:** backend breadth is real, but current branch state is not trustworthy until merge conflicts are resolved.

---

## 5. Priority Work Roadmap

### P0 (Critical)
- Resolve Neurosense merge conflicts in `Neurosense/neurosense/app/routers/devices.py`, `Neurosense/neurosense/app/services/device_manager.py`, `Neurosense/neurosense/tests/test_device_manager.py`, and `Neurosense/neurosense/tests/validate_hardware.py`, then rerun Ruff and strict mypy.
- Stop using archived and dead issue folders for active planning. Canonicalize on **root `issues/` + `docs/unified-dev-pipeline/*/generated-issues/`** only.
- Refresh stale generated CI issues before executing them, starting with Neurohub and Neurosim, so agent work is not driven by outdated assumptions.
- Eliminate syntax blockers first. The current **170 Ruff syntax failures** make all deeper lint metrics less trustworthy.

### P1 (Core Integration)
- Bring shared Flutter packages to zero warnings: `nmtk_ui_core`, `nmtk/neuro_toolkit`, and `neurocnl/frontend`.
- Triage Neurochip strict typing debt into import-availability issues vs. genuine annotation debt; 370 errors are too many for reliable contract enforcement.
- Reduce repo-wide production `print()` usage, starting with runtime services and routers rather than scripts/examples.
- Reconcile root hardware-contract issues with module CDD contract issues so one contract body of work maps to one canonical task.

### P2 (Polish/Quality)
- Remove obsolete `version` keys from compose files that still emit Docker warnings.
- Finish the smaller strict-mypy gaps in `Neuro-Dream-Hand`, `neurocnl`, and `Neurosim`.
- Clean up Ruff import/style debt after syntax blockers are gone.
- Regenerate or prune stale CDD issue text so it reflects current workflow, CI, and contract state.

---
*End of Report*
