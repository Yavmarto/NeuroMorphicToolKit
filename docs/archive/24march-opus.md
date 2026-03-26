# NeuroMorphicToolKit — Opus Status Update (25 March 2026)

## 1. Executive Summary

The NMTK project sits at approximately **~85% POC readiness** — a meaningful improvement from the ~78-80% reported on March 21-24. The earlier reports **understated progress** in several modules: Neurosense, Neurohub, Neurochip, and Neurobench have all grown substantially since the March 21 audit, with test suites and frontend UIs that weren't reflected in the task lists. Docker orchestration and backend healthchecks have been resolved. The unified CDD+PBT pipeline has been designed and partially deployed.

The remaining gaps are: frontend widget wiring (not creation — most widgets exist), CDD contract code delivery, and the Neurohub docker-compose + CI setup. The biggest non-code risk is **task fragmentation** — there are now 4+ overlapping task-tracking systems creating confusion about what's actually done vs. outstanding.

---

## 2. Task Fragmentation Problem (Critical Finding)

There are currently **four separate systems** describing outstanding work:

| System | Location | Tasks |
|--------|----------|-------|
| Root `*-Tasks.md` files | `neurocnl-Tasks.md`, `Neurosim-Tasks.md`, etc. (7 files) | 21 tasks (3 per module) |
| `POC-100-TASKS.md` | Root | 26 tasks across 5 tiers |
| `issues-archive/` folders | Per-submodule (12 directories) | ~95+ archived issue files |
| Unified pipeline `generated-issues/` | `docs/unified-dev-pipeline/*/generated-issues/` | 21 CDD issues (3 per module) |

### Duplicate Tasks Identified

The following tasks appear in **2-3 places simultaneously**:

| Task | Appears In |
|------|-----------|
| Neurochip QuantizationExplorer widget | `Neurochip-Tasks.md #2`, `POC-100-TASKS.md T2-3`, `Neurochip/issues-archive/NC-p4-quantization-explorer.md`, `001-finish-quantization-explorer-widget.md`, `22mar8_neurochip_complete_remaining_frontend_wi.md` |
| Neurosim canvas wiring | `Neurosim-Tasks.md #1`, `POC-100-TASKS.md T2-1`, `Neurosim/issues-archive/001-complete-canvas-interactions.md`, `22mar7_neurosim_wire_canvas_interactions_to_bac.md` |
| Neurosense frontend integration test | `Neurosense-Tasks.md #1`, `POC-100-TASKS.md T2-2`, `Neurosense/issues-archive/22mar3_neurosense_integration_test_frontend_aga.md` |
| Neurosense widget tests | `Neurosense-Tasks.md #2`, `POC-100-TASKS.md T3-1`, `Neurosense/issues-archive/22mar4_add_dart_tests_to_neurosense_frontend.md` |
| Neurohub dashboard frontend | `Neurohub-Tasks.md #2`, `POC-100-TASKS.md T2-4`, `Neurohub/issues-archive/NH-frontend-dashboard.md`, `22mar8_neurohub_build_functional_dashboard_fron.md` |
| Neurohub docker-compose | `POC-100-TASKS.md T1-3`, `Neurohub/issues-archive/22mar7_create_neurohub_docker_compose_yml.md`, `001-create-dockerfile.md` |
| Neurobench real benchmark runner | `Neurobench-Tasks.md #1`, `POC-100-TASKS.md T3-5`, `Neurobench/issues-archive/22mar8_wire_neurobench_real_benchmark_runner.md` |
| Neurochip Dart tests | `POC-100-TASKS.md T3-2`, `Neurochip/issues-archive/22mar9_add_dart_tests_to_neurochip_frontend.md`, `NC-p5-testing.md` |
| Neuro-Dream-Hand logging | `Neuro-Dream-Hand-Tasks.md #1`, already partially tracked in `NMTK-01-setup-to-pyproject.md` |
| Neuro-Dream-Hand mypy strict | `Neuro-Dream-Hand-Tasks.md #2`, `002-enable-mypy-strict.md` |

**Recommendation:** Consolidate into one canonical `issues/` folder per submodule. Archive the rest. The new `issues/` folder (created below) is that canonical source.

---

## 3. POC-100-TASKS.md Relevance Assessment

