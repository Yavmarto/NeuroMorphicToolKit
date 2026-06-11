# Frontend Remediation Plan — All Frontends

**Date:** 11 June 2026
**Mode:** Plan only (read-only analysis). No code changes performed.
**Scope:** All six frontends (NDH Python shell + NDH core, nmtk_ui_core, Neurobench, Neurosense, Neurohub) plus a new contract-sync phase.
**Tone:** Balanced — fix what breaks, resolve design-system drift, add a contract-sync phase. Skip cosmetic/optional.

---

## Open Decisions (resolved in this plan)

| # | Decision | Resolution |
|---|---|---|
| 1 | **Neurobench `runBenchmark` API** | **Add** `Future<BenchmarkResult> runBenchmark(...)` to `ApiClient` posting to `/api/neurobench/benchmarks/{id}/run`. Keep the screen; it was authored but the method was never wired. Re-verify the Python route in `Neurobench/neurobench/api/` accepts the same `InputSpec` + `ScoringConfig` shape as `BenchmarkRunRequest` on the Dart side; if the route shape diverges, align via the contract-sync phase (Phase 7). |
| 2 | **Neurosense codegen adoption** | **Path A — adopt `@freezed`.** Migrate all 6 state classes + 5 model files to `@freezed` and the 6 providers to `@riverpod` codegen in the same change. Justification: pubspec already declares the deps (they are being used as markers but generate no code), so the migration consumes the already-paid cost; `@freezed` gives us `==`/`hashCode`, `copyWith`, and JSON serialization for free; `@riverpod` codegen removes the `StateNotifier` boilerplate and matches the pattern Neurobench (Riverpod 3) and Neurohub (Riverpod 2 with codegen) already use. |
| 3 | **Contract sync strategy** | **Path A — Pydantic → Dart codegen** using `datamodel-code-generator` with `--input-file-type pydantic --output-model-type dart`. Output goes to a new `nmtk_module_contracts_gen/` sibling Dart package that depends on `nmtk_module_contracts`. Add a `scripts/sync_dart_contracts.py` wrapper that runs the generator and writes a `.last_sync.json` fingerprint; CI fails on drift. |
| 4 | **NDH large-file decomposition (mujoco_env.py, runner.py)** | **Defer to a follow-up PR.** Reason: each is well-tested today; the blast radius of splitting a 1000-line file with 6+ importers is high and orthogonal to the broken-build + design-system work this plan is focused on. Add a follow-up plan file in the same `tasks/` directory. |

---

## Phase 0 — Triage & Baselines (30 min, no code changes)

**Goal:** Lock the baseline so we can verify the plan against it.

| Task | File / Scope | Output |
|---|---|---|
| Capture pre-flight `git status` + branch | `git status`, `git log --oneline -5` | Pinned commit |
| Snapshot both broken web builds | `Neurobench/frontend/build_error.txt`, `Neurohub/frontend/build_error.txt` | Already captured |
| Snapshot ruff + dart-analyze baseline | run on each module | Baseline output to `docs/audits/frontend-baseline-<date>.txt` |
| Snapshot `material_icons_audit_test` pass counts | each frontend | Baseline in plan file |
| Snapshot integration test status | `Neurobench/integration_test/e2e_test.dart` (broken imports), `Neurohub/integration_test/app_test.dart` (broken imports) | Confirm both excluded from CI |

**Acceptance:** All four frontends have a recorded baseline; broken-build states confirmed.

---

## Phase 1 — Unblock the Two Web Builds (HIGHEST PRIORITY)

**Goal:** Restore `flutter build web` for Neurobench and Neurohub. These block production deploys.

### 1A. Neurobench — fix the `MetricDiff` + missing-method chain

