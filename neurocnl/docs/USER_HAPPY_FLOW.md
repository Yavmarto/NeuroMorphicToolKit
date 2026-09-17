# User Happy Flow — neurocnl Frontend

Last reviewed against the local checkout on 2026-04-12.

This document describes the frontend that is actually present in this repo today. It is intentionally conservative: it distinguishes between controls that are working, controls that are wired but backend-dependent or limited, and controls that are visible but not functional end-to-end in this build.

## Status Terms

- `working`: implemented in the current codepath and supported by local inspection plus relevant tests in this checkout
- `partial`: visible and wired, but backend-dependent, gated, or not freshly verified end-to-end in this environment
- `stubbed`: visible or implied, but currently placeholder-only or known not to complete its advertised workflow

## Current Operator Flow

### 1. First launch goes to Server Setup

On first launch, the app redirects to `/setup` until a backend URL is saved. The first usable path is:

1. Enter or accept the backend URL.
2. Click `Check Connection`.
3. If the backend health check succeeds, click `Save & Continue`.
4. The app routes to the Studio screen at `/`.

Notes:

- The settings gear in the shell also routes back to `/setup`.
- `Save & Return` and `Cancel` appear only when setup is opened from settings, not on first launch.

### 2. Studio is the main working path

The current Studio screen is the most complete frontend path:

1. Load a template with `Templates`, or type directly into the editor.
2. Parse and validate run automatically after a 500 ms debounce.
3. When validation passes, click `Run Simulation`.
4. Review results in the `Parsed Specs`, `Validation`, `Generate`, `Preview`, and `Deploy` panels.
5. Stay in the main Studio pipeline for normal work; legacy `Analysis` and `Hardware` ownership is now embedded under the `Deploy Review & Handoff` section inside `Deploy`.
6. Use `Export` for `.cnl`, local HTML report, Python script, or backend-driven framework exports.

Canonical workflow note:

- `Studio` is the primary owner of pipeline progression and deployment target selection.
- Open `NeuroSim` for visual editing or inspection, then return to `Studio`.
- Open `Neurochip` only after the deployment target is chosen in `Studio`.
- Cross-module ownership for this rule is documented in
  [docs/ADR-claude/0021-studio-neurochip-handoff-contract.md](/NeuroMorphicToolKit/docs/ADR-claude/0021-studio-neurochip-handoff-contract.md).

What is actually present in Studio today:

- Header actions: `Templates`, `Run Simulation`, `Export`
- Pipeline/status bar: `Parse`, `Validate`, `Generate`, `Simulate`, `Deploy`
- A duration slider above the results area
- A syntax-highlighted editor with autocomplete support and a sentence-builder dialog in code
- A parameter panel that extracts numeric values and also exposes presets
- Embedded `Deploy Review & Handoff` tabs for pre-handoff diagnostics and local device preview

Important corrections versus earlier aspirational docs:

- Template loading happens by tapping the template card itself. There is no visible `Use This Template` button in the current widget.
- The pipeline chips are status-linked navigation within the Studio workspace.
- There is no `New Spec` menu action in the current Studio screen.
- Auto-parse and auto-validate are implemented; auto-simulate is not.

### 3. Deploy review now owns subordinate diagnostics and local preview

The Studio workspace no longer restores standalone `Analysis` and `Hardware` panels. Legacy `/deploy`, `/hardware`, and `/analysis` links all land in Studio `Deploy`, where `Deploy Review & Handoff` now owns:

- `Diagnostics`: energy, quantization, and fault-injection review before handoff
- `Local Preview`: serial connectivity and short local telemetry preview before handing execution or live acquisition downstream

Ownership note:

- `Analysis` inside Studio is pre-handoff authoring review, not the owner of target-execution diagnostics.
- `Hardware` inside Studio is local serial and telemetry preview, not the owner of reusable biosignal acquisition.
- `Neurochip` owns execution-specific packaging, flashing, and runtime diagnostics after target handoff.
- `NeuroSense` owns live biosignal acquisition and reusable EMG telemetry artifacts.

## Button Inventory

### Global Navigation

| Screen area | Control | Intended purpose | Current status | Current behavior |
|---|---|---|---|---|
| Shell nav | `Studio` | Open the CNL editor and pipeline | `working` | Routes to `/` |
| Shell nav | Settings gear / `Settings` | Open backend setup | `working` | Routes to `/setup` |
| Pipeline bar | `Parse` | Show parse status and parsed-spec panel | `working` | Clickable inside Studio |
| Pipeline bar | `Validate` | Show validation status and validation panel | `working` | Clickable inside Studio |
| Pipeline bar | `Generate` | Show generation status and generate panel | `working` | Clickable inside Studio |
| Pipeline bar | `Simulate` | Show simulate status and preview panel | `working` | Clickable inside Studio |
| Pipeline bar | `Deploy` | Open deployment review panel | `working` | Clickable inside Studio |

