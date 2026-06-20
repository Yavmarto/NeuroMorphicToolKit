# Open Items — Consolidated Plan
**Date:** 20 June 2026  
**Source plans:** `tasks/11 june/frontend-remediation-plan.md`, `tasks/11 june/architecture-contracts-deep-dive.md`, `tasks/18_june_deployment_plan.md`  
**Excluded:** `neurocnl/docs/tasks/12-june/canvas-drawing-model.md` — left as-is (substantially implemented).

---

## Completed Since 11 June (do not re-do)

| Item | Where |
|---|---|
| `MetricDiff` constructor — `pValueTtest`/`pValueWilcoxon` split | `Neurobench/frontend/lib/models/result.dart` |
| `metric_diff_table.dart` — references `.pValueTtest` directly | `Neurobench/frontend/lib/widgets/` |
| Neurohub `shared_preferences: ^2.5.5` | `Neurohub/frontend/pubspec.yaml` |
| ZETA-MIGRATION-TODO sweep (0 results) | All frontends |
| Linux file loader — `FilePickerLinux.registerWith()` + `picked_save_path_writer_io.dart` | `neurocnl/frontend/lib/services/` |
| `docker-compose.prod.yml` ghcr.io images | repo root |
| `make deploy-prod` / `make dev-sync` Makefile targets | `Makefile` |
| Canvas tab model + pipeline canvas widgets | `neurocnl/frontend/` |

---

## Wave A — Quick Wins (low risk, bounded scope)

### A1. `MetricDiff.pValue` derived getter (Neurobench)

**File:** `Neurobench/frontend/lib/models/result.dart`

Add a derived getter so any future callers can use `.pValue` as a convenience:

```dart
double? get pValue => pValueTtest ?? pValueWilcoxon;
```

No callers are broken today (`metric_diff_table.dart` already uses `.pValueTtest` directly), but the plan spec'd this getter and it prevents future confusion.

**Acceptance:** `dart analyze Neurobench/frontend/` clean; `flutter test` passes.

---

### A2. `runBenchmark()` wired in Neurobench `ApiClient`

**File:** `Neurobench/frontend/lib/services/api_client.dart`

Add the missing method (plan Phase 1A, Decision 1):

```dart
Future<BenchmarkResult> runBenchmark({
  required String benchmarkId,
  required BenchmarkRunDraft draft,
}) async {
  // POST /api/neurobench/benchmarks/{benchmarkId}/run
  // body: { input_spec: ..., scoring_config: ... }
  // throws HttpApiException / TimeoutApiException / MalformedResponseException per existing pattern
}
```

Verify that `Neurobench/neurobench/api/` Python route accepts the same `InputSpec` + `ScoringConfig` shape as `BenchmarkRunRequest` on the Dart side. If shapes diverge, align both sides in this same change.

**Acceptance:** `flutter test` passes; `dart analyze` clean; Python route returns 200 on a mock payload in `pytest`.

---

### A3. Architecture drift — dead legacy config fields (suite_api)

**Source:** Architecture deep-dive, Drift #5.

**File:** `suite_api/config.py`

The following fields are dead after ADR 0018 (unified backend). Confirm zero live readers, then remove:

```python
# Remove these — all point to pre-consolidation per-module ports:
neurocnl_url: str = "http://localhost:8000"
neurosim_url: str = "http://localhost:8000"
neurochip_url: str = "http://localhost:8002"
neurobench_url: str = "http://localhost:8003"
neurosense_url: str = "http://localhost:8004"
neurohub_url: str = "http://localhost:8005"
```

Step 1: `grep -rn "settings\.neurocnl_url\|settings\.neurosim_url\|settings\.neurochip_url\|settings\.neurobench_url\|settings\.neurosense_url\|settings\.neurohub_url" suite_api/ tests/ scripts/` — must return 0 hits before deleting.  
Step 2: Remove the fields.  
Step 3: Add a one-line comment in `config.py`: `# Per-module URLs removed in ADR 0018 — all routes are in-process on port 9000.`

**Acceptance:** `ruff check --fix . && ruff format .` clean; `python3 -m pytest suite_api/tests/` passes; `python3 scripts/launcher_control_service.py --doctor --json` → `fatalCount: 0`.

---

### A4. Architecture drift — ADR 0001 missing

**Source:** Architecture deep-dive, Drift #7.

**File to create:** `docs/ADR-claude/0001-module-manifest-system.md`

Either restore the stub (recording the "one JSON manifest drives everything" decision) or update `nmtk/AGENTS.md` to drop the broken reference. Preferred: write a minimal stub ADR so the reference is valid.