Files (all under `Neurobench/frontend/lib/`):
- `models/result.dart` — `MetricDiff` constructor currently has `this.pValue` parameter but the fields are `pValueTtest` and `pValueWilcoxon`. The constructor and `fromJson` are mutually incompatible. **Fix:** drop the `pValue` named parameter from the constructor and add a derived getter `double? get pValue => pValueTtest ?? pValueWilcoxon;`. Update `fromJson` to pass `pValueTtest`/`pValueWilcoxon` correctly.
- `widgets/metric_diff_table.dart:95,97` — references `metric.pValue`. After the constructor fix, the getter exposes the field. Verify.
- `services/api_client.dart` — add `Future<BenchmarkResult> runBenchmark({required String benchmarkId, required BenchmarkRunDraft draft})` posting to `/api/neurobench/benchmarks/{benchmarkId}/run` with `InputSpec` + `ScoringConfig` serialized. Throws `HttpApiException`/`TimeoutApiException`/`MalformedResponseException` per existing pattern.
- `screens/benchmark_screen.dart:31` — the `apiClient.runBenchmark(...)` call stays, now correctly resolved.

### 1B. Neurohub — fix `shared_preferences` resolution

- `services/auth_service.dart` imports `package:shared_preferences/shared_preferences.dart` but `shared_preferences` is not in `pubspec.yaml`. **Fix:** add `shared_preferences: ^2.2.2` to `pubspec.yaml` dependencies; run `flutter pub get`.
- Wasm dry-run failure: `Cannot extract a file path from a org-dartlang-untranslatable-uri URI`. **Fix:** add `--no-wasm-dry-run` to the `flutter build web` invocation in `Dockerfile`; mirror the same flag in any CI script that calls `flutter build web`.

### 1C. Integration test imports

Both `integration_test/e2e_test.dart` (Neurobench) and `integration_test/app_test.dart` (Neurohub) use `package:frontend/...` or import non-existent widgets. **Fix:** rewrite imports to `package:neurobench_frontend/...` / `package:neurohub/...`; remove dead `project_card.dart`/`activity_feed.dart` references; remove the `integration_test/**` and `test/**` exclusion in `analysis_options.yaml:9-10`.

**Acceptance:** `flutter build web --no-wasm-dry-run` succeeds for both Neurobench and Neurohub from a clean checkout; integration tests compile; `dart analyze` on the `test/` directories succeeds.

**Verification:**
- `cd Neurobench/frontend && flutter build web`
- `cd Neurohub/frontend && flutter build web`
- `cd Neurobench/frontend && flutter test`
- `cd Neurohub/frontend && flutter test`

---

## Phase 2 — Neurosense Data-Class Correctness

**Goal:** Eliminate the `==`/`hashCode` absence and the codegen drift.

### 2A. Adopt `@freezed` + `@riverpod` codegen (per Decision 2)

State classes needing work (under `Neurosense/frontend/lib/`):
- `providers/device_provider.dart` — `DeviceState`, `DeviceNotifier` → `@freezed` + `@riverpod`
- `providers/recording_provider.dart` — `RecordingState`, `RecordingNotifier` → `@freezed` + `@riverpod`
- `providers/sessions_provider.dart` — `SessionsState`, `SessionsNotifier` → `@freezed` + `@riverpod`
- `providers/stream_provider.dart` — `StreamState`, `SignalBuffer`, `SignalFrame`, `SpikeFrame`, `StreamNotifier` → `@freezed` + `@riverpod` (note: `SignalBuffer` and `SignalFrame` are mutable buffers, migrate only the data classes, keep the buffer logic)
- `providers/quality_provider.dart` — `QualityState`, `QualityNotifier` → `@freezed` + `@riverpod`
- `providers/preset_provider.dart` — `PresetState`, `PresetNotifier` → `@freezed` + `@riverpod`
- `models/device_info.dart` — `DeviceInfo`, `ChannelQuality` → `@freezed`
- `models/session.dart` — `RecordingSession`, `EventMarker` → `@freezed`
- `models/signal_quality.dart` — `SignalQuality` → `@freezed`
- `models/preset.dart` — `AcquisitionPreset`, `FilterConfig`, `EncodingConfig` → `@freezed`

After the migration, delete the manual `copyWith` and the unused `import 'package:freezed_annotation/freezed_annotation.dart'` (it becomes used). Run `dart run build_runner build --delete-conflicting-outputs`.

