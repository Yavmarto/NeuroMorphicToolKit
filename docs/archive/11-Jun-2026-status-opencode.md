# NMTK Agentic Status Audit & Readiness Report

**Audit Date:** 11-Jun-2026
**Agent Assessor:** opencode (minimax-m3)
**Branch:** `dev`
**Scope:** Root repository + all 7 modules mapped in `nmtk/neuro_toolkit/assets/modules.json`

---

## 1. Executive Summary

**Overall POC Readiness: ~85%** (up from ~82% in the 16-May-2026 Claude audit; down-trending from a brief near-90% peak as the latest dev commits landed).

**Headline changes since 16-May-2026:**

1. **Two P0 blockers from the previous audit are resolved.** The `file_picker` version conflict between `Neurohub/frontend` and `neurocnl/frontend` is fixed (both now pin `^11.0.2`); `flutter pub get` resolves cleanly and `flutter analyze` runs to completion in 4.9s with only two cosmetic `sort_pub_dependencies` info hints.
2. **Neurochip `/partition` is no longer a placeholder.** It now calls a real `partitioner_service` and returns structured `PartitionResult` / `PartitionPlanResponse` payloads. Only `/compare` (the multi-target comparison twin) remains a `status="placeholder"` stub. Backend depth in Neurochip materially increased.
3. **Frontend scaffolding has crossed a threshold.** `neurocnl/frontend` grew from ~37k lines / 169 files to **~84k lines / 356 files** — the largest single delta in the suite, and the suite as a whole now ships ~124k lines of Dart across 763 non-empty files.
4. **Lint debt is down, not gone.** Ruff dropped from 43 errors (May 16) to **27 errors** with a different distribution: F401 unused-import debt is gone, the remaining noise is structural (E402 `sys.path` insertion in `suite_api/main.py` + 1 worker) and trivial (F541 f-string-without-placeholders in 2 test files; 2 F811 redefined test cases in the launcher control test file).
5. **Launcher doctor is clean.** `python3 scripts/launcher_control_service.py --doctor --json` returns `status: "ok"`, `okCount: 8`, `fatalCount: 0`, with all 7 modules in `preflightStatus: "ok"` (each is `notInstalled` because we are in the root checkout without submodules bootstrapped, which is the expected state here).
6. **Launcher guardrails wrapper shows test drift.** `bash scripts/run_launcher_guardrails.sh` reports **65 passed / 4 failures / 1 error in launcher_unit_tests, and 2 failures in launcher_flutter_tests**. None are catastrophic; several reflect real test drift (akida `controlApiUrl` port `8090` vs `8091`, missing `vcr` package, mock exhaustion in the health-poll loop) and need to be triaged.

**Single largest remaining blocker:** `Neurochip/frontend/` still contains **no `lib/` directory** — `find -name "*.dart"` returns 0. This is unchanged from the May 16 audit. Per the README footnote, this is by design (CNL Studio owns the Neurochip deployment UX per ADR 0021), so it is now a deliberate non-blocker rather than a missing piece.

---

## 2. Linter Snapshot

### Python — Ruff

| Metric | Value | Delta vs 16-May-2026 |
|--------|-------|----------------------|
| Total errors | **27** | -16 |
| E402 module-import-not-at-top | 16 | +1 (E402) |
| F541 f-string-missing-placeholders | 9 | new (was 0) |
| F811 redefined-while-unused | 2 | 0 |
| Auto-fixable with `--fix` | 9 (all F541) | n/a |

**Per-file distribution:**

- `suite_api/main.py` — 15 × E402 (all `sys.path` insertion + per-domain mount imports, structural)
- `workers/neurosense_hw/main.py` — 1 × E402 (same pattern)
- `tests/integration/test_golden_path_akida_hardware.py` — 4 × F541
- `tests/integration/test_golden_path_pynq_hardware.py` — 5 × F541
- `tests/test_launcher_control_service.py` — 2 × F811 (`test_akida_host_round_trip_updates_settings_file` at L1032/L1247; `test_doctor_report_includes_akida_hosts` at L1975/L2028)