Stub content should cover: what `modules.json` is, why it exists as the single source of truth, and that `nmtk/neuro_toolkit/lib/models/module.dart` mirrors it 1:1.

**Acceptance:** `nmtk/AGENTS.md` reference resolves to a real file; no other AGENTS.md references broken.

---

### A5. Linux file picker — add missing test

**Source:** Linux file loader investigation (20 June).

**File:** `neurocnl/frontend/test/services/file_picker_native_file_backend_test.dart`

Add the missing Linux registration test alongside the existing macOS and Windows tests:

```dart
test('FilePickerDialogGateway installs Linux desktop implementation', () {
  FilePickerDialogGateway.debugEnsureRegisteredForTests(
    TargetPlatform.linux,
  );

  expect(FilePickerPlatform.instance, isA<FilePickerLinux>());
  FilePickerDialogGateway.debugResetRegistrationForTests();
});
```

**Acceptance:** `flutter test test/services/file_picker_native_file_backend_test.dart` passes (all existing tests still green + new Linux test green).

---

## Wave B — Medium Scope (1–2 PRs each)

### B1. Neurohub stub widgets — replace with `NmtkEmptyState`

**Source:** Frontend plan, Phase 6.

All 7 files under `Neurohub/frontend/lib/widgets/` are still raw `Container(child: Text(...))` stubs:

| File | Replace with |
|---|---|
| `config_panel.dart` | `NmtkEmptyState(title: 'Configuration', subtitle: 'Config UI ships in a follow-up')` |
| `workflow_step_card.dart` | `NmtkEmptyState` |
| `member_manager.dart` | `NmtkEmptyState` |
| `note_editor.dart` | `NmtkEmptyState` |
| `bundle_export_dialog.dart` | `NmtkEmptyState` in a dialog wrapper |
| `milestone_timeline.dart` | `NmtkEmptyState` |
| `live_test_dashboard.dart` | `NmtkEmptyState` |

Add `const SomeWidget({super.key})` constructors to each to satisfy `use_key_in_widget_constructors`.

Also while here:

**B1a. `auth_service.dart` timeouts** (`lib/services/auth_service.dart:11-58`):  
Add `.timeout(Duration(seconds: 10))` to all 4 methods; wrap body in `try/catch`; rethrow as `HttpApiException`; validate `access_token` field.

**B1b. `_launchModule` stub** (`lib/screens/project_detail_screen.dart:174-179`):  
Uncomment the `launchUrl(...)` call; add `PlatformException` + `CouldNotLaunchException` error handling.

**B1c. Import path standardisation:**  
`lib/providers/riverpod_providers.dart` and `asset_library_provider.dart` use `package:neurohub/...`; standardise on relative paths via `dart fix --apply`.

**Acceptance:** All 7 stubs render `NmtkEmptyState`; `auth_service` has timeouts + structured errors; `_launchModule` launches; `dart analyze` clean; `use_key_in_widget_constructors` lint passes; `flutter build web --no-wasm-dry-run` succeeds.

---

### B2. Architecture drift — `test_cross_module.py` port rewrite

**Source:** Architecture deep-dive, Drift #2.

**File:** `tests/integration/test_cross_module.py`

Current state: defaults to `http://neurocnl:8000`, `http://neurochip:8000`, etc. — the old per-module port world. ADR 0018 superseded this; these silently skip via `_request_or_skip`.

Rewrite to:
- Read a single `SUITE_API_URL` env var (default `http://localhost:9000`)
- Assert actual monolith shapes: `/api/neurocnl/parse` → 200, `/api/neurosim/...`, etc.
- Cover the in-process pipeline round-trip: parse → validate → simulate → export (no localhost hops)
- Drop or replace `NEUROSIM_URL=http://neurocnl:8000` line (confirm it was an alias, not a separate service)

**Gate:** `python3 -m pytest tests/integration/test_cross_module.py tests/integration/test_teensy_e2e.py` must pass after the rewrite.

---

### B3. Architecture drift — `composeProfile` divergence

**Source:** Architecture deep-dive, Drift #6.

`DeploymentCapability.composeProfile` is parsed in `nmtk/neuro_toolkit/lib/models/backend_deployment.dart` (lines 282, 323) but no manifest entry ever sets it, and Docker worker profiles are not currently gated on it.

