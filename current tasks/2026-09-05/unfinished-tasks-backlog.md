# Unfinished Tasks Backlog

**Date:** 2026-09-05  
**Origin:** Consolidated backlog of open and deferred tasks identified from current tasks between 2026-08-28 and 2026-09-05.

---

## 1. Large-File Refactoring (17 Files > 1,000 Lines)

Source and prompt specifications: [`current tasks/2026-09-04/refactor-large-files-prompts.md`](file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/current%20tasks/2026-09-04/refactor-large-files-prompts.md) and line count baseline in [`current tasks/2026-08-25/files_over_1000_lines.txt`](file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/current%20tasks/2026-08-25/files_over_1000_lines.txt). Prompt 1 was completed on 2026-09-04; Prompts 2 through 6 remain open.

### Prompt 2: NeuroCNL Notebook Codegen Cluster (4 files, 7,721 lines)
- **Target Files:**
  - `neurocnl/backend/app/routers/notebook.py` (1,341 lines)
  - `neurocnl/backend/tests/test_notebook_generate_v2.py` (3,685 lines)
  - `neurocnl/backend/tests/test_notebook_codegen.py` (1,544 lines)
  - `neurocnl/backend/app/services/dataset_cache.py` (1,155 lines)
- **Scope:** Extract codegen/assembly logic out of `notebook.py` into `backend/app/services/notebook_assembly.py`. Split `dataset_cache.py` into cache mechanics and dataset artifacts. Split the test files to mirror the modularized code. Preserve compatibility re-exports.
- **Verification:** Run `pytest neurocnl/backend/tests/` and keep green; `ruff check` and `mypy` clean.

### Prompt 3: Launcher Control Integration Test Suite (5 files, 7,759 lines) — ✅ DONE 2026-09-06 (CEL-37, commit `c6df77b2`)
- **Target Files:**
  - `tests/launcher_control/test_launcher_deployment.py` (2,219 lines)
  - `tests/launcher_control/test_launcher_bundle_akida_provisioning.py` (1,822 lines)
  - `tests/launcher_control/test_launcher_hardware_settings.py` (1,492 lines)
  - `tests/launcher_control/test_launcher_lifecycle_doctor_cli.py` (1,152 lines)
  - `tests/launcher_control/test_launcher_pynq_provisioning.py` (1,074 lines)
- **Scope:** Move repeated setup/mocking boilerplate into `tests/launcher_control/base.py` or a shared helper module. Split remaining oversized suites by sub-domain.
- **Verification:** Run `pytest tests/launcher_control/`; `ruff check` and `mypy` clean.
- **Outcome:** All 5 files split by sub-domain into 21 files (largest 589 lines); all still import `LauncherControlServiceTestBase` from `base.py`. 350 tests pass (unchanged), ruff clean on all changed files, no new mypy findings (same pre-existing error set).

### Prompt 4: NeuroCNL `nir_cnl` Front-End (2 files, 2,183 lines)
- **Target Files:**
  - `neurocnl/neurocnl/nir_cnl/parser.py` (1,146 lines)
  - `neurocnl/neurocnl/tests/nir_native_cnl/test_compiler_weight_init.py` (1,037 lines)
- **Scope:** Relocate overlapping parsing/diagnostic utilities from `parser.py` into existing sibling modules (`token_cursor.py`, `grammar_tables.py`, etc.). Split `test_compiler_weight_init.py` by weight-init strategy or concern.
- **Verification:** Run `pytest neurocnl/neurocnl/tests/nir_native_cnl/`; `ruff check` and `mypy` clean.

### Prompt 5: Independent NIR Interop Suites (2 files, 2,129 lines)
- **Target Files:**
  - `neurocnl/neurocnl/runtime/test_nir_support.py` (1,124 lines): Split by simulator backend (`test_nir_support_brian2.py`, `test_nir_support_lava.py`, etc.).
  - `neurocnl/backend/tests/test_nir_graph_serializer.py` (1,005 lines): Evaluate splitting by NIR-to-canvas vs canvas-to-NIR directions.
- **Verification:** `pytest` on both test suites; keep tests green.

