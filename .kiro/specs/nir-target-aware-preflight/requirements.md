# Requirements Document

## Introduction

Today the NeuroCNL Studio lets users compose a network, run Parse → Validate →
Generate → Deploy, pick a simulator target (lava_sim / snntorch_sim), and click
Run. The compatibility check that decides whether the compiled NIR graph can
execute on the chosen backend only happens *inside* `POST /api/simulators/run`,
returning an HTTP 422 after the user has already committed to running. The user
sees nothing useful until after the expensive round-trip fails.

This feature adds a **target-aware preflight** layer that surfaces compatibility
status as early as possible — ideally the moment a deploy target is selected —
by introducing two new backend endpoints and updating the Studio frontend to
trigger and display preflight results before the Run button is ever pressed.

The key changes are:

1. **Backend** — two new lightweight classification-only endpoints that reuse
   the existing `classify_nir_graph` logic from `nir_support.py` without
   dispatching to a simulator.
2. **Frontend (provider)** — `runParseAndValidate` becomes target-aware;
   a new `SimulatorPreflightProvider` manages preflight state separately from
   the run state.
3. **Frontend (UI)** — the Deploy panel auto-triggers preflight, renders a
   node-level compatibility breakdown, gates the Run button on the result, and
   mirrors the status into the pipeline bar's Deploy step.

The Teensy `_scheduleDeployValidation` pattern is the established model for
"auto-validate on target selection"; this feature generalises that pattern to
simulator targets.

---

## Glossary

- **Preflight**: A classification-only request that compiles CNL to NIR (or
  accepts a raw NIR graph) and checks it against a simulator backend's
  node-support table, returning a `SupportClassification` without dispatching
  to the simulator.
- **SupportClassification**: The result of `classify_nir_graph` —
  `level` ("exact" | "approximate" | "unsupported"), plus lists of
  `supported_nodes`, `approximate_nodes`, `unsupported_nodes`, and
  `diagnostics`.
- **Preflight_Endpoint**: `POST /api/simulators/preflight` — accepts a CNL
  spec and a backend name; compiles to NIR internally, then classifies.
- **NIR_Preflight_Endpoint**: `POST /api/simulators/preflight-nir` — accepts
  a raw NIR graph (as HDF5 bytes or the serialised JSON representation already
  used by the inspect endpoint) and a backend name; classifies without
  recompiling CNL.
- **Simulator_Target**: One of the two software simulator deploy targets:
  `lava_sim` or `snntorch_sim`.
- **Hardware_Target**: A non-simulator deploy target: `teensy`, `pynq`,
  `akida`, or `lava` (Loihi2 hardware). Preflight in this spec applies only
  to Simulator_Targets.
- **Deploy_Panel**: The Studio panel shown when the user selects the "Deploy"
  tab in the right-hand panel list.
- **Pipeline_Bar**: The horizontal four-step progress strip (Parse → Validate
  → Generate → Deploy) rendered at the top of the Studio.
- **Preflight_Provider**: A new Riverpod `StateNotifierProvider` in the Flutter
  frontend that manages the lifecycle of a single preflight request
  (idle → running → result | error).
- **Run_Button**: The "Run Simulation" `FilledButton` inside `SimulatorPanel`
  (also labelled "Run" in the compact Deploy-pane layout).
- **Override_Mode**: A user-acknowledged state in which the Run button is
  re-enabled despite a preflight result of `level == "unsupported"`.
- **Backend_Name**: The string identifier of a simulator backend passed in API
  requests: `"lava_sim"` or `"snntorch_sim"`.
- **NIR_Node_Type**: The Python class name of a node in a compiled NIR graph
  (e.g. `"Conv2d"`, `"LIF"`, `"Linear"`).
- **CNL_Spec**: The text content of the active workspace file, a NeuroCNL
  specification.
- **NIR_Graph**: The compiled intermediate representation produced by
  `neurocnl.compile_to_nir(spec)` or imported from a `.nir` HDF5 file.