| Tier | Status | Verdict |
|------|--------|---------|
| **TIER 1** — Docker fixes (T1-1 to T1-4) | Reported as done on 24 March | **Archive** — confirmed resolved |
| **TIER 1** — Docker validation (T1-5) | Root `docker-compose.yml` exists with 7+ services, healthchecks | **Still relevant** — needs real validation run |
| **TIER 1** — Launcher E2E test (T1-6) | Active issue exists at `nmtk/neuro_toolkit/issues/001-end-to-end-launcher-test.md` | **Still relevant** — not yet done |
| **TIER 2** — Frontend integration (T2-1 to T2-5) | Core work still outstanding | **Highly relevant** — this is the main remaining work |
| **TIER 3** — Testing (T3-1 to T3-6) | No test files added since report | **Still relevant** |
| **TIER 4** — Packaging (T4-1 to T4-5) | Installers untested | **Relevant but lower priority** |
| **TIER 5** — Documentation (T5-1 to T5-4) | Some docs exist but incomplete | **Partially relevant** |

**Overall:** POC-100-TASKS.md is still the most accurate high-level task list. The per-module `*-Tasks.md` files are a subset of it. Both can be kept but the per-submodule `issues/` folders should be the canonical work queue.

---

## 4. Unified CDD+PBT Pipeline Assessment

### What's Working
- **Workflows installed**: All 5 pipeline workflows (`contract-verification.yml`, `cdd-pbt-module-ci.yml`, `auto-merge-agents.yml`, `ci-failure-fix-agent.yml`, `issue-sync.yml`) are in `.github/workflows/`
- **Scripts exist**: 6 scripts totaling 663 LOC, all appear to be real implementations
- **module.json manifests**: All 7 modules have valid declarative manifests
- **Issues published**: `.issue-state.json` in neurocnl shows issues 55-57 were pushed to GitHub
- **Generated issues**: 3 issues generated per module (21 total) — all properly topologically sorted

### What's NOT Working (README vs. Reality)

| README Claims | Actual State |
|--------------|-------------|
| `neurocnl/contracts/` with 3 Python files (18 invariants) | **Directory does not exist** — contracts are described in module.json as targets, not delivered code |
| `neurocnl/properties/test_physics_properties.py` (12 property tests) | **File does not exist** |
| `neuro-dream-hand/contracts/hardware_contracts.py` | **Does not exist** |
| `neuro-dream-hand/properties/test_hitl_properties.py` (11 tests) | **Does not exist** |
| `neurosim/contracts/design_contracts.py` | **Does not exist** |
| `neurosense/contracts/signal_contracts.py` + `properties/` | **Does not exist** |
| `neurochip/contracts/` + `properties/` | **Does not exist** |
| `neurobench/contracts/benchmark_contracts.py` | **Does not exist** |
| `neurohub/contracts/orchestration_contracts.py` | **Does not exist** |
| AGENTS.md for all 7 modules | Only neurocnl + neuro-dream-hand have AGENTS.md |
| GUARDRAILS.md for all 7 modules | Only neurocnl + neuro-dream-hand have GUARDRAILS.md |

### Verdict

The unified pipeline is a **well-designed declarative control plane** — the architecture is intentionally issue-driven: `module.json` declares what *should* exist, scripts generate GitHub issues as work orders, and agents/humans implement the actual code. The infrastructure (workflows, scripts, manifests, issue templates) is solid and functional.

**However, the README is misleading.** It describes a directory tree with `contracts/` and `properties/` Python files as if they already exist. In reality, these are *targets to be created*. The actual structure uses `generated-issues/` with markdown work orders instead.

**Immediate fix needed:** Update the README directory tree and Module Migration State table to reflect reality — show `generated-issues/` instead of `contracts/` and `properties/`, and clarify that the contract code is the *output* of the pipeline, not a pre-existing input.