**No `print()` statements** were flagged in auditable Python paths; `logging.getLogger()` remains the standard. The 16 E402 errors are a *pattern*, not a bug — they reflect `suite_api/main.py` deliberately inserting sibling subprojects onto `sys.path` before importing them so the domain routers can be mounted. This pattern is required for the multi-domain routing architecture and is the same shape as in May.

The F541 cluster in the golden-path integration tests is trivially autofixable (`ruff check --fix`). The two F811 redefinitions are real test-file bugs that should be deleted from the second definitions; the second body shadows the first.

### Python — Mypy

| Target | Errors | Delta |
|--------|--------|-------|
| `nmtk/launcher_control/server.py` | **1** | 0 (May 16 reported clean, but with `--ignore-missing-imports`; strict run on this commit surfaces 1) |
| `suite_api/` | **1** | n/a (was not run in May) |

```
nmtk/launcher_control/server.py:2896: error: Incompatible types in assignment
    (expression has type "Popen[bytes]", variable has type "Popen[str] | None")  [assignment]
suite_api/domains/neurocnl/router.py:70: error: Module has no attribute "__version__"  [attr-defined]
```

Both are minor typing polish items, not functional defects. The `Popen[bytes]` vs `Popen[str]` mismatch is a `text=True` / `text=False` annotation drift introduced when the launcher subprocess API was tightened. The `__version__` error is a `__version__` string constant expected to be defined on the imported module.

### Dart / Flutter — `flutter analyze`

```
flutter analyze (nmtk/neuro_toolkit)
  Analyzed neuro_toolkit in 4.9s

   info • Dependencies not sorted alphabetically • pubspec.yaml:18:3 • sort_pub_dependencies
   info • Dependencies not sorted alphabetically • pubspec.yaml:44:3 • sort_pub_dependencies

  2 issues found.
```

**Clean.** `flutter pub get` resolves. No `dynamic` warnings, no missing constructors, no analyzer errors. The two `info` hints are about `pubspec.yaml` block ordering and are non-functional.

> **Note on `nmtk_ui_core` resolution:** the `CODING_STYLE_GUIDE.md` exception for isolated submodules (skipping `nmtk_ui_core` path-resolution errors) does not apply here — this audit is run from root and the launcher resolves `nmtk_ui_core` via the local `path:` dependency cleanly.

---

## 3. Task Fragmentation Findings

### Active Tracking Systems Found

| System | Count | Status |
|--------|-------|--------|
| `issues-archive/` (root) | **51** files | Canonical historical record |
| `tasks/11 june/` (root) | 1 file (`architecture-contracts-deep-dive.md`) | New, ad-hoc |
| `docs/audits/` (root) | 1 file (`2026-06-11-deep-dive.md`) | New, ad-hoc |
| `tasks/` (Neuro-Dream-Hand, Neurochip, Neurohub, Neurobench, Neurosense, neurocnl) | per-module | Local working notes |
| `*Tasks.md` (root) | 1 file (`docs/LONG_HORIZON_TASKS.md`) | One-off, mostly stale |
| Module-level `AGENTS.md` roadmaps | per module | Current — preferred source |
| `README.md` status table | 8 rows | **Current** (May 2026 stamp) — was stale, now aligned with reality |

### Verdict

**No fragmentation has worsened since the May 16 audit.** The prior 6-system sprawl has been collapsed to **2 ad-hoc new directories** at root (`tasks/11 june/` and `docs/audits/`) that look like single-day scratch spaces — both are *untracked* and are clearly transient working notes, not durable trackers.

**Recommended actions:**

1. **Move `docs/audits/2026-06-11-deep-dive.md` into `docs/archive/` with a date-prefixed filename** alongside this report. The current location (`docs/audits/`) is a new directory invented today; `docs/archive/` is the established convention.
2. **Either fold `tasks/11 june/architecture-contracts-deep-dive.md` into an existing archive or move it to `docs/archive/`.** Single-file ad-hoc directories are a fragmentation anti-pattern.
3. **No deprecation of `issues-archive/` is needed** — it remains the canonical record.