---

## Requirements

### Requirement 1: Preflight Endpoint (CNL Input)

**User Story:** As a backend developer, I want a dedicated preflight endpoint
that classifies a CNL spec against a simulator backend without running the
simulation, so that the Studio can show compatibility status before the user
clicks Run.

#### Acceptance Criteria

1. THE Preflight_Endpoint SHALL accept HTTP POST requests at
   `/api/simulators/preflight` with a JSON body containing fields `spec`
   (string) and `backend_name` (string).

2. WHEN a valid request is received, THE Preflight_Endpoint SHALL compile the
   `spec` field to a NIR graph using `neurocnl.compile_to_nir` and classify
   it with `classify_nir_graph(graph, backend_name)`.

3. WHEN compilation or classification succeeds, THE Preflight_Endpoint SHALL
   return HTTP 200 with a JSON body containing `level` ("exact" |
   "approximate" | "unsupported"), `supported_nodes` (list of strings),
   `approximate_nodes` (list of strings), `unsupported_nodes` (list of
   strings), and `diagnostics` (list of strings).

4. IF the `spec` fails to compile, THEN THE Preflight_Endpoint SHALL return
   HTTP 400 with the same structured `CompileError` diagnostic format used by
   `POST /api/simulators/run`.

5. IF `backend_name` is not one of `"lava_sim"` or `"snntorch_sim"`, THEN
   THE Preflight_Endpoint SHALL return HTTP 422 with an `unknown_backend`
   error code.

6. THE Preflight_Endpoint SHALL NOT dispatch to any simulator runtime and SHALL
   NOT check whether optional simulator dependencies are installed.

7. THE Preflight_Endpoint SHALL apply the same rate limit as
   `POST /api/simulators/run` (10 requests per minute per IP).

---

### Requirement 2: Preflight Endpoint (Raw NIR Graph Input)

**User Story:** As a backend developer, I want a second preflight endpoint that
classifies a raw NIR graph against a simulator backend, so that the Studio can
show preflight results for imported `.nir` files before any CNL has been
written.

#### Acceptance Criteria

1. THE NIR_Preflight_Endpoint SHALL accept HTTP POST requests at
   `/api/simulators/preflight-nir` with a multipart form body containing a
   `file` field (the `.nir` HDF5 binary) and a `backend_name` field (string).

2. WHEN a valid request is received, THE NIR_Preflight_Endpoint SHALL load the
   NIR graph from the uploaded file bytes using the same HDF5 loading path
   already used by `POST /api/nir/inspect`, then classify it with
   `classify_nir_graph(graph, backend_name)`.

3. WHEN loading and classification succeed, THE NIR_Preflight_Endpoint SHALL
   return HTTP 200 with the same JSON response shape as Requirement 1.3.

4. IF the uploaded file cannot be parsed as a valid NIR HDF5 file, THEN THE
   NIR_Preflight_Endpoint SHALL return HTTP 422 with a `nir_parse_error`
   error code and a human-readable message identifying the failure.

5. IF `backend_name` is not one of `"lava_sim"` or `"snntorch_sim"`, THEN
   THE NIR_Preflight_Endpoint SHALL return HTTP 422 with an `unknown_backend`
   error code.

6. THE NIR_Preflight_Endpoint SHALL NOT recompile CNL and SHALL NOT dispatch
   to any simulator runtime.

7. THE NIR_Preflight_Endpoint SHALL apply the same rate limit as
   `POST /api/simulators/run` (10 requests per minute per IP).

---

### Requirement 3: Preflight Provider (Frontend State Management)

**User Story:** As a frontend developer, I want a dedicated Riverpod provider
that manages preflight state for a simulator target, so that preflight results
are available to any widget in the Deploy panel without coupling to the run
state.

#### Acceptance Criteria