**Decision needed (pick one):**
1. **Delete** `composeProfile` from `DeploymentCapability` + Dart parsing + update ADR 0001 (simpler, honest).
2. **Wire it** — gate the launcher-control compose invocation on `composeProfile` and add `"composeProfile": "hardware"` entries to the relevant manifest workers, + update ADR 0001.

The plan (architecture-contracts-deep-dive.md) left this unresolved. **Recommended: Option 1** (delete) unless the launcher team wants gated profile support. Either way, update ADR 0001 to record the decision.

**Acceptance:** `dart analyze nmtk/` clean; `bash scripts/run_launcher_guardrails.sh` passes; `launcher doctor → fatalCount: 0`.

---

### B4. nmtk_ui_core hardening

**Source:** Frontend plan, Phase 3.

#### B4a. `zetaFallback()` helper
Replace the 5 sites of `try { Zeta.of(context).colors; } catch (_) {}` in `tone.dart`, `info_chip.dart`, `summary_card.dart`, `validation_chip.dart` with a single helper that catches only the actual Zeta-not-found exception class.

**New file:** `nmtk_ui_core/lib/src/zeta_fallback.dart` (export from `nmtk_ui_core.dart`).

#### B4b. `NmtkToasts` → `NmtkSnackBars` deprecation
Mark `NmtkToasts` as `@Deprecated('Use NmtkSnackBars instead')`. Update all three downstream frontends (Neurobench, Neurosense, Neurohub) to import `NmtkSnackBars` only.

#### B4c. Misc cleanups
- Remove `.toDouble()` after `.clamp(0.0, ...)` in `loading_screen.dart:207,257,300`
- Remove unused `dart:async` import in `pipeline_stepper.dart:1`
- Fix circular barrel import: `top_app_bar.dart:2` → import `shell_models.dart` + `shell_tokens.dart` directly

> Note: `desktop_scaffold.dart` split (B4d from Phase 3C) and `neat/dark/` move (Phase 3D) are deferred — high blast radius, no tests broken today. Track separately if needed.

**Acceptance:** `dart analyze nmtk_ui_core/` clean with no file-level suppressions; `flutter test` passes; `NmtkToasts` migration complete in all three consumers.

---

## Wave C — Larger Scope (plan before executing)

### C1. Neurosense `@freezed` + `@riverpod` codegen migration

**Source:** Frontend plan, Phase 2.

State classes and models to migrate (all under `Neurosense/frontend/lib/`):

**Providers → `@freezed` state + `@riverpod` codegen:**
- `providers/device_provider.dart` — `DeviceState`, `DeviceNotifier`
- `providers/recording_provider.dart` — `RecordingState`, `RecordingNotifier`
- `providers/sessions_provider.dart` — `SessionsState`, `SessionsNotifier`
- `providers/stream_provider.dart` — `StreamState`, `SignalBuffer`, `SignalFrame`, `SpikeFrame`, `StreamNotifier` *(migrate only data classes; keep mutable buffer logic)*
- `providers/quality_provider.dart` — `QualityState`, `QualityNotifier`
- `providers/preset_provider.dart` — `PresetState`, `PresetNotifier`

**Models → `@freezed`:**
- `models/device_info.dart` — `DeviceInfo`, `ChannelQuality`
- `models/session.dart` — `RecordingSession`, `EventMarker`
- `models/signal_quality.dart` — `SignalQuality`
- `models/preset.dart` — `AcquisitionPreset`, `FilterConfig`, `EncodingConfig`

**Also fix in same PR (Phase 2B/2C):**
- `lib/widgets/live_signal_viewer.dart:14-19,187-203` — remove `expandedHeight` parameter (double `Expanded` hazard)
- `lib/app.dart:85-91` — move `ProviderScope` override to root `main.dart`

Run `dart run build_runner build --delete-conflicting-outputs` after migration.

**Acceptance:** `dart analyze Neurosense/frontend/` clean; all `expect(state.x, equals(...))` matchers work without instance-identity assumptions; `flutter test test/providers/` passes; `flutter build web` succeeds; build_runner outputs committed.

---

### C2. NDH shell + core cleanup

**Source:** Frontend plan, Phase 5.

#### C2a. Narrow `except Exception` (safety-critical)
| File:Line | Narrow to |
|---|---|
| `neurodreamhand/shell/adapter.py:224` | `except (ValueError, KeyError, json.JSONDecodeError, binascii.Error, TypeError, UnicodeDecodeError)` |
| `neurodreamhand/shell/hitl_surface.py:254` | `except (IOError, OSError, TypeError, ValueError, RuntimeError)` |