### 2B. Fix `LiveSignalViewer` double-`Expanded` hazard

`lib/widgets/live_signal_viewer.dart:14-19,187-203` — remove the `expandedHeight` parameter entirely. The widget always uses `Expanded` internally. Update `signal_monitor_screen.dart:55` to drop the `null` argument.

### 2C. Fix nested `ProviderScope`

`lib/app.dart:85-91` — move the override to the root `ProviderScope` in `main.dart`. Pass `workspaceController` as a value into a single override at app start, not in a `build()` method.

**Acceptance:** `dart analyze Neurosense/frontend/` clean; all `expect(state.x, equals(mockValue))` matchers work without instance-identity assumptions; `LiveSignalViewer` is single-mode; `ProviderScope` tree is built once; build_runner outputs committed.

**Verification:** `flutter test test/providers/` passes after migration; `flutter build web` succeeds.

---

## Phase 3 — nmtk_ui_core Hardening (one-PR worth)

**Goal:** Close the design-system gaps that cascade into every frontend.

### 3A. Extract a shared `zetaFallback()` helper
Replace the 5 sites of `try { Zeta.of(context).colors; } catch (_) {}` in `tone.dart`, `info_chip.dart`, `summary_card.dart`, `validation_chip.dart` with a call to a single helper that **catches only the actual Zeta-not-found exception class** (confirm against `zeta_flutter` 1.4.5 source — likely `_ZetaProviderNotFoundException` or whatever the package emits) and surfaces a typed `ZetaColors` or `NmtkShellTokens` fallback.

**File to add:** `nmtk_ui_core/lib/src/zeta_fallback.dart` (and export from `nmtk_ui_core.dart`).

### 3B. Resolve the `NmtkToasts` vs `NmtkSnackBars` duplication
Consolidate into `NmtkSnackBars` (the one using `NmtkShellTokens`). Mark `NmtkToasts` as `@Deprecated('Use NmtkSnackBars instead')` for one minor version, then remove. Update all three downstream frontends (Neurobench, Neurosense, Neurohub) to import from `NmtkSnackBars` only.

### 3C. Remove `lines_longer_than_80_chars` suppression in `desktop_scaffold.dart:1`
The 1,433-line file currently bypasses the lint. Refactor nested widget trees or break the long lines, then remove the suppression. Splitting `desktop_scaffold.dart` into a host file + `desktop_scaffold_top_bar.dart` + `desktop_scaffold_sidebar.dart` is the bigger win (8 private widget classes extracted).

### 3D. Move `lib/neat/dark/` out of production
109 files × ~6,480 lines of hardcoded `Positioned(left: X, top: Y)` with zero tests. **Decision:** keep as design previews but move to `nmtk_ui_core/previews/` (outside `lib/`) and remove from the barrel `nmtk_ui_core.dart` if currently exported. Confirm not currently exported.

### 3E. Misc cleanups
- Remove `.toDouble()` after `.clamp(0.0, ...)` in `loading_screen.dart:207,257,300`
- Remove unused `dart:async` import in `pipeline_stepper.dart:1`
- Fix circular barrel import: `top_app_bar.dart:2` should import `shell_models.dart` + `shell_tokens.dart` directly, not the barrel

**Acceptance:** `dart analyze nmtk_ui_core/` clean with no file-level suppressions; `flutter test` passes; `NmtkToasts` migration complete in all three consumers; `neat/dark/` no longer ships in `lib/`.

---

## Phase 4 — Zeta Design-System Sweep (12 sites)

**Goal:** Close all `ZETA-MIGRATION-TODO` and `ZETA-MIGRATION-EXEMPT` markers, migrate raw Material widgets to Nmtk equivalents.

### 4A. `ZETA-MIGRATION-TODO` sites (12 — resolve each)