1. THE Preflight_Provider SHALL expose a state containing: `status`
   (idle | running | success | error), `backendName` (nullable string),
   `level` (nullable "exact" | "approximate" | "unsupported"),
   `supportedNodes` (list of strings), `approximateNodes` (list of strings),
   `unsupportedNodes` (list of strings), `diagnostics` (list of strings),
   and `errorMessage` (nullable string).

2. WHEN `runPreflight(spec, backendName)` is called on the
   Preflight_Provider, THE Preflight_Provider SHALL POST to
   `POST /api/simulators/preflight`, update `status` to `running` while
   the request is in-flight, then transition to `success` or `error` based
   on the HTTP response.

3. WHEN `runPreflightNir(nirBytes, backendName)` is called on the
   Preflight_Provider, THE Preflight_Provider SHALL POST to
   `POST /api/simulators/preflight-nir`, follow the same status lifecycle
   as Requirement 3.2.

4. WHILE a preflight request is in-flight, THE Preflight_Provider SHALL ignore
   any new `runPreflight` or `runPreflightNir` calls for the same
   `backendName` and `spec`/`nirBytes` combination (debounce by key).

5. WHEN the active workspace file content changes, THE Preflight_Provider
   SHALL invalidate the current preflight result and set `status` to `idle`.

6. THE Preflight_Provider SHALL be scoped to the active simulator target so
   that switching between `lava_sim` and `snntorch_sim` resets the state.

---

### Requirement 4: Auto-Preflight on Simulator Target Selection

**User Story:** As a user, I want the Studio to automatically check whether
my current network is compatible with a simulator target as soon as I select
it, so that I learn about incompatibilities before clicking Run.

#### Acceptance Criteria

1. WHEN the user selects `lava_sim` or `snntorch_sim` as the deploy target,
   THE Studio SHALL call `Preflight_Provider.runPreflight` with the current
   `CNL_Spec` and the selected `Backend_Name` within one event loop frame
   (using `addPostFrameCallback`, matching the Teensy deploy-validation
   pattern).

2. WHEN the user selects `lava_sim` or `snntorch_sim` as the deploy target
   AND the active workspace file was populated from a `.nir` import (i.e.
   `NirImportState.source == NirSource.file`), THE Studio SHALL call
   `Preflight_Provider.runPreflightNir` with the imported NIR bytes instead
   of `runPreflight`.

3. WHEN the Deploy panel is opened and a Simulator_Target is already selected,
   THE `_buildPanelContent` method SHALL trigger the same preflight schedule
   that fires on target selection, so that re-opening the panel always reflects
   the current state.

4. WHEN a Hardware_Target is selected (teensy, pynq, akida, lava), THE Studio
   SHALL NOT trigger a simulator preflight.

5. WHEN the user selects the same Simulator_Target that is already selected,
   THE Studio SHALL NOT re-trigger the preflight if the spec has not changed
   since the last successful preflight for that target (key-based debounce
   matching `_lastDeployValidationKeys`).

---

### Requirement 5: Auto-Preflight on NIR File Import

**User Story:** As a user, I want the Studio to automatically check whether
an imported `.nir` file is compatible with my currently selected simulator
target, so that I see compatibility status immediately after import without
having to click Run.

#### Acceptance Criteria

1. WHEN a `.nir` file finishes loading (i.e. `NirImportState.status`
   transitions to `NirImportStatus.loaded` with `source == NirSource.file`)
   AND a Simulator_Target is already selected, THE Studio SHALL call
   `Preflight_Provider.runPreflightNir` with the imported file bytes and the
   selected `Backend_Name`.

2. WHEN a `.nir` file is imported AND no Simulator_Target is currently
   selected, THE Studio SHALL NOT trigger a preflight.

3. WHEN a `.nir` file is imported AND a Hardware_Target is currently selected,
   THE Studio SHALL NOT trigger a simulator preflight.

4. IF the NIR preflight call fails with a `nir_parse_error`, THE
   Preflight_Provider SHALL set `status` to `error` and surface the
   `errorMessage` in the Deploy panel without preventing the import
   write-back from completing.

---

