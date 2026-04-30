# Loading Screen — Wait For Backend Readiness Before UI Appears

## Owner

- `F2` Full-workspace local agent preferred

## Depends on

- `nmtk_ui_core/issues/03-shell-chrome-overhaul.md`
- `issues/03-launcher-workspace-host-and-persistent-sessions.md`

## Can run in parallel with

- `nmtk_ui_core/issues/05-validation-ux-improvements.md`

## Write scope

- `nmtk_ui_core/lib/**`
- `nmtk_ui_core/test/**`
- `nmtk/neuro_toolkit/lib/**` (launcher boot sequence)

## Background

The UI currently launches and renders the workspace before the backend services are ready,
causing error banners, blank panels, or failed API calls on first load. The user should see a
polished loading screen (not a spinner-on-white) that blocks entry into the workspace until all
required backend modules have reported healthy. This turns a confusing error-prone boot into a
clean, intentional "warming up" moment.

## Tasks

- On app start, before routing to any workspace screen, show a full-screen **loading/splash
  screen** that:
  - Displays the NeuroMorphicToolKit logo / wordmark with a smooth entrance animation.
  - Shows a progress indicator that cycles through module names as each one becomes healthy
    (e.g. "Starting NeuroStudio…", "Starting Neurohub…").
  - Polls each module's `/health` endpoint (using the ports from `modules.json`) on a
    configurable interval (default: 1 s, timeout: 30 s).
- Define a `BackendReadinessProvider` (or extend the existing launcher health service) that
  exposes:
  - `ReadinessState.waiting` — polling in progress.
  - `ReadinessState.ready` — all required modules healthy.
  - `ReadinessState.degraded` — one or more optional modules failed; user can proceed.
  - `ReadinessState.failed` — required module(s) timed out; show actionable error + retry.
- On `ready` or `degraded`, animate the loading screen out and route to the last workspace
  destination (or home if no restore point).
- On `failed`, show a human-readable error card (not a stack trace) with a **Retry** button
  that re-runs the health check sequence.
- "Required" vs "optional" module classification lives in `modules.json` as a boolean field
  `required: true/false`; the loading screen only blocks on required modules.

## Done when

- The app never shows a blank or error-state workspace on first launch.
- The loading screen animates in and out cleanly.
- All required backend modules are healthy before the workspace is shown.
- A degraded state (optional module down) shows a non-blocking warning after routing.
- A failed state shows an error card with a retry action.
- `cd nmtk_ui_core && flutter test` passes including a test for each `ReadinessState`.

## Validation

- `cd nmtk_ui_core && flutter test`
- `cd nmtk/neuro_toolkit && flutter test`
- Manual: start the app before backends are up → loading screen shows → backends start →
  loading screen fades out → workspace appears.
- Manual: kill a required backend → retry → loading screen re-polls → workspace unblocked when
  backend returns.