The generated issues (CDD-001 through CDD-003 per module) correctly describe the work needed. Issues for neurocnl have been published to GitHub (issues #55-57). Other modules' issues exist as local previews in `generated-issues/` and need publishing via `publish_github_issues.py --execute`.

### Additional Pipeline Gaps

- **AGENTS.md / GUARDRAILS.md**: Only neurocnl and neuro-dream-hand have these. The other 5 modules have `null` in module.json — these need to be created as agents are deployed to each module.
- **Neurohub has no CI at all**: This is flagged as CRITICAL in neurohub's module.json (NH-CDD-003). It's the only module without any `ci.yml`.
- **Old automation workflows still active**: `auto-merge-jules-prs.yml` and `ci-failure-fix.yml` coexist with the newer unified `auto-merge-agents.yml` and `ci-failure-fix-agent.yml`. The old ones should be deprecated.

---

## 5. Per-Module Status (25 March)

> **Note:** The 24march-Jules.md report (March 24) described some issues that have since been resolved or were inaccurate. Corrections are marked with [CORRECTION].

### neurocnl (95%+ ready)
- Backend: Mature, 1 import fix needed in analysis router. 5 sub-routers for prosthetic suite.
- Frontend: ~8-12K LOC, 47 Dart files, 5 screens, 13 providers, 10+ widgets. Comprehensive.
- Tests: **16 test files** — excellent coverage
- Remaining: Fix `analyze_quantization` import, expand edge-case invariants
- CDD pipeline: Issues published to GitHub (#55-57), contracts/properties to be created

### Neurosim (~75% ready)
- Backend: Functional FastAPI with 8 routers (components, templates, validation, generation, preview, sweep, export, projects)
- Frontend: ~4-6K LOC, 18 Dart files. `network_canvas.dart` is complete (~300+ LOC) with drag/drop, transformation, edge/node management
- Tests: **17 test files** — excellent coverage including property-based tests
- Remaining: Wire canvas to API (may be closer to done than reported), add integration tests
- CDD pipeline: Issues generated, no contracts yet

### Neurosense (~80% ready) [CORRECTION: higher than previously reported]
- Backend: Functional with 10 routers (devices, presets, stream, encoding, recording, sessions, quality, export, nir)
- Frontend: ~4.5-6K LOC, 16 Dart files, 5 providers (device, quality, recording, sessions, stream), 7 widgets
- Tests: **15 test files** [CORRECTION: not 0 — includes property tests, contract tests, service tests, integration tests]
- Remaining: Verify frontend-backend integration, add Dart widget tests, verify OpenBCI hardware
- CDD pipeline: Issues generated, no contracts yet

### Neurohub (~65% ready) [CORRECTION: higher than previously reported]
- Backend: **Starts successfully** [CORRECTION: DB imports are properly wired with SQLAlchemy ORM]. 10 routers (activity, assets, config, dashboard, health, members, milestones, notes, projects, workflows)
- Frontend: ~5.5-7.5K LOC, 21 Dart files, 8 screens, 11 widgets [CORRECTION: much larger than "238 LOC scaffolds" reported earlier — significant growth since March 21]
- Tests: **15 test files** [CORRECTION: not 0 — includes property tests, service tests, endpoint tests]
- Docker: **docker-compose.yml still missing** (only remaining Docker gap)
- Remaining: Build out dashboard widget functionality, wire activity feed, create docker-compose.yml
- CDD pipeline: Issues generated, **no ci.yml workflow** (only module without CI)

### Neurochip (~70% ready) [CORRECTION: higher than previously reported]
- Backend: Functional with 8 routers (analysis, deployments, estimation, export, faults, quantization, serial, targets)
- Frontend: ~4-5.5K LOC, 11 Dart files, 4 screens, 9 widgets. Widgets exist for quantization_explorer, constraint_report, firmware_generator, flash_progress, etc. [CORRECTION: widgets exist but may need wiring/completion, not entirely missing]
- Tests: **13 test files** [CORRECTION: not 0 — covers constraint_analyzer, deployment_store, fault_runner, generators, quantizer, etc.]
- Remaining: Verify frontend model imports, complete widget wiring to backend, add Dart tests
- CDD pipeline: Issues generated, no contracts yet

### Neurobench (~60% ready) [CORRECTION: higher than previously reported]
- Backend: Functional with 8 routers + CLI module. Well-structured service layer (benchmark_loader, runner, comparator, sweepers, report_generator, result_store)
- Frontend: ~5.5-7K LOC, 23 Dart files, 4 screens, 13 widgets, 2 providers [CORRECTION: substantially larger than "164 LOC scaffolds" — significant growth]
- Tests: **14 test files** — including property-based and contract tests
- Remaining: Wire real benchmark execution (replace mock data), verify frontend wiring
- CDD pipeline: Issues generated, no contracts yet

### Neuro-Dream-Hand (~93% ready) [CORRECTION: higher than previously reported]
- Library: Essentially complete. 5 core modules, 8 hardware modules, 4 learning modules, 2 analytics modules, 8 experiment runners
- Code quality: **Already uses `logging.getLogger()` throughout** [CORRECTION: 62 occurrences of proper logging across experiments — the `print()` issue from the March 24 report appears to be resolved]. Type annotations present.
- Tests: Existing test suite
- Remaining: Verify strict mypy compliance, verify Teensy firmware integration
- CDD pipeline: Issues published, contracts/properties to be created

### neuro_toolkit / nmtk Launcher (~80% ready)
- Architecture: Well-designed with abstract `ProcessRunner` base class + `DefaultProcessRunner` implementation
- Frontend: ~3-4K LOC, 11 Dart files, 3 screens, 3 providers, services
- Tests: Minimal test coverage despite solid code
- Remaining: E2E launcher test (active issue), expand test coverage, installer validation

---

## 6. Complete Task Accounting (25 March)

All tasks from every source (POC-100-TASKS.md, *-Tasks.md files, CDD pipeline, and this audit) have been deduplicated and placed into canonical `issues/` folders. This is the single source of truth.

### Tasks Already Done (Archived / No Longer Relevant)

| Task | Source | Status |
|------|--------|--------|
| T1-1: Fix Neurochip Dockerfile | POC-100-TASKS.md | ✅ Done March 24 |
| T1-2: Fix Neurobench Dockerfile | POC-100-TASKS.md | ✅ Done March 24 |
| T1-3: Create Neurohub docker-compose | POC-100-TASKS.md | ⚠️ Partially — Dockerfile exists, compose still needed (Neurohub/issues/001) |
| T1-4: Fix Neurosense docker-compose | POC-100-TASKS.md | ✅ Done March 24 |
| T5-1: Create SETUP_GUIDE.md | POC-100-TASKS.md | ✅ Done |
| NDH print→logging | Neuro-Dream-Hand-Tasks.md | ✅ Already done (62 logging occurrences found) |
| Neurohub DB imports fix | Neurohub-Tasks.md | ✅ Backend starts fine (SQLAlchemy wired correctly) |

### Active Issue Counts Per Module

| Module | issues/ | Key Priorities |
|--------|---------|---------------|
| **neurocnl** | 5 issues | Fix import (P1), edge-case invariants, 3× CDD |
| **Neurosim** | 7 issues | Wire canvas (P1), integration tests, mypy, 3× CDD, agents/guardrails |
| **Neurosense** | 7 issues | Verify integration (P1), Dart tests, OpenBCI, 3× CDD, agents/guardrails |
| **Neurohub** | 9 issues | Docker-compose (P0), CI workflow (P0), dashboard (P1), activity feed, Dart tests, 3× CDD, agents/guardrails |
| **Neurochip** | 7 issues | Model imports (P1), widget wiring (P1), Dart tests, 3× CDD, agents/guardrails |
| **Neurobench** | 6 issues | Real benchmarks (P1), mypy, frontend UI, frontend wiring, CDD, agents/guardrails |
| **Neuro-Dream-Hand** | 5 issues | Strict mypy, Teensy firmware, 3× CDD |
| **nmtk** | 5 issues | E2E test (P1), test coverage, 3× installer validation |
| **Root (cross-cutting)** | 10 issues | Docker-compose validation (P1), pipeline README fix (P1), dev-setup, pre-commit, docs, workflow cleanup, CDD publishing |
| **TOTAL** | **61 issues** | |

### POC-100-TASKS.md Disposition

Every task from POC-100-TASKS.md is now accounted for:

| POC Task | Disposition |
|----------|------------|
| T1-1, T1-2, T1-4 | ✅ DONE — archived |
| T1-3 | → Neurohub/issues/001-create-docker-compose.md |
| T1-5 | → issues/001-validate-root-docker-compose.md |
| T1-6 | → nmtk/neuro_toolkit/issues/001-end-to-end-launcher-test.md |
| T2-1 | → Neurosim/issues/001-wire-canvas-to-api.md |
| T2-2 | → Neurosense/issues/001-verify-frontend-backend-integration.md |
| T2-3 | → Neurochip/issues/001 + 002 (model imports + widget wiring) |
| T2-4 | → Neurohub/issues/003-build-dashboard-widgets.md |
| T2-5 | → issues/007-add-demo-screenshots.md |
| T3-1 | → Neurosense/issues/002-add-dart-widget-tests.md |
| T3-2 | → Neurochip/issues/003-add-dart-tests.md |
| T3-3 | → Neurohub/issues/005-add-dart-tests.md |
| T3-4 | → nmtk/neuro_toolkit/issues/002-expand-test-coverage.md |
| T3-5 | → Neurobench/issues/001-implement-real-benchmark-execution.md |
| T3-6 | → Neurosim/issues/002-python-integration-tests.md |
| T4-1 | → nmtk/neuro_toolkit/issues/003-validate-macos-dmg-installer.md |
| T4-2 | → nmtk/neuro_toolkit/issues/004-validate-linux-appimage.md |
| T4-3 | → nmtk/neuro_toolkit/issues/005-fix-windows-installer-scope.md |
| T4-4 | → issues/002-create-dev-setup-script.md |
| T4-5 | → issues/003-add-root-precommit-hooks.md |
| T5-1 | ✅ DONE |
| T5-2 | → issues/004-update-readme-architecture.md |
| T5-3 | → issues/005-create-contributing-md.md |
| T5-4 | → issues/006-create-architecture-md.md |

---

## 7. Recommended Execution Order

### Phase 1: Unblock (1-2 days)
1. Neurohub/issues/001 — Create docker-compose.yml (P0, 30 min)
2. Neurohub/issues/002 — Create CI workflow (P0, 1 day)
3. issues/008 — Fix pipeline README (P1, 1 hour)
4. Neurochip/issues/001 — Fix frontend model imports (P1, 1 day)

### Phase 2: Core Integration (1-2 weeks)
5. Neurosim/issues/001 — Wire canvas to API (P1, 2-3 days)
6. Neurohub/issues/003 — Build dashboard widgets (P1, 3-5 days)
7. Neurochip/issues/002 — Complete widget wiring (P1, 2-3 days)
8. Neurosense/issues/001 — Verify frontend-backend integration (P1, 1-2 days)
9. Neurobench/issues/001 — Implement real benchmarks (P1, 2-3 days)
10. neurocnl/issues/001 — Fix analysis router import (P1, 30 min)

### Phase 3: Testing & Quality (1 week)
11. nmtk/issues/001 — E2E launcher test (P1)
12. All Dart test issues (Neurosense/002, Neurochip/003, Neurohub/005, nmtk/002)
13. Neurosim/issues/002 — Python integration tests
14. issues/001 — Validate root docker-compose

### Phase 4: CDD Pipeline (1-2 weeks)
15. issues/010 — Publish CDD issues to GitHub for all modules
16. All CDD contract extraction issues (per module)
17. All CDD property test issues (per module)
18. All CDD CI issues (per module)
19. All agents/guardrails creation issues

### Phase 5: Polish & Ship (1 week)
20. issues/009 — Deprecate old workflows
21. Installer validation (nmtk/003, 004, 005)
22. Documentation (issues/004, 005, 006, 007)
23. issues/002 — Dev setup script
24. issues/003 — Root pre-commit hooks

---

## 8. What To Do After All Tasks Are Implemented

Once all 61 issues are resolved, the POC reaches 100% readiness. Here's the roadmap for what comes next:

### 8.1 Immediate (Week of Completion)

1. **Run Full Smoke Test**
   - `docker-compose --profile full up --build`
   - Walk through DEMO_WALKTHROUGH.md end-to-end
   - Verify every module's health endpoint
   - Test the complete user journey: Launch → NeuroCNL → Write Spec → Simulate → Benchmark → Deploy to Chip

2. **Tag Release `v0.1.0-poc`**
   - Git tag on the commit where all issues pass
   - Build installers (macOS DMG, Linux AppImage, Windows setup)
   - Create GitHub Release with changelog

3. **Run CDD Pipeline End-to-End**
   - `python scripts/publish_github_issues.py --execute` for all modules
   - Verify contract-verification.yml triggers on PR
   - Verify auto-merge-agents.yml gates correctly
   - Run `scripts/verify-contracts-local.sh` for all modules

### 8.2 Short-Term (Weeks 1-4 After POC)

4. **Stabilization Sprint**
   - Fix any issues found during smoke testing
   - Monitor CI failure rates — tune flaky tests
   - Run `ruff check --fix` and `mypy --strict` across all modules to reach zero warnings
   - Get `flutter analyze` to zero issues across all frontends

5. **Performance Baseline**
   - Run `scripts/generate-golden-baselines.sh` to capture simulation baselines
   - Set up regression detection in Neurobench
   - Establish latency budgets for each backend endpoint

6. **User Testing**
   - Demo to 3-5 target users (neuroscience researchers, hardware engineers)
   - Collect feedback on UX, workflow gaps, and missing features
   - Create issues from feedback

### 8.3 Medium-Term (Months 1-3)

7. **Hardening for Production**
   - Add authentication to backend APIs
   - Implement persistent storage (replace in-memory stores with PostgreSQL/SQLite)
   - Add rate limiting and input validation
   - Set up centralized logging (ELK/Grafana stack)

8. **Real Hardware Integration**
   - Test Neurosense with physical OpenBCI hardware
   - Test Neuro-Dream-Hand with physical Teensy board
   - Test Neurochip firmware generation → flash → verify cycle
   - Document hardware setup procedures

9. **API Gateway Migration**
   - Replace per-port access (8000-8005) with a single reverse proxy
   - Implement unified auth at gateway level
   - Consider gRPC for inter-service communication

10. **Dependency Unification**
    - Migrate to `uv` or Poetry workspaces for monorepo dependency management
    - Single lockfile, per-module extras
    - Eliminate dependency drift between modules

### 8.4 Long-Term (Months 3-6)

11. **Plugin Architecture**
    - Allow third-party modules to register with the launcher
    - Define module manifest standard for external contributions
    - Build module marketplace in Neurohub

12. **Cloud Deployment**
    - Kubernetes manifests for cloud deployment
    - Multi-user support with tenant isolation
    - Remote simulation execution (GPU cluster for large networks)

13. **Research Publication**
    - Write paper describing the unified neuromorphic development toolkit
    - Benchmark against existing tools (Brian2, NEST, Lava)
    - Open-source release with documentation site

---

## 9. Files Created Alongside This Report (Updated 25 March)

### Per-Submodule `issues/` Folders (Canonical Work Queue)

All tasks from POC-100-TASKS.md, *-Tasks.md files, CDD pipeline, and this audit have been deduplicated and placed in these folders:

| Location | Count |
|----------|-------|
| `neurocnl/issues/` | 5 issues |
| `Neurosim/issues/` | 7 issues |
| `Neurosense/issues/` | 7 issues |
| `Neurohub/issues/` | 9 issues |
| `Neurochip/issues/` | 7 issues |
| `Neurobench/issues/` | 6 issues (3 pre-existing + 3 new) |
| `Neuro-Dream-Hand/issues/` | 5 issues |
| `nmtk/neuro_toolkit/issues/` | 5 issues (1 pre-existing + 4 new) |
| `issues/` (root, cross-cutting) | 10 issues |
| **Total** | **61 issues** |

Each issue file includes: clear problem statement, acceptance criteria, priority, effort estimate, labels, and references to archived predecessors.

### What Can Be Archived Now

The following root-level files are now **fully absorbed** into the issues/ folders and can be moved to a root `issues-archive/` if desired:

- `POC-100-TASKS.md` — all 26 tasks mapped to specific issues
- `neurocnl-Tasks.md` — absorbed into neurocnl/issues/
- `Neurosim-Tasks.md` — absorbed into Neurosim/issues/
- `Neurosense-Tasks.md` — absorbed into Neurosense/issues/
- `Neurohub-Tasks.md` — absorbed into Neurohub/issues/
- `Neurochip-Tasks.md` — absorbed into Neurochip/issues/
- `Neurobench-Tasks.md` — absorbed into Neurobench/issues/
- `Neuro-Dream-Hand-Tasks.md` — absorbed into Neuro-Dream-Hand/issues/

Keep `24march-Jules.md` and `24march-opus.md` as historical records.