### Requirement 6: Target-Aware Validate

**User Story:** As a user, I want the Validate pipeline step to use my selected
simulator target's backend when possible, so that the CNL-level planner
verdict reflects my actual target and I do not receive a generic "nir backend"
result when I have already selected lava_sim or snntorch_sim.

#### Acceptance Criteria

1. WHEN `runParseAndValidate` is called AND `workspaceProvider.selectedDeployTarget`
   is `"lava_sim"` or `"snntorch_sim"`, THE Pipeline_Provider SHALL pass that
   value as the `backend` parameter to `api.validate(spec, backend: backendName)`.

2. WHEN `runParseAndValidate` is called AND the selected deploy target is a
   Hardware_Target or is not set, THE Pipeline_Provider SHALL pass `backend: 'nir'`
   as it does today (no regression).

3. WHEN the selected deploy target changes while a parse/validate cycle is
   in-flight, THE next auto-triggered validate cycle SHALL use the updated
   target (the in-flight request SHALL complete with its original backend).

4. WHEN the `ValidationResult.backendSupport` field is populated from a
   simulator-targeted validate call, THE Validation panel SHALL display the
   backend name alongside the planner verdict so the user knows which backend
   was checked.

---

### Requirement 7: Preflight Result Display in Deploy Panel

**User Story:** As a user, I want to see a clear preflight compatibility
breakdown in the Deploy panel before I click Run, so that I know exactly which
NIR node types are supported, approximate, or unsupported for my selected
simulator target.

#### Acceptance Criteria

1. WHEN the Preflight_Provider `status` is `running`, THE Deploy panel SHALL
   display a loading indicator in place of the preflight result area.

2. WHEN the Preflight_Provider `status` is `success` and `level` is `"exact"`,
   THE Deploy panel SHALL display a green "Fully supported" badge and list all
   `supportedNodes` by NIR_Node_Type name.

3. WHEN the Preflight_Provider `status` is `success` and `level` is
   `"approximate"`, THE Deploy panel SHALL display an amber "Approximate"
   badge, list `approximateNodes` with a caution label, and list
   `supportedNodes`.

4. WHEN the Preflight_Provider `status` is `success` and `level` is
   `"unsupported"`, THE Deploy panel SHALL display a red "Unsupported" badge,
   list all `unsupportedNodes` with their diagnostic messages, and list any
   `supportedNodes` and `approximateNodes`.

5. WHEN the Preflight_Provider `status` is `error`, THE Deploy panel SHALL
   display the `errorMessage` inline in the preflight result area without
   hiding the Run button area.

6. WHEN the Preflight_Provider `status` is `idle`, THE Deploy panel SHALL NOT
   display a preflight result area (the region is absent, not blank).

---

### Requirement 8: Run Button Gating

**User Story:** As a user, I want the Run button to be disabled when the
preflight result shows my network is unsupported, so that I cannot accidentally
start a simulation that will immediately fail with a 422 error.

#### Acceptance Criteria

1. WHEN the Preflight_Provider `level` is `"unsupported"` AND
   `Override_Mode` is not active, THE Run_Button SHALL be disabled and SHALL
   display a tooltip reading "Unsupported node types detected. See preflight
   results above." (or equivalent locale string).

2. WHEN the Preflight_Provider `level` is `"approximate"`, THE Run_Button
   SHALL remain enabled and SHALL display a warning tooltip listing the
   approximate node types.

3. WHEN the Preflight_Provider `level` is `"exact"` or `status` is `idle`,
   THE Run_Button SHALL behave as it does today (enabled when the backend is
   available and the spec is non-empty).

4. WHEN the Preflight_Provider `status` is `running`, THE Run_Button SHALL be
   disabled until the preflight completes, to prevent the user from running
   before the classification is known.

5. WHEN the Preflight_Provider `level` is `"unsupported"`, THE Deploy panel
   SHALL display an "Override — run anyway" toggle or link. WHEN the user
   activates this toggle, THE Preflight_Provider SHALL set `Override_Mode` to
   active for the current preflight result, re-enabling the Run_Button with a
   persistent amber "Override active" warning.