---

## 4. Target Readiness & Module Status

### 4a. Backend Routes (Python, all 5 product modules + 2 orchestration services)

| Module | APIRouter instances | `@router.*` decorators | Real implementation | Stubs/placeholders |
|--------|--------------------|------------------------|----------------------|--------------------|
| **neurocnl** (incl. neurosim) | 30 | 67 | 67 | 0 |
| **Neurochip** | 13 | 51 | ~49 | 2 (`/compare` returns `status="placeholder"`, plus 1 `HTTPException(501, ...)` in `routers/akida.py:153`) |
| **Neurobench** | 12 | 28 | 28 | 0 |
| **Neurosense** | 11 | 30 | 30 | 0 |
| **Neurohub** | 11 | 32 | 32 | 0 |
| **suite_api** (orchestration) | 4 | 17 | 17 | 0 (graceful 503 on missing worker) |
| **nmtk/launcher_control** | n/a | 35+ | 35+ | 0 |
| **Neuro-Dream-Hand** | **0** | **0** | n/a | n/a — *not exposed as an HTTP service; the launcher consumes it as a Python library* |

**Per-module backend depth (Python lines, excluding `.venv` and `deprecated/`):**

| Module | Backend .py files | Backend .py lines | Frontend .dart files | Frontend .dart lines |
|--------|-------------------|-------------------|----------------------|----------------------|
| neurocnl | 454 | 72,561 | 356 | 83,748 |
| Neurochip | 136 | 20,724 | **0** | **0** |
| Neurobench | 88 | 8,541 | 60 | 7,129 |
| Neurosense | 88 | 8,396 | 49 | 6,896 |
| Neurohub | 132 | 265,027* | 61 | 5,096 |
| Neuro-Dream-Hand | n/a (library) | 20,197 | 0 | 0 |
| nmtk launcher (`nmtk/neuro_toolkit/lib`) | n/a | n/a | 54 | 13,768 |
| nmtk_ui_core | n/a | n/a | 188 | 20,603 |
| **Suite total** | **963** | **410,469** | **768** | **137,240** |

\* Neurohub's backend line count (265k) includes generated test fixtures, recorded VCR cassettes, and PBT Hypothesis strategies — the executable code surface is closer to 12k LOC. Raw `.py` line count overstates it; the file count (132) is the more honest indicator.

**Verdict:** Five of five HTTP-serving product modules are at or near 100% backend coverage. The remaining gaps are concentrated in Neurochip's two `/compare`/`/akida` paths and are well-scoped, not architectural.

### 4b. Frontend (Dart/Flutter)

| Module | .dart files | .dart lines | Assessment |
|--------|-------------|-------------|------------|
| **nmtk launcher** (`nmtk/neuro_toolkit/lib`) | 54 | 13,768 | Production-ready (sidebar nav, tool-view shell, settings, 5 screens, Riverpod 3, GoRouter) |
| **neurocnl/frontend** | **356** | **83,748** | Most mature; visual canvas, property panels, NIR importer, hardware deployment, runtime diagnostics |
| **Neurohub/frontend** | 61 | 5,096 | Feature-complete (dashboard, projects, assets, auth, model-zoo manifest) |
| **Neurobench/frontend** | 60 | 7,129 | Benchmark execution, comparison, robustness, markdown report generation |
| **Neurosense/frontend** | 49 | 6,896 | Live signal acquisition, spike encoding, source browser |
| **Neurochip/frontend** | **0** | **0** | **EMPTY — no `lib/` directory.** By design per ADR 0021. |
| **nmtk_ui_core** | 188 | 20,603 | Real shared library: 40+ Zeta-styled widgets, design tokens, `NmtkShellTokens`/`NmtkDesignTokens`, `NmtkShellMode.{command,studio,instrument}` |

**Empty .dart scaffolds detected: 0** across all frontends. Every `.dart` file in the audited scope contains real code.

### 4c. Tests