| File:Line | Issue | Fix |
|---|---|---|
| `Neurosense/replay_controls.dart:274-275` | `border`/`isDense` dropped on a Zeta input | Add `borderType: ZetaWidgetBorderType.sharp` on `ZetaTextInput`; for `isDense`, wrap in `NmtkInputDecorator` with reduced vertical padding |
| `Neurosense/support_level_badge.dart:18` | `degradedColor` vs `warningColor` semantics | Use `NmtkStatusBadge` (semantic palette per `CODING_STYLE_GUIDE.md`) — pick `warningColor` consistently for "degraded" |
| `Neurohub/asset_library_screen.dart:301-303` | `isDense`/`contentPadding`/`border` dropped | Migrate to `NmtkSelect` |
| `Neurohub/new_project_screen.dart:143,155,156` | `border`/`maxLines` dropped | `ZetaTextInput(maxLines:)` is supported; add it back; add `borderType` |
| `Neurohub/share_model_screen.dart:154,163,164` | same as above | same |
| `Neurobench/report_builder.dart:80` | "border has no ZetaTextInput equivalent" | `ZetaTextInput(borderType:)` — comment is stale, restore border |
| `Neurobench/robustness_curve_chart.dart:155` | degraded vs warning color | Use `NmtkShellTokens.warningColor` |
| `Neurobench/target_comparison_grid.dart:316` | same | same |

### 4B. Migrate raw Material widgets to Nmtk equivalents

| File | Widget | Replace with |
|---|---|---|
| `Neurosense/live_signal_viewer.dart:265-291` | `_StatusChip` (private) | `NmtkStatusBadge` |
| `Neurosense/support_level_badge.dart:30-38` | `Chip` | `NmtkStatusBadge` |
| `Neurohub/asset_card.dart:34-38` | raw `Chip` | `NmtkStatusBadge(label: asset.type, tone: NmtkTone.info)` |
| `Neurobench/benchmark_run_form.dart:107-111` | `Chip` | `NmtkChip` (or remove) |
| `Neurobench/report_builder.dart:91` | `DropdownButtonFormField` | `NmtkSelect` |
| `Neurobench/baseline_selector.dart:45-51` | `DropdownButtonFormField` | `NmtkSelect` |
| `Neurohub/settings_screen.dart` | raw `AppBar` | `NmtkTopAppBar` |
| `Neurohub/live_test_screen.dart` | raw `AppBar` | `NmtkTopAppBar` |

### 4C. Harden the `material_icons_audit_test` governance