### Server Setup (`/setup`)

| Control | Intended purpose | Current status | Current behavior |
|---|---|---|---|
| URL field | Enter backend base URL | `working` | Stores the value in local config once saved |
| `Check Connection` | Run backend health check | `working` | Uses `serverConfigProvider.checkConnection()` |
| `Save & Continue` | Persist backend URL and enter Studio | `working` | Enabled only after successful connection |
| `Save & Return` | Persist backend URL and return from settings mode | `working` | Only shown when setup is opened after initial configuration |
| `Cancel` | Leave settings without changes | `working` | Only shown in settings mode |

### Studio (`/`)

| Control | Intended purpose | Current status | Current behavior |
|---|---|---|---|
| `Templates` | Open template gallery | `working` | Opens a dialog populated from `/api/templates` |
| Template card tap | Load template into editor | `working` | Replaces editor text, runs parse/validate, applies hardware config |
| Gallery close `X` | Close template dialog | `working` | Dismisses dialog |
| `Run Simulation` | Generate network and run simulation | `working` | Enabled only when validation passes |
| Duration slider | Set simulation duration | `working` | Controls duration passed to `/api/simulate` |
| Editor text input | Edit CNL spec | `working` | Debounced parse/validate reruns after changes |
| Autocomplete selection | Insert matching sentence template | `working` | Implemented in editor controller logic |
| Sentence builder `+` action | Open guided sentence builder | `working` | Present in editor widget code |
| Result tab `Parsed Specs` | Show parse rows | `working` | Empty state until parse data exists |
| Result tab `Validation` | Show L1/L2 results | `working` | Empty state until validation data exists |
| Result tab `Generate` | Show generated graph and artifact summary | `working` | Empty state until generate data exists |
| Result tab `Simulation` | Show simulation dashboard | `working` | Empty state until simulate data exists |

### Studio Export Menu

| Control | Intended purpose | Current status | Current behavior |
|---|---|---|---|
| `Download .cnl` | Save current spec text | `working` | Downloads `spec.cnl` |
| `Export HTML Report` | Save a report of current state | `working` | Builds a local HTML report from current pipeline state |
| `Export Python Script` | Save generated Python/Nengo code | `working` | Works only after `Generate`; downloads `network.py` |
| `Export NeuroML` | Request backend export | `partial` | Calls `/api/export` with `neuroml` |
| `Export C Header` | Request embedded export | `partial` | Calls `/api/export` with `c_header` |
| `Export NengoLoihi` | Request Loihi-oriented script export | `partial` | Calls `/api/export` with `loihi` |
| `Export Lava` | Request Lava script export | `partial` | Calls `/api/export` with `lava` |
| `Export SpiNNaker` | Request SpiNNaker script export | `partial` | Calls `/api/export` with `spinnaker` |
| `Export NIR` | Request NIR artifact export | `partial` | Calls `/api/export` with `nir` |
| `Copy Shareable Link` | Copy a URL that should reopen the same spec | `stubbed` | Copies a `#spec=...` URL, but the app does not currently read that hash on startup |

### Compact Numeric Editing

| Control | Intended purpose | Current status | Current behavior |
|---|---|---|---|
| Number picker action | Rewrite the selected numeric value in the spec | `working` | Appears when the caret is on a numeric literal and updates the spec text after confirmation |
| Keyboard shortcut | Open the compact numeric editor without leaving the keyboard | `working` | `Ctrl/Cmd+E` opens the number editor for the currently selected numeric value |

### Deploy (`/?panel=deploy` or legacy `/deploy`)

| Control | Intended purpose | Current status | Current behavior |
|---|---|---|---|
| Tab `Simulation` | Prosthetic/MuJoCo simulation workflow | `partial` | Backed by `/api/prosthetic/simulate`; UI is real, but depends on backend/runtime availability |
| `Run Simulation` | Start prosthetic simulation | `partial` | Wired through `prostheticSimProvider` |
| MuJoCo parameter sliders/dropdowns | Configure simulation request | `partial` | Update request payload |
| MuJoCo stream panel | Show live MuJoCo frames | `stubbed` | Current widget is an explicit placeholder |
| Tab `Learning` | Sleep training workflow | `partial` | Wired through `learningProvider` and sleep route |
| `Start Training` | Start training job | `partial` | Depends on backend support and current spec |
| Tab `Export` | Crossbar export workflow | `partial` | Depends on training result first |
| `Export` | Export learned weights | `partial` | Disabled until training yields weights |
| Tab `Teensy` | Teensy readiness preview and handoff | `partial` | Auto-validates current spec for Teensy, then routes flashing work into Neurochip |
| Teensy bit-width chips | Choose deployment bit width | `partial` | Updates deploy request |
| `Open Neurochip Teensy Execution` | Continue flashing and runtime verification downstream | `working` | Opens Neurochip directly in the Teensy workspace |