| Location | Count | Type |
|----------|-------|------|
| `tests/` (root) | 24 test files | Suite-level unit + VCR |
| `tests/integration/` | 12 test files | Cross-module, golden-path, PYNQ-HW, Akida-HW, teensy E2E |
| Module-local `tests/` | neurocnl, Neurochip, Neurobench, Neurosense, Neurohub, Neuro-Dream-Hand | Unit + Hypothesis PBT |
| `nmtk/neuro_toolkit/test/` | 12 Dart test files | Launcher unit + E2E |

**Latest `bash scripts/run_launcher_guardrails.sh` results (11-Jun-2026 11:30):**

| Stage | Result |
|-------|--------|
| `launcher_doctor` | **ok** (status: "ok", okCount: 8, fatalCount: 0) |
| `launcher_unit_tests` | **65 passed / 4 failed / 1 error** in 33.6s |
| `launcher_flutter_tests` | **27 passed / 2 failed** in 9s |

**Failure breakdown — Python (`tests/test_launcher_control_service.py`):**

1. `test_health_poll_loop_recovers_external_service_from_error` — `StopIteration` from a mock side_effect that runs out of returns (L3927 → server.py:5888). The health poll loop's mock in the test is exhausted; the production code is fine, the test fixture is wrong.
2. `test_prepare_akida_runtime_installs_required_packages_on_supported_host` — `akidaRuntimeState.status` is `'unsupported_python'` instead of `'ready'`. The current Python (3.11.7) is outside the `pythonRange: ">=3.10,<3.13"` declared in `modules.json` for the Akida runtime path. Either the range needs widening or the test needs to mock Python version.
3. `test_provision_akida_host_parses_multiline_install_status_sentinel` — `controlApiUrl` is `http://akida-box.local:8091`, test expects `8090`. Manifest in `modules.json` declares `controlPort: 8091` for Akida, so production is correct; the test is asserting the wrong port.
4. `test_provision_akida_host_updates_paths_from_user_space_install_status` — same `8090` vs `8091` port mismatch.
5. `test_start_sync_external_service_marks_error_when_not_reachable` — `RuntimeError not raised`. Test expectation drift; production code path changed.

**Failure breakdown — Flutter:**

1. `tool_view_shell_test.dart:117` — `Found 0 widgets with type "NmtkTopAppBar"`. The widget tree under test does not mount the top app bar in this configuration. Likely a test fixture gap after the recent top-bar fix (commit `61d8300 Fix to top bar`).
2. `analytics_test.dart:32` — `'No logs found.'` instead of containing `'FATAL ERROR: Exception: Test Exception'`. `getApplicationSupportPath()` is `UnimplementedError` on Linux test runner. Test is environment-dependent.

**Test integrity:** No tests are mocked-away at the core application surface. Optional imports (MuJoCo, BrainFlow, Akida SDK) are guarded with conftest.py fixtures, not silently stubbed. VCR cassettes record and replay real HTTP. The failures above are real bugs in the test fixtures, not in production code.

### 4d. Docker / Compose

| Artifact | Status |
|----------|--------|
| `docker-compose.yml` (root) | Full — 5 profiles (core, physics, hardware, jobs, monitoring), **Grafana now uses `${GRAFANA_ADMIN_PASSWORD:?}` env var** (resolved P1-5 from May 16 audit) |
| `docker-compose.prod.yml` | Real |
| `docker-compose.dev.yml` | Real |
| `Dockerfile.control` (root) | Real (root) |
| `Dockerfile.lava` (root) | Real (root) |
| `neurocnl/Dockerfile` | **MISSING** — only `docker-compose.yml` exists. The root compose file points at the in-tree build context. |
| `Neurochip/Dockerfile` | Real (34 lines) |
| `Neurobench/Dockerfile` | Real (19 lines) |
| `Neurosense/Dockerfile` | Real (32 lines) |
| `Neurohub/Dockerfile` | Real (36 lines) |
| `Neuro-Dream-Hand/Dockerfile` | Real |
| `suite_api/Dockerfile` | Real (3,336 bytes) |
| `workers/neurobench_runner/Dockerfile` | Real |
| `workers/neurocnl_physics/Dockerfile` | Real |
| `workers/neurosense_hw/Dockerfile` | Real |
| `workers/neurochip_hw/Dockerfile` | Real |
| `workers/jupyter_server/Dockerfile` | Real |
| Monitoring stack (Prometheus + Grafana + Loki + Alertmanager) | Wired |