Each module already has a governance test counting `ZETA-MIGRATION-EXEMPT` markers. Add a parallel assertion that **forbids any new `ZETA-MIGRATION-TODO` comment** (the only TODO marker left after this phase). Update the count expectation: TODOs = 0, EXEMPTs ≤ current count (don't grow).

**Acceptance:** `git grep -E "ZETA-MIGRATION-TODO" -- '*.dart'` returns 0 results across all frontends; all migrated widgets pass their existing widget tests; `material_icons_audit_test` fails if anyone re-adds a TODO.

**Verification:** `cd <frontend> && flutter test test/governance/material_icons_audit_test.dart`.

---

## Phase 5 — Neuro-Dream-Hand Shell Surface + Core Cleanup

**Goal:** Make the NDH Python surface error-safe and dedupe the constant blocks.

### 5A. Narrow `except Exception` in shell surfaces

| File:Line | Current | Narrow to |
|---|---|---|
| `neurodreamhand/shell/adapter.py:224` (decode) | `except Exception` | `except (ValueError, KeyError, json.JSONDecodeError, binascii.Error, TypeError, UnicodeDecodeError)` |
| `neurodreamhand/shell/hitl_surface.py:254` (send_guarded_grip) | `except Exception` | `except (IOError, OSError, TypeError, ValueError, RuntimeError)` — the bridge's contract |

Both `except` sites are flagged as catching `KeyboardInterrupt`/`SystemExit`. The narrowed tuple excludes those.

### 5B. Centralize physics constants

The values `BASE_GRIP = 0.80`, `KP = 15.0`, `KD = 1.0`, `N_NEURONS = 100`, `NENGO_DT = 0.002`, `TAU_FAST = 0.02`, `TAU_SLOW = 0.1`, `PERTURB_TIME = 1.0`, `PERTURB_DUR = 0.3`, `DURATION_S = 3.0`, `ERROR_SCALE` are duplicated across:
- `neurodreamhand/experiments/drop_test.py`
- `neurodreamhand/experiments/runner.py`
- `neurodreamhand/learning/ocl_engine.py`

**Action:** add a new module `neurodreamhand/core/_constants.py` exporting a `@dataclass(frozen=True) class SimDefaults` (or simple `Final` module-level constants). Update all three callers to `from neurodreamhand.core._constants import SimDefaults`. **Critical:** `ERROR_SCALE = 5.0` in `ocl_engine.py:38` vs `ERROR_SCALE = 1.0` in `runner.py:47` — the new shared module picks **`1.0` (runner value)** and adds a separate `SimDefaults.ocl_error_scale = 5.0` if the OCL override is intentional. Add a regression test asserting the two values are distinct and that callers pass the correct one.

### 5C. Mid-body imports

| File:Line | Import | Action |
|---|---|---|
| `hardware/loihi_exporter.py:116` | `import typing` mid-method | Move to top |
| `hardware/quantization.py:58` | `from typing import cast` in function | Move to top |
| `hardware/crossbar_exporter.py:109,176` | `import h5py`, `import typing` in methods | Move to top |
| `experiments/statistical_validation.py:149,151` | `import matplotlib`, `from pathlib import Path` in function | Move to top |

### 5D. Docstring style alignment

`experiments/tracking.py:25-30,51-55,67-69` and `experiments/config.py:67-69` use Google-style (`Args:`). Convert to NumPy-style (`Parameters\n----------\n`) to match the rest of NDH.

### 5E. Magic number extraction

- `adapter.py:35` — `2**31 - 1.0` → `_MAX_SEED: Final[float] = 2**31 - 1.0`
- `adapter.py:130` — `"0.6.0"` version fallback → read from `pyproject.toml` via `tomllib` (Python 3.11+), or cache `_current_version()` at module load.

### 5F. Large-file decomposition — DEFERRED to follow-up
- `core/mujoco_env.py` (1012 lines) — split `Observation`, `PinchBridge`, `TripodBridge`, MJCF XML strings
- `experiments/runner.py` (787 lines) — extract `multi_day` pipeline from CLI sweep runner

Tracked separately. See `tasks/12-jun-ndh-large-file-split.md` (file to be created in a follow-up session).

**Acceptance:** `pytest Neuro-Dream-Hand/tests/test_neurodreamhand/` passes with the same coverage; `python3 -m mypy --strict neurodreamhand/core/ neurodreamhand/experiments/ neurodreamhand/hardware/ neurodreamhand/learning/ neurodreamhand/contracts/ neurodreamhand/shell/` clean (currently shell/ is excluded by AGENTS.md — recommend adding it for stricter safety, but is OPTIONAL); ruff clean.

---

## Phase 6 — Neurohub Stub Resolution

**Goal:** Either implement or replace the 6 non-functional stub widgets.

### 6A. The 6 stubs (all under `Neurohub/frontend/lib/widgets/`)

| File | Status | Action |
|---|---|---|
| `config_panel.dart` | `Container(child: Text('ConfigPanel'))` | Replace with `NmtkEmptyState(title: 'Configuration', subtitle: 'Config UI ships in a follow-up')` |
| `workflow_step_card.dart` | stub | `NmtkEmptyState` |
| `member_manager.dart` | stub | `NmtkEmptyState` |
| `note_editor.dart` | stub | `NmtkEmptyState` |
| `bundle_export_dialog.dart` | stub | `NmtkEmptyState` in a dialog wrapper |
| `milestone_timeline.dart` | stub | `NmtkEmptyState` |
| `live_test_dashboard.dart` | stub | `NmtkEmptyState` |

Then add `const ConfigPanel({super.key})` constructors and `super.key` to satisfy the `use_key_in_widget_constructors` lint.

### 6B. Fix `auth_service.dart`

`lib/services/auth_service.dart:11-58` — add `.timeout(Duration(seconds: 10))` to all 4 methods; wrap body in `try/catch`; rethrow as `HttpApiException` from `nmtk_module_contracts` (already used elsewhere in this module). Validate response shape with `as String? ?? throw MalformedResponseException('access_token')`.

### 6C. Fix `_launchModule` stub

`lib/screens/project_detail_screen.dart:174-179` — restore the `launchUrl(...)` call (it's already there but commented out). Add proper error handling for `PlatformException` and `CouldNotLaunchException`.

### 6D. Standardize import paths

`lib/providers/riverpod_providers.dart:3-5` and `lib/providers/asset_library_provider.dart:3-4` use `package:neurohub/...`; screens use relative paths. **Standardize on relative paths** for monorepo development (no need to fix the package name on rename). Apply project-wide via `dart fix --apply`.

**Acceptance:** All 7 stub widgets render `NmtkEmptyState` (visible to end user, with an "empty state" pattern); `auth_service` has timeouts and structured errors; `_launchModule` actually launches; `dart analyze` clean; no `use_key_in_widget_constructors` violations.

---

## Phase 7 — Contract Sync (new phase, per Decision 3)

**Goal:** Establish a Pydantic → Dart codegen pipeline so the data contracts have a single source of truth.

### 7A. Strategy

**Path A — `datamodel-code-generator` Pydantic → Dart.** Add a new sibling Dart package `nmtk_module_contracts_gen/` that depends on `nmtk_module_contracts` and holds the generated Dart models. Wrap the codegen in `scripts/sync_dart_contracts.py` with a `.last_sync.json` fingerprint; CI fails on drift.

Tool: `datamodel-code-generator --input <python-pydantic-dir> --input-file-type pydantic --output <dart-lib-dir> --output-model-type dart --use-double-quotes --use-equality --target-python-version 3.11`.

### 7B. First 4 model pairs to sync

| Python (Pydantic) | Dart (generated) |
|---|---|
| `Neurosense/contracts/device_contracts.py` → `DeviceInfo`, `DeviceConfig`, `ConnectionTransition` | `nmtk_module_contracts_gen/lib/src/neurosense/device.dart` |
| `Neurosense/contracts/session_contracts.py` → `RecordingSession`, `EventMarker` | `nmtk_module_contracts_gen/lib/src/neurosense/session.dart` |
| `Neurosense/contracts/preset_contracts.py` → `AcquisitionPreset`, `FilterConfig`, `EncodingConfig` | `nmtk_module_contracts_gen/lib/src/neurosense/preset.dart` |
| `Neurohub/contracts/project_contracts.py` → `Project`, `ProjectMember`, `ProjectLinks` | `nmtk_module_contracts_gen/lib/src/neurohub/project.dart` |

### 7C. Wire the consumers

- `Neurosense/frontend/pubspec.yaml` — add `nmtk_module_contracts_gen: path: ../../nmtk_module_contracts_gen`; replace local `lib/models/device_info.dart`, `session.dart`, `preset.dart` with `import 'package:nmtk_module_contracts_gen/src/neurosense/device.dart'`. Keep the local re-exports if existing widget imports use relative paths — adjust as needed.
- `Neurohub/frontend/pubspec.yaml` — same; replace `lib/models/project.dart` with the generated equivalent.
- The generated models override the hand-rolled ones; the old hand-rolled files are deleted once the consumers migrate.

### 7D. Specific known divergences to fix during sync

- `Neurosense DeviceInfo` JSON uses `serial_port`, `sampling_rate_hz` (snake_case) but Dart field names are `serialPort`, `samplingRateHz` (camelCase). The hand-rolled `fromJson` mapping is the drift hazard. **Codegen fixes this** by reading the Pydantic `Field(alias=...)` and emitting the snake-case JSON keys directly.
- `Neurosense DeviceInfo.batteryPct` is required if `connected: true` per the Python validator, but Dart doesn't enforce. **Fix during sync:** add a `PostValidation` getter in the generated Dart (or a thin wrapper) that throws if `connected == true && batteryPct == null`.
- `Neurohub Project.name` is non-empty in Python via `field_validator`. Dart `fromJson` does not enforce. **Fix during sync:** same approach — wrapper that throws on empty name.

### 7E. CI integration

Add a `scripts/sync_dart_contracts.py` wrapper that:
1. Runs `datamodel-code-generator` against the four Python contract files.
2. Writes the output to `nmtk_module_contracts_gen/lib/src/`.
3. Computes a SHA-256 of the generated tree; compares to `nmtk_module_contracts_gen/.last_sync.json`.
4. Exits non-zero on drift.

Wire into `scripts/run_launcher_guardrails.sh` and the root `tests/integration/test_cross_module.py`.

**Acceptance:** Each of the 4 model pairs has generated Dart code committed; CI fails if Pydantic schemas change without re-running the generator; the three specific known divergences above are addressed.

**Verification:** `python3 scripts/sync_dart_contracts.py --check` exits 0; `flutter test` passes in both Neurosense and Neurohub frontends after consumer migration; `dart analyze` clean.

---

## Phase 8 — Cross-Frontend Polish (LOW priority, optional)

These are all marked LOW and can be deferred if scope pressure arises.

| # | Frontend | File | Change |
|---|---|---|---|
| L1 | Neurobench | `workbench_shell.dart` | Use `NmtkDesktopScaffold` instead of raw `Scaffold` (per AGENTS.md) |
| L2 | Neurobench | `comparison_workspace.dart:89,247,256` | Add `if (!context.mounted) return;` guards |
| L3 | Neurosense | `replay_controls.dart`, `signal_quality_bar.dart` | Replace hardcoded `EdgeInsets`/`SizedBox` with `NmtkShellTokens` spacing tokens (4 sites) |
| L4 | Neurosense | `app.dart:124` | Replace `MediaQuery.of(context).size.width < 800` with `< NmtkShellTokens.normalBreakpoint` |
| L5 | Neurosense | `_RecordingTimer` in `recording_controls.dart:206-250` | Replace 60fps `Ticker` with `Timer.periodic(Duration(seconds: 1))` |
| L6 | Neurohub | `lib/services/api_service.dart` (257 lines) | Extract `_getList<T>(Uri, T fromJson)` helper to dedupe 4 list endpoints |
| L7 | Neurohub | `analysis_options.yaml:16-17` | Re-enable `use_key_in_widget_constructors`, `avoid_unnecessary_containers` (after Phase 6 fixes) |
| L8 | Neurohub | `README.md`, `web/index.html:21` | Replace generic Flutter template text with NeuroHub-specific |
| L9 | Neurohub | `integration_test/app_test.dart:8-9` | Remove dead imports of `project_card.dart`/`activity_feed.dart` |
| L10 | nmtk_ui_core | `shell_tokens.dart:202-343` | Consider freezed/macro codegen for the 141-line `copyWith`/`lerp` boilerplate (Dart macro stabilization pending) |
| L11 | nmtk_ui_core | `desktop_scaffold.dart:1050,1384` | Replace manual `_hovered` setState with `InkWell`/`MouseRegion` only |
| L12 | nDH | `core/mujoco_env.py` (1012L) | Split ABC, concrete bridges, MJCF XML strings, Observation type — **deferred to follow-up** |
| L13 | nDH | `experiments/runner.py` (787L) | Extract multi-day pipeline from CLI sweep runner — **deferred to follow-up** |
| L14 | nDH | `experiments/runner.py:178` + `learning/ocl_engine.py:120` | `error_scale` parameter passes through but is undocumented; add docstring + `Final` |
| L15 | Neurobench | `lib/widgets/trend_chart.dart:32-34` | Either implement with `fl_chart` or remove |

---

## Phase 9 — Verification Sweep

**Goal:** Confirm the changes are green across the entire suite.

### Local checks per module

**NDH** (`Neuro-Dream-Hand/`):
- `python3 -m pytest tests/test_neurodreamhand/` — must be green
- `python3 -m mypy --strict neurodreamhand/core/ neurodreamhand/experiments/ neurodreamhand/hardware/ neurodreamhand/learning/ neurodreamhand/contracts/`
- `ruff check --fix . && ruff format .`
- `python3 -m pytest tests/test_neurodreamhand/test_shell_*.py` — verify Phase 5A narrowings

**nmtk_ui_core**:
- `dart format .`
- `dart fix --apply`
- `flutter test` — must be green
- `dart analyze` — clean

**Neurobench/frontend**:
- `dart fix --apply && dart format .`
- `flutter test` — must be green
- `flutter build web` — must succeed
- `dart analyze` — clean (including test/, integration_test/)

**Neurosense/frontend**:
- `dart fix --apply && dart format .`
- `flutter test` — must be green
- `flutter build web` — must succeed
- `dart analyze` — clean
- `dart run build_runner build --delete-conflicting-outputs` — verify freezed/riverpod codegen succeeds

**Neurohub/frontend**:
- `dart fix --apply && dart format .`
- `flutter test` — must be green
- `flutter build web --no-wasm-dry-run` — must succeed
- `dart analyze` — clean

### Suite-level checks (per AGENTS.md)

- `python3 scripts/launcher_control_service.py --doctor --json` — must report `fatalCount: 0`
- `bash scripts/run_launcher_guardrails.sh --with-integration`
- `python3 -m pytest tests/integration/test_cross_module.py`
- `python3 -m pytest tests/integration/test_teensy_e2e.py` — only if teensy changes
- `python3 scripts/sync_dart_contracts.py --check` — must exit 0 (Phase 7)

### End-to-end visual check

For each frontend, `flutter run -d chrome` and walk the navigation:
- Neurobench: catalog → run form → results table → comparison
- Neurosense: device list → connect → live signal → record
- Neurohub: login → dashboard → project detail → asset library

---

## Phase 10 — Open Brain / Knowledge Update

**Goal:** Capture durable lessons per the AGENTS.md Open Brain directive.

Add to Open Brain (under appropriate category):
- `architecture`: "Flutter frontends must export a public barrel file (`<module>_frontend.dart`); integration tests must import via that barrel, never via `package:frontend/`."
- `architecture`: "Zeta migration is gated by a governance test (`material_icons_audit_test.dart`); new `ZETA-MIGRATION-TODO` comments are forbidden after 2026-Q3 sweep."
- `process`: "When a Pydantic `field_validator` exists on the Python side, the matching Dart `fromJson` must enforce the same constraint — current drift in `DeviceInfo.batteryPct` and `Project.name` are cautionary examples."
- `debugging`: "`flutter build web` failures with `Could not resolve package` are often the result of a deleted/missing pubspec entry, not a Dart-level error — always check pubspec before chasing the import stack."
- `architecture`: "Python `try/except Exception` is a hard no in safety-critical surface code (NDH `shell/`, `hardware/`); narrow to specific exception types and document the contract."

---

## Sequencing & Risk

| Order | Phase | Risk | Notes |
|---|---|---|---|
| 0 | Triage | none | Baselines only |
| 1 | Web builds | medium | Risk of finding additional broken sites; iterate as needed |
| 2 | Neurosense data classes | medium | Freezed migration is invasive but well-bounded |
| 3 | nmtk_ui_core hardening | medium | The deprecation cycle on `NmtkToasts` touches 3 frontends |
| 4 | Zeta sweep | low | All sites identified; mechanical replacements |
| 5 | NDH shell + core | low | Tests exist; mostly mechanical |
| 6 | Neurohub stubs | low | Pure widget replacement |
| 7 | Contract sync | high | New tooling; needs upfront decision (resolved: Path A) |
| 8 | Cross-frontend polish | very low | All marked LOW; defer as needed |
| 9 | Verification | none | Mechanical |
| 10 | Open Brain | none | Documentation |

**Status:** No files have been modified. Plan saved to `tasks/11 june/frontend-remediation-plan.md`. Awaiting approval to begin Phase 0.