6. WHEN the spec changes or a new preflight runs, THE Preflight_Provider SHALL
   reset `Override_Mode` to inactive and SHALL set `status` to `idle`, so the
   provider is ready to accept a new preflight request rather than indicating
   that a run is in progress.

---

### Requirement 9: Pipeline Bar Deploy Step Reflects Preflight

**User Story:** As a user, I want the pipeline bar's Deploy step to reflect
the preflight status so that I can see compatibility at a glance without
opening the Deploy panel.

#### Acceptance Criteria

1. WHEN the Preflight_Provider `status` is `running`, THE Pipeline_Bar Deploy
   step SHALL display `StepStatus.running`.

2. WHEN the Preflight_Provider `status` is `success` and `level` is `"exact"`,
   THE Pipeline_Bar Deploy step SHALL display `StepStatus.success` with detail
   text "Preflight OK".

3. WHEN the Preflight_Provider `status` is `success` and `level` is
   `"approximate"`, THE Pipeline_Bar Deploy step SHALL display
   `StepStatus.success` with detail text "Approximate" (amber colouring via
   the existing approximate SupportLevel chip).

4. WHEN the Preflight_Provider `status` is `success` and `level` is
   `"unsupported"`, THE Pipeline_Bar Deploy step SHALL display
   `StepStatus.error` with detail text "Unsupported nodes".

5. WHEN no Simulator_Target is selected OR the Preflight_Provider `status`
   is `idle`, THE Pipeline_Bar Deploy step SHALL fall back to its current
   behaviour (based on `generateStatus`).

6. WHEN a Hardware_Target is selected, THE Pipeline_Bar Deploy step SHALL
   NOT use preflight status and SHALL continue to reflect the existing
   generate/deploy step status.

---

### Requirement 10: Preflight on Spec Change (Incremental Re-check)

**User Story:** As a user, I want the preflight result to update automatically
when I edit the CNL spec and the validate step completes, so that I always see
an up-to-date compatibility status for my current network.

#### Acceptance Criteria

1. WHEN `runParseAndValidate` completes successfully AND a Simulator_Target
   is currently selected, THE Pipeline_Provider SHALL trigger
   `Preflight_Provider.runPreflight` with the validated spec and the selected
   backend name.

2. WHEN `runParseAndValidate` fails (parse or validate error), THE
   Pipeline_Provider SHALL reset the Preflight_Provider to `status: idle` for
   the current simulator target, so stale preflight results are not shown for
   a broken spec.

3. WHEN the spec text changes (before validate completes), THE
   Preflight_Provider SHALL transition to `status: idle`, clearing the
   previous preflight result immediately, so the user does not see stale
   green/red status.

4. WHEN no Simulator_Target is selected, THE Pipeline_Provider SHALL NOT
   trigger preflight after validate completes (no regression against current
   behaviour).

---

### Requirement 11: No Disruption to Hardware Deploy Paths

**User Story:** As a user targeting Teensy, PYNQ, Akida, or Lava/Loihi2
hardware, I want no change to my deploy workflow, so that this feature does
not introduce regressions on hardware targets.

#### Acceptance Criteria

1. THE Studio SHALL NOT call `POST /api/simulators/preflight` or
   `POST /api/simulators/preflight-nir` when a Hardware_Target is selected.

2. THE existing Teensy `_scheduleDeployValidation` logic SHALL remain
   unchanged.

3. THE existing `POST /api/simulators/run` endpoint SHALL remain unchanged;
   it SHALL continue to perform its own internal classification and return
   HTTP 422 for unsupported graphs (the preflight is an additional earlier
   gate, not a replacement).

4. WHEN the user switches from a Simulator_Target to a Hardware_Target, THE
   Pipeline_Bar Deploy step SHALL revert to the generate-status-based
   rendering it uses today.