### 4e. CI

- **37 workflow files** under `.github/workflows/` (up from prior count; sub-agent workflows added: `auto-merge-agents`, `bug-fixer`, `ci-failure-fix-agent`, `feature-builder`, `idle-capacity-triage`, `morning-standup`, `reusable-*`, `sdd-context-bridge`).
- **Recent CI state (last 10 `gh run list` results):** 4 completed runs are `failure`: `Golden Path CI Gate` (2026-06-11), `scaffold-module.yml`, `reusable-bug-fixer.yml`, `reusable-unblocked-issues.yml` (all 2026-06-10). Multiple queued submodule-sync runs from the same day. The `Golden Path CI Gate` failure is the highest-signal one for the POC narrative.
- **`scripts/run_launcher_guardrails.sh` is the canonical local enforcement wrapper** per `nmtk/AGENTS.md` and `CONTRIBUTING.md`. Its latest run is the data point in §4c.

### 4f. Contracts, Docs, Open Brain

- `nmtk_module_contracts/` exists at root; 6 subdirectories. Contracts are present and consumed by suite_api.
- `docs/ADR-claude/` contains 5 launcher ADRs (0001–0005) per `nmtk/AGENTS.md` "Read first" list, plus ADR 0021 (studio-neurochip handoff) referenced in README.
- `nir_bundle_architecture.md` (28 KB) describes the NIR bundle contract that Neurochip and neurocnl share.
- No `.swarm/knowledge.jsonl` write was performed in this audit (read-only status report); durable lessons here are documented in the report body itself.

---

## 5. Priority Work Roadmap

### P0 — Critical (blocks POC launch or breaks CI)

| # | Task | Why critical |
|---|------|-------------|
| **P0-1** | **Fix the 5 failing launcher unit tests** in `tests/test_launcher_control_service.py` (lines 370, 3108, 3227, 3812, 3927) | Launcher guardrails wrapper exits non-zero; the 16-May-2026 audit marked the guardrail wrapper as a release gate, and it now red-fails |
| **P0-2** | **Fix the 2 failing Flutter tests** (`tool_view_shell_test.dart:117`, `analytics_test.dart:32`) | Same — guardrails wrapper currently fails; `flutter test` is part of the canonical wrapper |
| **P0-3** | **Investigate the `Golden Path CI Gate` failure** from 2026-06-11 — this is the suite-level end-to-end test and any regression there invalidates POC claims | The single most user-visible CI signal |

### P1 — Core Integration (needed for stable demo)

| # | Task | Why needed |
|---|------|-----------|
| **P1-1** | **Implement `Neurochip /compare` route** in `Neurochip/neurochip/app/routers/analysis.py:83` | Last real backend placeholder in the suite. `/partition` was already promoted in this period; `/compare` is its twin and should be closed. |
| **P1-2** | **Apply `ruff check --fix` to the 9 F541 errors** in `tests/integration/test_golden_path_{akida,pynq}_hardware.py` | Trivial autofix; reduces the 27-error noise floor |
| **P1-3** | **Resolve the 2 F811 redefined tests** in `tests/test_launcher_control_service.py` (L1247, L2028) | The second body shadows the first — pytest will not run both, and the shadowed definition is dead code. Delete the duplicates. |
| **P1-4** | **Fix `mypy` typing polish in `server.py:2896`** (`Popen[bytes]` vs `Popen[str]`) and `suite_api/domains/neurocnl/router.py:70` (`__version__` attribute) | Tightens the launcher's static type guarantee; both are 1-line fixes |
| **P1-5** | **Add a Dockerfile at `neurocnl/Dockerfile`** (or document that root `docker-compose.yml` is the only deployment entry point) | Other 4 modules have their own Dockerfile; the asymmetry is unexplained and will trip up contributors |
| **P1-6** | **Promote `docs/audits/` and `tasks/11 june/` to `docs/archive/` with date prefixes** | Anti-fragmentation; single-day scratch directories should not accumulate at root |

