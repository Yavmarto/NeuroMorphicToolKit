# Integrate Hub, Sim, and Bench Into Launcher — Remove Module/Server Exposure From Frontend

## Owner

- `F2` Full-workspace local agent preferred

## Depends on

- `issues/04-launcher-modules-surface-and-install-start-semantics.md`
- `nmtk_ui_core/issues/03-shell-chrome-overhaul.md`
- `nmtk_ui_core/issues/04-loading-screen-backend-readiness.md`

## Unlocks

- `issues/05-neurohub-reposition-as-sharing-space.md`

## Write scope

- `nmtk/neuro_toolkit/lib/**`
- `nmtk/neuro_toolkit/assets/modules.json`
- `nmtk_ui_core/lib/**`

## Background

Currently the launcher exposes module server details (port numbers, install status, start/stop
controls) to the user. The principle driving this issue is **"it just works"**: services run
in the background and the user never needs to think about them. Neurohub (sharing), Neurosim
(canvas, now merged into NeuroStudio), and Neurobench (benchmarking) should appear in the
launcher as first-class navigation destinations — not as services the user manages.

## Tasks

### Remove module/server management from the frontend
- Remove the modules management surface: the cards showing install state, port numbers,
  start/stop buttons, and log panels that are currently visible to end users.
- Move any operational monitoring (logs, health status) to a **developer/debug panel** that is
  hidden behind a `Settings → Developer → Show module internals` toggle, off by default.
- The loading screen (`nmtk_ui_core/issues/04`) handles startup readiness; the user's mental
  model is simply "the app is loading" rather than "services are starting".

### Integrate Neurohub (Sharing) as a first-class destination
- Add a **Share** rail entry in the launcher that navigates directly into the Neurohub sharing
  surface (see `issues/05-neurohub-reposition-as-sharing-space.md`).
- The rail entry should light up / show a badge when new shared content is available (via a
  lightweight poll of `GET /api/neurohub/feed/unread-count`).

### Integrate Neurosim (NeuroStudio Canvas) as a first-class destination
- Neurosim is merged into NeuroStudio (`neurocnl`) per `merge-cnl-sim.md`.
- Ensure the launcher rail entry for NeuroStudio is present and routes into the unified app
  (CNL editor + canvas tabs).
- Remove any separate Neurosim launcher entry if it still exists after the merge.

### Integrate Neurobench as a first-class destination
- Add a **Bench** rail entry in the launcher that navigates into the Neurobench job-setup and
  results UI.
- The Bench entry should show a badge with the count of running/queued jobs if > 0.

### Update `modules.json` and launcher models
- Ensure `modules.json` entries for `neurocnl` (NeuroStudio), `neurohub` (Share), and
  `neurobench` (Bench) have:
  - Correct `name` (display name shown in rail).
  - `required: true` for any module that blocks the loading screen.
  - `hasFrontend: true` so the launcher knows to show a nav destination.
- Run launcher doctor after any `modules.json` change:
  ```bash
  python3 scripts/launcher_control_service.py --doctor --json
  ```
- Update launcher Dart models and tests to match any schema changes.

## Done when

- No module install/port/start-stop controls are visible to a non-developer user.
- Share (Neurohub), NeuroStudio (neurocnl+Neurosim), and Bench (Neurobench) all appear as
  first-class rail destinations.
- Badge counts update for Share (unread) and Bench (queued jobs).
- Launcher doctor reports `fatalCount: 0`.
- `cd nmtk/neuro_toolkit && flutter test` passes.

## Validation

- `cd nmtk/neuro_toolkit && flutter test`
- `python3 scripts/launcher_control_service.py --doctor --json` → `fatalCount: 0`
- Manual: launch the app as a non-developer → confirm no server controls visible → confirm all
  three destinations reachable from the rail.
- Manual: toggle `Settings → Developer → Show module internals` → confirm operational panels
  appear.