#### C2b. Centralise physics constants
Add `neurodreamhand/core/_constants.py` with a `@dataclass(frozen=True) class SimDefaults`. Unify:
- `BASE_GRIP`, `KP`, `KD`, `N_NEURONS`, `NENGO_DT`, `TAU_FAST`, `TAU_SLOW`, `PERTURB_TIME`, `PERTURB_DUR`, `DURATION_S`
- **Important:** `ERROR_SCALE = 5.0` in `ocl_engine.py` vs `1.0` in `runner.py` — keep as `SimDefaults.error_scale = 1.0` + `SimDefaults.ocl_error_scale = 5.0`. Add a regression test asserting both values are distinct.

Update `experiments/drop_test.py`, `experiments/runner.py`, `learning/ocl_engine.py` to import from `_constants`.

#### C2c. Mid-body imports
Move to top-of-file:
- `hardware/loihi_exporter.py:116` — `import typing`
- `hardware/quantization.py:58` — `from typing import cast`
- `hardware/crossbar_exporter.py:109,176` — `import h5py`, `import typing`
- `experiments/statistical_validation.py:149,151` — `import matplotlib`, `from pathlib import Path`

#### C2d. Docstring style
`experiments/tracking.py:25-30,51-55,67-69` and `experiments/config.py:67-69` — convert Google-style (`Args:`) to NumPy-style (`Parameters\n----------`) to match the rest of NDH.

#### C2e. Magic numbers
- `adapter.py:35` — `2**31 - 1.0` → `_MAX_SEED: Final[float] = 2**31 - 1.0`
- `adapter.py:130` — `"0.6.0"` version fallback → read from `pyproject.toml` via `tomllib`

**Acceptance:** `python3 -m pytest Neuro-Dream-Hand/tests/test_neurodreamhand/` passes; `python3 -m mypy --strict neurodreamhand/core/ neurodreamhand/experiments/ neurodreamhand/hardware/ neurodreamhand/learning/ neurodreamhand/contracts/` clean; `ruff check --fix . && ruff format .` clean.

---

### C3. Contract sync — Pydantic → Dart codegen pipeline

**Source:** Frontend plan, Phase 7. Highest-risk item; plan before touching code.

**Strategy:** `datamodel-code-generator` Pydantic → Dart. New sibling package `nmtk_module_contracts_gen/` with a `scripts/sync_dart_contracts.py` wrapper and `.last_sync.json` fingerprint; CI fails on drift.

**First 4 model pairs to sync:**

| Python | Dart output |
|---|---|
| `Neurosense/contracts/device_contracts.py` → `DeviceInfo`, `DeviceConfig`, `ConnectionTransition` | `nmtk_module_contracts_gen/lib/src/neurosense/device.dart` |
| `Neurosense/contracts/session_contracts.py` → `RecordingSession`, `EventMarker` | `nmtk_module_contracts_gen/lib/src/neurosense/session.dart` |
| `Neurosense/contracts/preset_contracts.py` → `AcquisitionPreset`, `FilterConfig`, `EncodingConfig` | `nmtk_module_contracts_gen/lib/src/neurosense/preset.dart` |
| `Neurohub/contracts/project_contracts.py` → `Project`, `ProjectMember`, `ProjectLinks` | `nmtk_module_contracts_gen/lib/src/neurohub/project.dart` |

**Known divergences to fix during sync:**
- `Neurosense DeviceInfo` — JSON `serial_port`/`sampling_rate_hz` vs Dart `serialPort`/`samplingRateHz` (codegen resolves via `Field(alias=...)`)
- `Neurosense DeviceInfo.batteryPct` — required when `connected: true` in Python, not enforced in Dart → add `PostValidation` getter
- `Neurohub Project.name` — non-empty in Python validator, not enforced in Dart → same approach

**CI integration:**
1. `sync_dart_contracts.py` runs codegen, writes output to `nmtk_module_contracts_gen/lib/src/`
2. Computes SHA-256 of generated tree; compares to `.last_sync.json`
3. Exits non-zero on drift
4. Wire into `scripts/run_launcher_guardrails.sh` and `tests/integration/test_cross_module.py`

**Acceptance:** 4 model pairs generated and committed; `python3 scripts/sync_dart_contracts.py --check` exits 0; CI fails on Pydantic drift; `dart analyze` + `flutter test` clean in both Neurosense and Neurohub after consumer migration.

---

## Wave D — Low Priority / Deferred Polish

These are all safe to skip under scope pressure. Carry forward from Phase 8 of the June 11 plan:

| # | Frontend | File | Change |
|---|---|---|---|
| D1 | Neurobench | `workbench_shell.dart` | Use `NmtkDesktopScaffold` instead of raw `Scaffold` |
| D2 | Neurobench | `comparison_workspace.dart:89,247,256` | Add `if (!context.mounted) return;` guards |
| D3 | Neurosense | `replay_controls.dart`, `signal_quality_bar.dart` | Replace hardcoded `EdgeInsets`/`SizedBox` with `NmtkShellTokens` spacing tokens |
| D4 | Neurosense | `app.dart:124` | Replace `MediaQuery…size.width < 800` with `< NmtkShellTokens.normalBreakpoint` |
| D5 | Neurosense | `recording_controls.dart:206-250` | Replace 60fps `Ticker` with `Timer.periodic(Duration(seconds: 1))` |
| D6 | Neurohub | `api_service.dart` (257L) | Extract `_getList<T>()` helper to dedupe 4 list endpoints |
| D7 | Neurohub | `analysis_options.yaml:16-17` | Re-enable `use_key_in_widget_constructors`, `avoid_unnecessary_containers` |
| D8 | Neurohub | `README.md`, `web/index.html:21` | Replace Flutter template text with Neurohub-specific content |
| D9 | nmtk_ui_core | `shell_tokens.dart:202-343` | Consider freezed/macro codegen for the 141-line `copyWith`/`lerp` boilerplate |
| D10 | nmtk_ui_core | `desktop_scaffold.dart:1050,1384` | Replace manual `_hovered` setState with `InkWell`/`MouseRegion` only |
| D11 | NDH | `experiments/runner.py:178` + `learning/ocl_engine.py:120` | `error_scale` parameter — add docstring + `Final` |
| D12 | Neurobench | `lib/widgets/trend_chart.dart:32-34` | Implement with `fl_chart` or remove |

---

## Deployment Open Questions (18 June plan)

These questions from `tasks/18_june_deployment_plan.md` remain unanswered and block fully closing that plan:

> **Q1:** Do we deprecate the `rsync`-based production deployment (`make docker-ex-m`) in favour of registry deployment, or keep it as an offline fallback?

> **Q2:** For rapid development (`dev-sync`): does the local machine architecture match the remote server, or do we need multi-arch Docker builds (e.g. Apple Silicon vs x86_64)?

> **Q3:** Are there any private/proprietary pip packages or assets that must **not** be pushed to the public GitHub Container Registry?

> **Q4:** What should the default Docker image tag strategy be? (e.g. `latest` for master, `v1.x` for releases)

The `docker-compose.prod.yml` already uses `ghcr.io` images and `make deploy-prod`/`dev-sync` exist. Once the above questions are resolved, the June 18 plan is complete.

---

## Execution Order

| Order | Wave | Item | Risk | Notes |
|---|---|---|---|---|
| 1 | A | A1 — `MetricDiff.pValue` getter | none | 5-minute change |
| 2 | A | A5 — Linux file picker test | none | 10-minute change |
| 3 | A | A3 — dead legacy config fields | low | grep-verify before delete |
| 4 | A | A4 — restore ADR 0001 | none | documentation only |
| 5 | A | A2 — `runBenchmark()` | low | verify Python route shape first |
| 6 | B | B1 — Neurohub stubs | low | mechanical widget replacement |
| 7 | B | B4 — nmtk_ui_core hardening | medium | touches 3 consumers |
| 8 | B | B2 — test_cross_module.py rewrite | medium | needs live suite_api to verify |
| 9 | B | B3 — composeProfile (delete vs wire) | low | needs a decision first |
| 10 | C | C2 — NDH shell + core cleanup | low | well-tested module |
| 11 | C | C1 — Neurosense @freezed migration | medium | invasive but bounded |
| 12 | C | C3 — Contract sync pipeline | high | new tooling; plan session first |
| 13 | D | D1–D12 — polish items | very low | whenever there's bandwidth |

---

## Suite Verification Checklist (run after each wave)

```bash
# After any Dart change
dart fix --apply && dart format .
dart analyze
flutter test

# After any Python change
ruff check --fix . && ruff format .
python3 -m pytest <module>/tests/

# After any launcher/manifest/contract change
python3 scripts/launcher_control_service.py --doctor --json   # fatalCount must be 0
bash scripts/run_launcher_guardrails.sh

# After Wave B2 (test_cross_module.py) and C3 (contract sync)
python3 -m pytest tests/integration/test_cross_module.py tests/integration/test_teensy_e2e.py
python3 scripts/sync_dart_contracts.py --check
```