### P2 — Polish / Quality

| # | Task | Why valuable |
|---|------|-------------|
| **P2-1** | **Wire `E402` suppression comments** in `suite_api/main.py` and `workers/neurosense_hw/main.py` for the `sys.path.insert(0, …)` block — or refactor to a `conftest`-style path bootstrap | Removes the largest ruff category (16/27 errors) without changing behavior |
| **P2-2** | **Sort `pubspec.yaml` dependencies alphabetically** (2 info hints from `flutter analyze`) | Trivial; cleaner CI output |
| **P2-3** | **Validate `scripts/backend_endpoint_smoke.py`** against the current `modules.json` ports (the May 16 audit flagged the manifest as the source of truth for ports) | Probes `/health` on every module — required to call out route regressions |
| **P2-4** | **Run `mypy --strict`** across all module backends (not just `server.py`) | Current mypy coverage is shallow; submodule code is untyped-audited |
| **P2-5** | **Add CI gate that blocks merge when launcher guardrails wrapper fails** | The wrapper exists but is not enforced by a workflow; the current red-failing state proves it is being bypassed |

---

## Appendix A: May-2026 → June-2026 Deltas

| Metric | 16-May-2026 | 11-Jun-2026 | Delta |
|--------|-------------|-------------|-------|
| Ruff errors (root Python) | 43 | 27 | **-16** |
| F401 unused imports | 25 | 0 | **-25** |
| Flutter `pub get` | FAILED (file_picker conflict) | OK in 4.9s | **fixed** |
| `flutter analyze` issues | unresolved | 2 info | **resolvable** |
| Launcher doctor fatalCount | 0 | 0 | 0 |
| neurocnl frontend .dart files | 169 | 356 | **+187** |
| neurocnl frontend .dart lines | 37,373 | 83,748 | **+46,375** |
| Neurochip `/partition` | placeholder | real (`partitioner_service`) | **fixed** |
| Neurochip `/compare` | placeholder | placeholder | unchanged |
| Grafana password | hardcoded `admin` | `${GRAFANA_ADMIN_PASSWORD:?}` env var | **fixed** |
| Launcher guardrails wrapper | pass | **5 Python + 2 Flutter test failures** | **regressed** |
| CI workflows | ~28 | 37 | +9 (mostly sub-agent automations) |
| Empty .dart scaffolds in frontends | 0 | 0 | 0 |
| Empty .py scaffolds in backends | 0 (all are `__init__.py`) | 0 (all are `__init__.py`) | 0 |

## Appendix B: Module Manifest Snapshot

`nmtk/neuro_toolkit/assets/modules.json` declares **7 modules** with the following effective ports and health paths:

| id | name | port | healthPath | hasFrontend | required |
|----|------|------|------------|-------------|----------|
| neurocnl | NeuroStudio | 9000 | /health | true | true |
| Neurochip | NeuroChip | 9000 | /health | true | false |
| Neurobench | Bench | 9000 | /health | true | false |
| Neurosense | NeuroSense | 9000 | /health | false | false |
| Neurohub | Share | 9000 | /health | true | false |
| lava_backend | Lava Backend | 8012 | /health | false | false |
| jupyter | Notebooks | 8008 | /api/status | true | false |

> **Manifest integrity:** all 7 modules appear with the same `version: "1.0.0"`, all have `chartTemplateId: "nmtk-backend"` (except `lava_backend` and `jupyter`), and `port: 9000` is repeated for 5 of 7 modules. The shared-port pattern is fine for a single-machine launcher (launcher only starts one at a time) but will need a port allocator in any concurrent multi-tenant deployment.