### Hardware (`/?panel=hardware` or legacy `/hardware`)

| Control | Intended purpose | Current status | Current behavior |
|---|---|---|---|
| Serial port dropdown | Select local serial preview port | `partial` | Populated from backend serial endpoint |
| `Refresh ports` | Refresh serial port list | `partial` | Calls `hardwareProvider.refreshPorts()` |
| Baud rate dropdown | Set serial baud rate | `working` | Local UI state only until connect |
| `Connect` | Open serial connection | `partial` | Calls backend hardware connect route |
| `Disconnect` | Close serial connection | `partial` | Calls backend disconnect route |
| `Open NeuroSense Monitor` | Continue live telemetry in NeuroSense | `working` | Opens the downstream monitor workspace directly |
| `Open … in Neurochip` | Continue execution work in Neurochip | `working` | Opens the selected target workspace directly |
| Live sensor chart area | Preview local telemetry before downstream handoff | `stubbed` | Provider polling path is a no-op placeholder; live frames will not populate from current frontend logic |

### Analysis (`/?panel=analysis` or legacy `/analysis`)

| Control | Intended purpose | Current status | Current behavior |
|---|---|---|---|
| Tab `Energy` | Pre-handoff energy review | `partial` | Wired through `/api/prosthetic/energy` |
| `Run Energy Profile` | Request energy analysis | `partial` | Disabled when no spec is loaded |
| Tab `Quantization` | Pre-handoff quantization review | `partial` | Wired through `/api/prosthetic/quantize` |
| Bit-width chips | Choose quantization widths | `working` | Local UI selection |
| `Run Analysis` | Start quantization analysis | `partial` | Depends on backend response |
| Tab `Fault Injection` | Authoring-stage resilience review | `stubbed` | Screen exists, but backend client path is intentionally unavailable |
| Error-rate slider | Choose fault rate | `working` | Local UI state only |
| `Run Fault Injection` | Request fault injection analysis | `stubbed` | `ApiClient.prostheticFaultInjection()` throws `UnsupportedError` in this build |
| `Open … diagnostics in Neurochip` | Continue target-runtime diagnostics downstream | `working` | Opens the selected target workspace directly |

## What Works Reliably Today

- First-run backend setup flow
- Template loading from `/api/templates`
- Debounced parse and validate in Studio
- Generate + simulate from the main Studio screen
- Parse, validation, network, and simulation result panels
- Parameter extraction and preset-driven rewrites
- Local `.cnl`, HTML, and generated Python export actions
- Teensy readiness preview and direct Neurochip handoff

## Known Gaps And Caveats

- `Copy Shareable Link` is not a true working deep-link feature yet. The app writes the URL but does not consume it on load.
- Hardware live sensor streaming is still placeholder-only in the frontend provider.
- The Deploy screen's MuJoCo stream panel is placeholder UI.
- Analysis `Fault Injection` is intentionally nonfunctional in the current API client.
- Advanced diagnostics may remain degraded depending on backend/runtime availability, but Studio now hands execution-specific work directly to `Neurochip` or `NeuroSense` instead of owning it locally.
- Backend-driven export and deploy paths should be treated as backend-dependent, not guaranteed from the frontend alone.

## Verification Basis

This status assessment is based on:

- direct inspection of the current frontend widgets, providers, routes, and backend routers in this checkout
- passing focused frontend verification in `neurocnl/frontend`, including widget, provider, pipeline, API-client, and Teensy deploy tests
- existing in-repo backend tests and readiness docs, including:
  - `neurocnl/docs/PRE_BETA_READINESS_REVIEW.md`
  - `neurocnl/docs/support_matrix.md`
  - `neurocnl/docs/poc_demo_readiness_assessment_2026-04-08.md`

Fresh backend pytest reruns were not completed in this environment because `uv run pytest` attempted to resolve the optional `py-spinnaker2` dependency and failed on Git submodule / SSH access before pytest started.
