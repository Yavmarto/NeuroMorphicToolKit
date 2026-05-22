# Implementation Plan: NIR Target-Aware Preflight

## Overview

This plan implements the preflight compatibility layer for NeuroCNL Studio.
Users will see NIR graph compatibility status before clicking Run by introducing
two new backend endpoints and a dedicated Riverpod provider on the frontend.

The implementation follows the bug-condition methodology:
- Exploration tests (Wave 1) expose the current gap — no preflight endpoint,
  validate always uses `'nir'`.
- Preservation tests (Wave 1) lock hardware paths against regression.
- Backend and frontend model work runs in parallel (Wave 2).
- API client and provider wiring follow (Wave 3).
- Studio screen integration (Wave 4), UI widgets (Wave 5), and pipeline bar
  (Wave 6) complete the feature.
- Exploration tests are verified on fixed code; PBT tests are added (Wave 7).
- A final checkpoint closes the plan (Wave 8).

---

## Tasks

- [x] 1. Write exploration and preservation tests
  - [x] 1.1 Write backend exploration tests for the missing preflight endpoints
    - In `neurocnl/backend/tests/test_preflight_exploration.py` (new file),
      write pytest tests that assert `POST /api/simulators/preflight` returns
      404 and `POST /api/simulators/preflight-nir` returns 404 (these are the
      "bug condition" tests; they should fail once the endpoints are added).
    - Write a preservation test that `POST /api/simulators/run` still returns
      the same response shape as before this feature — confirming Requirement
      11.3 is not broken.
    - _Requirements: 1.1, 2.1, 11.3_

  - [x] 1.2 Write frontend exploration tests for the validate backend hardcoding
    - In `neurocnl/frontend/test/pipeline_provider_exploration_test.dart` (new
      file), write widget / unit tests using a mock `ApiClient` that assert
      `runParseAndValidate` always calls `api.validate(spec, backend: 'nir')`
      regardless of the selected deploy target.  These must pass now and fail
      after Task 3.2.
    - Write a preservation test confirming that selecting a hardware target
      (`'teensy'`) still calls `api.validate(spec, backend: 'nir')`.
    - _Requirements: 6.1, 6.2_

