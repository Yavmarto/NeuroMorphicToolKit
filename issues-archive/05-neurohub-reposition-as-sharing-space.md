# Neurohub Repositioned As Sharing Space — Remove Module-Hub Role

## Owner

- `M4` Single-repo cloud agent or local module owner with careful review

## Depends on

- `issues/06-integrate-hub-sim-bench-in-launcher.md`

## Can run in parallel with

- `Neurohub/issues/11-neurohub-shell-adapter-and-workflow-restoration.md`
- `Neurohub/issues/12-neurohub-bundle-inspection-and-orchestration-controls.md`

## Write scope

- `Neurohub/frontend/**`
- `Neurohub/neurohub/**` (backend, schema, routing adjustments)
- `nmtk/neuro_toolkit/assets/modules.json` (display name / role metadata)
- `nmtk/neuro_toolkit/lib/**` (launcher role references)

## Background

Neurohub was originally conceived as the **orchestration hub** for all modules — the central
control plane from which users launch, monitor, and connect modules. That role is being
retired: module lifecycle is now handled invisibly by the launcher (see
`issues/06-integrate-hub-sim-bench-in-launcher.md`). Neurohub's remaining unique value is as
a **sharing and collaboration space** — a place where users can:
- Share CNL networks, canvas projects, and bench results with others.
- Browse publicly shared neuromorphic models.
- Sync results to a team workspace or remote repository.

This issue realigns Neurohub's UI and backend to that focused identity.

## Tasks

### Backend
- Remove or deprecate the module-orchestration routes
  (`/api/orchestrate`, `/api/modules/status`, `/api/workflow/trigger`, etc.) from the Neurohub
  FastAPI app. Keep them behind a feature flag (`ENABLE_ORCHESTRATION=false` by default) during
  a transition period rather than hard-deleting, so existing workflow rows in the DB are not
  broken.
- Keep sharing routes: bundle upload/download, public feed, team workspace sync.
- Update `Neurohub/neurohub_spec.md` to reflect the new scope.

### Frontend
- Remove the "Modules" tab / section from the Neurohub Flutter UI.
- Remove any server-status cards, module start/stop controls, and pipeline-builder surfaces
  that belong to the old hub role.
- Rename the top-level navigation entry in the launcher from "Hub" to "Share" (or "Sharing")
  in `modules.json` and the launcher nav rail.
- Replace removed surfaces with:
  - A **Feed** view showing recently shared models (from public Neurohub API).
  - A **My Shares** view for the user's own shared bundles.
  - A **Team** section (stub or live, depending on auth state).

### Launcher / manifest
- Update `nmtk/neuro_toolkit/assets/modules.json`: change the Neurohub entry's `description`
  to reflect the sharing identity.
- Run launcher doctor after the manifest change:
  ```bash
  python3 scripts/launcher_control_service.py --doctor --json
  ```

## Done when

- Neurohub frontend shows no module-management or server-control surfaces.
- Neurohub is labelled "Share" (or "Sharing") in the launcher rail.
- Orchestration routes are gated behind `ENABLE_ORCHESTRATION` flag (not removed yet).
- Sharing feed and my-shares views are present and load data from the Neurohub API.
- Launcher doctor reports `fatalCount: 0`.
- `cd Neurohub/frontend && flutter test` passes.

## Validation

- `cd Neurohub/frontend && flutter test`
- `python3 scripts/launcher_control_service.py --doctor --json` → `fatalCount: 0`
- Manual: open Neurohub → confirm no module cards, no start/stop controls → confirm Feed and
  My Shares are visible.