### Prompt 6: Standalone Files (4 files)
- **Target Files:**
  - `neurocnl/neurocnl/planner.py` (1,038 lines): Split by planning phase (topology analysis vs backend-capability matching vs planner public API).
  - `Neurochip/neurochip/app/services/akida_model_jobs.py` (1,212 lines): Split job lifecycle state machine vs artifact packaging.
  - `Neurochip/neurochip/tests/test_pynq_backend.py` (1,137 lines): Split by collaborator (core, worker, simulator).
  - `nmtk/neuro_toolkit/lib/screens/backend_setup.dart` (1,492 lines): Extract multi-step UI sections (connection form, credentials, progress, health repair) into `lib/screens/backend_setup/`.
- **Verification:** Module `pytest` and `flutter test nmtk/neuro_toolkit/test/screens/backend_setup_test.dart`.

---

## 2. Python Major Refactor Stages

Source specification: [`current tasks/2026-08-31/python-major-refactor-remaining-stages.md`](file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/current%20tasks/2026-08-31/python-major-refactor-remaining-stages.md) (Stages 2, 3, 4, 5, 6 closed).

### Stage 1: Trustworthy Baseline Snapshot (Not Started)
- **Scope:**
  - Record current Ruff, formatting, Mypy, and Pytest results across all modules in one dated snapshot document.
  - Snapshot OpenAPI schemas and launcher-control JSON responses for regression diffs.
  - Perform an exhaustive check of `.github/workflows/ci.yml` to ensure no jobs swallow errors via `continue-on-error`.

### Stage 7: Remaining Product Python (Partial)
- **Remaining Gap:** Router thinning in Neurochip.
  - `Neurochip/neurochip/app/routers/pynq.py` (901 lines)
  - `Neurochip/neurochip/app/routers/akida.py` (747 lines)
- **Action:** Extract business logic into underlying services to make routes transport-only (request validation -> service call -> response mapping).

### Stage 8: Quality Gates (Partial)
- **Architecture Decision Record (ADR):** Draft ADR defining "one authoritative owner per database/job/artifact" across services.
- **Pyupgrade Cleanup:** Apply 18 automated pyupgrade findings in `Neurohub/` (16× `datetime.UTC` replacement, 2× `StrEnum`).

---

## 3. Codebase Cleanup Deferred Items & Test Debt

Source reports: [`current tasks/2026-09-02/cleanup-backlog.md`](file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/current%20tasks/2026-09-02/cleanup-backlog.md), [`current tasks/2026-09-02/cleanup-verification.md`](file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/current%20tasks/2026-09-02/cleanup-verification.md), and [`current tasks/2026-09-02/cel-18-toolchain-repair-report.md`](file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/current%20tasks/2026-09-02/cel-18-toolchain-repair-report.md).

### Strict Mypy Typing Across 6 Modules
- **Context:** During the CEL-3 cleanup sprint, only `Neurosense` was brought to 0 strict errors (gated in CI). The remaining 6 modules were deferred:
  - `neurocnl` (~2,320 errors)
  - `Neurochip` (~487 errors)
  - `Neurohub` (~177 errors)
  - `Neurobench` (~86 errors)
  - `suite_api` (~63 errors)
  - `workers` (~114 errors)

### Pre-Existing Test Failure Remediation
- **Neurohub Pydantic v2 Validation:** 15 test failures in `neurohub/tests/test_all_endpoints.py` and `test_assets_router.py` caused by `SharedAsset` `metadata` dict vs object validation.
- **NeuroCNL NIR 1.0.8 API Drift:** 116 test failures in `neurocnl/` caused by NIR version drift (e.g. `LIF.__init__(input_type=...)`).
- **Suite API Starlette Router Path:** 2 test failures in `suite_api/tests` related to Starlette 1.x `_IncludedRouter` lacking `.path`.
- **Launcher Control macOS Dependencies:** 5 failures caused by missing `sshpass` binary on macOS, and 2 CORS transport header bug failures.

### Real Host CLI Verification
- Source: [`current tasks/2026-09-04/CEL-23-cli-app-parity.md`](file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/current%20tasks/2026-09-04/CEL-23-cli-app-parity.md)
- **Scope:** Execute live `neuro login` and `neuro backend connect` on target host `moosebun2@192.168.2.90` with real user credentials to complete end-to-end sign-off.