- [x] 2. Backend schemas and endpoints; frontend Dart model and provider
  - [x] 2.1 Add `PreflightRequest` and `PreflightResult` Pydantic schemas
    - In `neurocnl/backend/app/schemas/simulators.py`, add:
      - `PreflightRequest(BaseModel)` with fields `spec: str` and
        `backend_name: str` (matching the design's schema).
      - `PreflightResult(BaseModel)` with fields `level: Literal["exact",
        "approximate", "unsupported"]`, `supported_nodes: list[str]`,
        `approximate_nodes: list[str]`, `unsupported_nodes: list[str]`,
        `diagnostics: list[str]` (all defaulting to empty lists except `level`).
    - Export both new classes from the module.
    - _Requirements: 1.1, 1.3, 2.1, 2.3_

  - [x] 2.2 Implement `POST /api/simulators/preflight` endpoint
    - In `neurocnl/backend/app/routers/simulators.py`, add imports:
      `Annotated`, `UploadFile`, `File`, `Form` from `fastapi`, `tempfile`,
      `pathlib.Path`, `nir`, and the two new schemas.
    - Implement `preflight()` following the pseudocode in the design:
      1. Validate `backend_name` ∈ `{"lava_sim", "snntorch_sim"}` → HTTP 422
         `unknown_backend`.
      2. `compile_to_nir(body.spec)` → HTTP 400 `compile_failed` on
         `CompileError` (same structured format as `/run`).
      3. `classify_nir_graph(graph, body.backend_name)` → return
         `PreflightResult` with the classification fields.
    - Apply `@limiter.limit("10/minute")` decorator, matching `/run`.
    - Do NOT call any simulator dispatch or dependency check.
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7_

  - [x] 2.3 Implement `POST /api/simulators/preflight-nir` endpoint
    - In the same router file, implement `preflight_nir()` following the design
      pseudocode:
      1. Validate `backend_name` → HTTP 422 `unknown_backend`.
      2. `contents = await file.read()` → write to `NamedTemporaryFile(suffix=".nir")`.
      3. `graph = nir.read(str(tmp_path))` → HTTP 422 `nir_parse_error` on any
         exception, with a human-readable message (use `finally: unlink(missing_ok=True)`).
      4. `classify_nir_graph(graph, backend_name)` → return `PreflightResult`.
    - Accept `file: Annotated[UploadFile, File()]` and `backend_name: Annotated[str, Form()]`.
    - Apply `@limiter.limit("10/minute")`.
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7_

  - [x] 2.4 Create Dart `PreflightResult` model
    - Create `neurocnl/frontend/lib/models/simulator_preflight.dart` (new file).
    - Implement the `PreflightResult` class exactly as specified in the design's
      "Frontend — Dart state model" section, including the `fromJson` factory
      that handles null-safe list parsing.
    - _Requirements: 3.1_

  - [x] 2.5 Create `SimulatorPreflightState` and `SimulatorPreflightNotifier` provider
    - Create `neurocnl/frontend/lib/providers/simulator_preflight_provider.dart`
      (new file).
    - Implement `SimulatorPreflightStatus` enum (`idle, running, success, error`).
    - Implement `SimulatorPreflightState` immutable class with all fields from
      the design, including the `runsBlocked` computed getter:
      `status == running || (level == 'unsupported' && !overrideMode)`.
    - Implement `SimulatorPreflightNotifier extends StateNotifier<SimulatorPreflightState>`:
      - `runPreflight(String spec, String backendName)` — key-based debounce,
        sets state to `running`, calls `apiClientProvider`, transitions to
        `success` or `error`; guards on `!mounted` and stale key.
      - `runPreflightNir(Uint8List nirBytes, String backendName)` — same
        lifecycle as `runPreflight` but calls `preflightNir()`.
      - `setOverrideMode(bool value)` — updates `overrideMode` field only.
      - `invalidate()` — resets to `const SimulatorPreflightState()`, clears
        `_currentKey`.
      - `_extractErrorMessage(ApiException e)` — tries to parse structured
        body; falls back to `'Preflight failed (HTTP ${e.statusCode})'`.
    - Export `simulatorPreflightProvider` as a `StateNotifierProvider`.
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6_

- [x] 3. `ApiClient` preflight methods; `pipeline_provider` target-aware validate
  - [x] 3.1 Add `preflight()` and `preflightNir()` to `ApiClient`
    - In `neurocnl/frontend/lib/services/api_client.dart`, add two methods after
      the existing `validate` section (import `simulator_preflight.dart`):
      - `Future<PreflightResult> preflight(String spec, String backendName)` —
        calls `_post('/simulators/preflight', {'spec': spec, 'backend_name': backendName})`
        and returns `PreflightResult.fromJson(response)`.
      - `Future<PreflightResult> preflightNir(Uint8List nirBytes, String backendName)` —
        builds a `MultipartRequest`, attaches the bytes as `'file'` with filename
        `'graph.nir'`, adds `'backend_name'` as a form field, sends via `_http`,
        throws `ApiException` on non-200, and returns `PreflightResult.fromJson(...)`.
      - Both methods must respect `apiKey` in the `X-API-Key` header.
    - _Requirements: 3.2, 3.3_

  - [x] 3.2 Make `runParseAndValidate` target-aware and trigger preflight
    - In `neurocnl/frontend/lib/providers/pipeline_provider.dart`:
      - Import `simulator_preflight_provider.dart` and `workspace_provider.dart`
        (already imported).
      - In `runParseAndValidate`, read `_ref.read(workspaceProvider).selectedDeployTarget`
        to determine `backend`:
        - If target is `'lava_sim'` or `'snntorch_sim'`, pass it as `backend` to
          `api.validate(spec, backend: target)`.
        - Otherwise pass `backend: 'nir'` (preserves existing behaviour).
      - After a successful validate (status becomes `success`): if a simulator
        target is selected, call
        `_ref.read(simulatorPreflightProvider.notifier).runPreflight(spec, target)`.
      - After a failed validate (status becomes `error`): if a simulator target is
        selected, call
        `_ref.read(simulatorPreflightProvider.notifier).invalidate()`.
      - When `spec.trim().isEmpty`, also call
        `_ref.read(simulatorPreflightProvider.notifier).invalidate()` after resetting
        state to `const PipelineState()`.
    - _Requirements: 6.1, 6.2, 10.1, 10.2, 10.3_

- [x] 4. Studio screen integration
  - [x] 4.1 Add `_scheduleSimulatorPreflight` and update `_selectDeployTarget`
    - In `neurocnl/frontend/lib/screens/studio_screen.dart`:
      - Import `simulator_preflight_provider.dart` and `nir_import_provider.dart`.
      - Add `static const _simulatorTargets = {'lava_sim', 'snntorch_sim'}`.
      - Implement `void _scheduleSimulatorPreflight(String targetId)` following
        the design pseudocode:
        - Non-simulator target → call `simulatorPreflightProvider.notifier.invalidate()`.
        - Compute a debounce key: NIR file loaded → `'$targetId:nir:${nirState.result.hashCode}'`;
          CNL → `'$targetId:cnl:${spec.hashCode}'`.
        - If `_lastDeployValidationKeys[targetId] == key`, return early.
        - Set `_lastDeployValidationKeys[targetId] = key`.
        - Use `addPostFrameCallback` to call either `runPreflightNir` (if NIR
          file is loaded and bytes are resolvable) or `runPreflight`.
      - In `_selectDeployTarget`, add `_scheduleSimulatorPreflight(targetId)`
        after calling `setSelectedDeployTarget`.
    - _Requirements: 4.1, 4.2, 4.4, 4.5, 11.1_

  - [x] 4.2 Trigger preflight when deploy panel opens
    - In `_buildPanelContent` in `studio_screen.dart`, for the `'deploy'` panel
      case, add `_scheduleSimulatorPreflight(selectedTarget)` after the existing
      `_scheduleDeployValidation(selectedTarget)` call.
    - This ensures re-opening the panel with an already-selected simulator target
      always re-fires the debounced preflight check.
    - _Requirements: 4.3_

  - [x] 4.3 Trigger preflight after NIR file import
    - In `neurocnl/frontend/lib/widgets/nir_importer_tab.dart`, inside the
      `_applyWriteBack()` callback (or the equivalent `addPostFrameCallback`
      block that fires when `NirImportState` transitions to `loaded` with
      `source == NirSource.file`):
      - Read `selectedDeployTarget` from `workspaceProvider`.
      - If the target is in `_simulatorTargets` and raw bytes are available
        (from `NirImportState.result`), call
        `simulatorPreflightProvider.notifier.runPreflightNir(nirBytes, target)`.
    - Note: `NirInspectResult` may need a `rawBytes` field; if the bytes are
      not persisted in `NirInspectResult`, store them in `NirImportState` instead
      (add a `rawBytes: Uint8List?` field to `NirImportState` and populate it in
      `NirImportNotifier.inspectFile` before the write-back step).
    - _Requirements: 5.1, 5.2, 5.3, 5.4_

- [x] 5. `SimulatorPanel` UI — `_PreflightResultWidget` and Run button gating
  - [x] 5.1 Implement `_PreflightResultWidget` in `simulator_panel.dart`
    - Add a `_PreflightResultWidget extends ConsumerWidget` that reads
      `simulatorPreflightProvider` and renders:
      - `idle` → `SizedBox.shrink()` (region absent).
      - `running` → compact spinner row: `CircularProgressIndicator(strokeWidth: 2)`
        + `Text('Checking compatibility…')`.
      - `success, level == "exact"` → green `_PreflightBadge('Fully supported')`
        + `_NodeList` for `supportedNodes`.
      - `success, level == "approximate"` → amber `_PreflightBadge('Approximate')`
        + `_NodeList` for `approximateNodes` with caution label
        + `_NodeList` for `supportedNodes`.
      - `success, level == "unsupported"` → red `_PreflightBadge('Unsupported')`
        + `_NodeList` for `unsupportedNodes` with diagnostics
        + optional lists for `supportedNodes` and `approximateNodes`
        + `_OverrideToggle` that calls `setOverrideMode`.
      - `error` → red icon + `Text(errorMessage)`.
    - Add private `_PreflightBadge`, `_NodeList`, and `_OverrideToggle` helper
      widgets using `AppTheme` tokens and 12 px compact padding.
    - _Requirements: 7.1, 7.2, 7.3, 7.4, 7.5, 7.6, 8.5_

  - [x] 5.2 Insert `_PreflightResultWidget` and gate the Run button in `_CompactToolbar`
    - In the `locked == true` branch of `_SimulatorPanelState.build()`, insert
      `_PreflightResultWidget()` above the `_CompactToolbar` widget.
    - In `_CompactToolbar` (or pass down a `preflightBlocking` bool), read
      `simulatorPreflightProvider` and set the `Run Simulation` button's
      `onPressed` to `null` when `preflightState.runsBlocked == true`.
    - Wrap the `FilledButton` in a `Tooltip` whose message is:
      - `'Preflight in progress — please wait.'` when status is `running`.
      - `'Unsupported node types detected. See preflight results above.'` when
        `level == "unsupported" && !overrideMode`.
      - An amber warning listing `approximateNodes` when `level == "approximate"`.
    - _Requirements: 8.1, 8.2, 8.3, 8.4_

- [x] 6. Pipeline bar integration
  - [x] 6.1 Update `PipelineBar` deploy step to reflect preflight state
    - In `neurocnl/frontend/lib/widgets/pipeline_bar.dart`:
      - Import `simulator_preflight_provider.dart` and `workspace_provider.dart`.
      - In `build()`, read `simulatorPreflightProvider` and
        `workspaceProvider.select((w) => w.selectedDeployTarget)`.
      - Compute `isSimulatorTarget = selectedTarget == 'lava_sim' || selectedTarget == 'snntorch_sim'`.
      - For the `'deploy'` step, use the preflight-aware status and detail
        when `isSimulatorTarget`:
        - `running` → `NmtkStepStatus.running`, detail `'Preflight…'`.
        - `success && level == "exact"` → `NmtkStepStatus.success`, detail `'Preflight OK'`.
        - `success && level == "approximate"` → `NmtkStepStatus.success`, detail `'Approximate'`.
        - `success && level == "unsupported"` → `NmtkStepStatus.error`, detail `'Unsupported nodes'`.
        - `error` → `NmtkStepStatus.error`, detail `'Preflight error'`.
        - `idle` → fall back to existing `_deployStatusFor(pipeline)` / `_deployDetailFor(pipeline)`.
      - When `!isSimulatorTarget`, keep the existing `_deployStatusFor` path
        unchanged (hardware targets and no-target).
    - _Requirements: 9.1, 9.2, 9.3, 9.4, 9.5, 9.6, 11.4_

- [x] 7. Verify exploration tests pass; add property-based tests
  - [x] 7.1 Verify backend exploration tests now pass
    - Re-run `neurocnl/backend/tests/test_preflight_exploration.py`.
    - The exploration tests from Task 1.1 that previously expected 404 must
      now be updated/inverted to assert HTTP 200 for valid requests — confirming
      the endpoints exist and respond correctly.
    - _Requirements: 1.1, 2.1_

  - [x] 7.2 Write PBT Property 1 — preflight CNL response completeness
    - In `neurocnl/backend/tests/test_preflight_properties.py`, write a
      Hypothesis test `test_preflight_cnl_response_completeness` with
      `settings(max_examples=100)`.
    - Use `st.sampled_from(VALID_CNL_FIXTURES)` and
      `st.sampled_from(["lava_sim", "snntorch_sim"])`.
    - Assert: HTTP 200, all five fields present, level-consistency invariant
      (non-empty `unsupported_nodes` → `level == "unsupported"`; non-empty
      `approximate_nodes` and empty `unsupported_nodes` → `level == "approximate"`).
    - **Property 1: Preflight endpoint response completeness (CNL path)**
    - **Validates: Requirements 1.2, 1.3**

  - [x] 7.3 Write PBT Property 2 — preflight NIR response completeness
    - In the same file, write `test_preflight_nir_response_completeness`.
    - Build random `nir.NIRGraph` objects in-process, serialise to HDF5, read
      bytes. Assert HTTP 200 and that the response matches
      `classify_nir_graph(graph, backend_name)` called directly.
    - **Property 2: Preflight endpoint response completeness (NIR path)**
    - **Validates: Requirements 2.2, 2.3**

  - [x] 7.4 Write PBT Property 3 — compile error maps to HTTP 400
    - Write `test_preflight_cnl_compile_error` using `st.text()` filtered to
      strings that cause `compile_to_nir` to raise `CompileError`.
    - Assert HTTP 400, `compile_failed` code, non-empty `items` with
      `source == "compile"`.
    - **Property 3: Compile error maps to HTTP 400**
    - **Validates: Requirements 1.4**

  - [x] 7.5 Write PBT Property 4 — invalid HDF5 maps to HTTP 422 nir_parse_error
    - Write `test_preflight_nir_parse_error` using `st.binary()` (possibly
      filtered to non-valid HDF5 byte sequences).
    - Assert HTTP 422, `nir_parse_error` code, non-empty human-readable message.
    - **Property 4: Invalid HDF5 maps to HTTP 422 with nir_parse_error**
    - **Validates: Requirements 2.4**

  - [x] 7.6 Write PBT Property 5 — unknown backend rejected at both endpoints
    - Write `test_preflight_unknown_backend` using
      `st.text().filter(lambda s: s not in {"lava_sim", "snntorch_sim"})`.
    - Assert HTTP 422, `unknown_backend` code for both endpoints.
    - **Property 5: Unknown backend rejected at both endpoints**
    - **Validates: Requirements 1.5, 2.5**

  - [x] 7.7 Verify frontend exploration tests now pass
    - Re-run `test/pipeline_provider_exploration_test.dart`.
    - The tests from Task 1.2 that previously asserted `backend: 'nir'` for
      simulator targets must now be updated to assert the simulator target id
      is passed as the backend, confirming Task 3.2 is correct.
    - _Requirements: 6.1, 6.2_

  - [x] 7.8 Write PBT Property 6 — provider state lifecycle
    - In `neurocnl/frontend/test/simulator_preflight_provider_test.dart` (new),
      write a glados/property test `testPreflightProviderStateLifecycle`.
    - Use arbitrary `(spec, backendName)` pairs with a mock `ApiClient` that
      either returns a `PreflightResult` or throws `ApiException`.
    - Assert idle → running → success transitions; assert idle → running → error
      transitions; assert `errorMessage` is non-null on error.
    - **Property 6: Provider state lifecycle (running → success/error)**
    - **Validates: Requirements 3.1, 3.2, 3.3**

  - [x] 7.9 Write PBT Property 7 — debounce drops in-flight duplicates
    - Write `testPreflightProviderDebounce` with a delayed-mock `ApiClient`.
    - For any key (same `backendName` + `specHash`), calling `runPreflight`
      twice while in-flight must result in exactly one HTTP POST.
    - **Property 7: Debounce — in-flight duplicates are dropped**
    - **Validates: Requirements 3.4, 4.5**

  - [x] 7.10 Write PBT Property 8 — invalidation resets all state
    - Write `testPreflightProviderInvalidation` over arbitrary non-idle states
      (including `overrideMode == true`).
    - Assert `invalidate()` transitions to `idle`, `level == null`,
      `overrideMode == false`, all node lists empty, `errorMessage == null`.
    - **Property 8: Invalidation resets all state (including override mode)**
    - **Validates: Requirements 3.5, 8.6, 10.3**

  - [x] 7.11 Write PBT Property 9 — pipeline bar deploy step mapping
    - Write `testPipelineBarDeployStepMapping` over arbitrary
      `SimulatorPreflightState` values and `isSimulatorTarget` booleans.
    - Assert the four-way mapping (running/success+level/error/idle) and that
      hardware targets always use `_deployStatusFor(pipeline)`.
    - **Property 9: Pipeline bar deploy step maps correctly from preflight state**
    - **Validates: Requirements 9.1–9.6, 11.4**

  - [x] 7.12 Write PBT Property 10 — Run button blocked by unsupported or in-flight
    - Write `testRunButtonGating` over arbitrary `SimulatorPreflightState`.
    - Assert `runsBlocked == true` iff `status == running` or
      (`level == "unsupported"` and `!overrideMode`); assert `onPressed == null`
      in those cases.
    - **Property 10: Run button blocked by unsupported or in-flight preflight**
    - **Validates: Requirements 8.1, 8.2, 8.4**

  - [x] 7.13 Write PBT Property 11 — override activation enables run
    - Write `testOverrideEnablesRun` over arbitrary unsupported `PreflightResult`
      states.
    - Assert `setOverrideMode(true)` → `runsBlocked == false` while all other
      state fields remain unchanged.
    - **Property 11: Override activation enables run for unsupported graphs**
    - **Validates: Requirements 8.5**

  - [x] 7.14 Write PBT Property 12 — pipeline provider uses simulator backend for validate
    - Write `testValidateBackendSelection` over arbitrary `(spec, deployTarget)`.
    - Assert simulator targets → `api.validate(backend: target)`;
      non-simulator → `api.validate(backend: 'nir')`.
    - **Property 12: Pipeline provider uses simulator backend for validate**
    - **Validates: Requirements 6.1, 6.2**

  - [x] 7.15 Write PBT Property 13 — preflight triggered after successful validate
    - Write `testPipelinePreflightTriggerOnValidate` over arbitrary
      `(spec, simulatorTarget)`.
    - Assert `runPreflight` called with the spec and target on validate success;
      `invalidate()` called on validate failure.
    - **Property 13: Preflight triggered after successful validate for simulator target**
    - **Validates: Requirements 10.1, 10.2**

  - [x] 7.16 Write PBT Property 14 — hardware targets never trigger simulator preflight
    - Write `testNoPreflightForHardwareTargets` over arbitrary hardware target IDs
      (`'teensy'`, `'pynq'`, `'akida'`, `'lava'`).
    - Assert `runPreflight` and `runPreflightNir` are never called for any
      hardware target path (`_selectDeployTarget`, NIR import, validate completion).
    - **Property 14: Hardware targets never trigger simulator preflight**
    - **Validates: Requirements 4.4, 5.2, 5.3, 11.1**

  - [-] 7.17 Write PBT Property 15 — NIR import triggers runPreflightNir
    - Write `testNirImportTriggersPreflight` over arbitrary `(nirBytes, simulatorTarget)`.
    - Simulate `NirImportState` transitioning to `loaded` with
      `source == NirSource.file`; assert `runPreflightNir` called with bytes and
      target when a simulator target is selected; assert NOT called when no
      simulator target is selected.
    - **Property 15: NIR import triggers runPreflightNir for active simulator target**
    - **Validates: Requirements 5.1, 5.2**

- [x] 8. Final checkpoint
  - Ensure all tests pass (backend and frontend).
  - Verify no regressions in hardware deploy paths (Teensy, PYNQ, Akida, Lava/Loihi2).
  - Ask the user if any questions arise before closing.

---

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP delivery.
- Backend endpoints intentionally never return 503 — they do not check whether
  `lava` or `snntorch` are installed (that check lives in `/run` only).
- The `_scheduleSimulatorPreflight` debounce key uses `hashCode`, matching the
  Teensy `_lastDeployValidationKeys` pattern exactly — do not use a different
  debounce mechanism.
- `NirImportState` may need a `rawBytes: Uint8List?` field to pass bytes from
  `inspectFile` to the NIR import hook in Task 4.3; evaluate during
  implementation and keep the change minimal.
- Override mode is ephemeral — scoped to the current preflight result; any
  spec change, re-preflight, or `invalidate()` call resets it.
- PBT tests use Hypothesis (Python) and glados (Dart); each must be configured
  with a minimum of 100 iterations.
- Each task references specific requirements for traceability; checkpoints
  ensure incremental validation.

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1", "1.2"] },
    { "id": 1, "tasks": ["2.1", "2.4"] },
    { "id": 2, "tasks": ["2.2", "2.3", "2.5"] },
    { "id": 3, "tasks": ["3.1", "3.2"] },
    { "id": 4, "tasks": ["4.1"] },
    { "id": 5, "tasks": ["4.2", "4.3"] },
    { "id": 6, "tasks": ["5.1", "6.1"] },
    { "id": 7, "tasks": ["5.2"] },
    { "id": 8, "tasks": ["7.1", "7.7"] },
    { "id": 9, "tasks": ["7.2", "7.3", "7.4", "7.5", "7.6", "7.8", "7.9", "7.10", "7.11", "7.12", "7.13", "7.14", "7.15", "7.16", "7.17"] }
  ]
}
```
