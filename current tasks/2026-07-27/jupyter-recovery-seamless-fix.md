# Make Jupyter recovery seamless instead of a dead-end full redeploy

Ask: a remote deploy came up with Jupyter degraded (`degraded optional
capability: Jupyter is not ready; core services are available.`). User
reported the "Recover Jupyter" / try-again affordance was gone and called
it "highly annoying that such a simple thing is not working."

## Root cause

Two compounding problems:

1. `_recoverJupyter()` (`nmtk/neuro_toolkit/lib/screens/backend_setup.dart`)
   called `BackendDeploymentNotifier.recoverActiveJob()` →
   `ClientDeploymentService.retryJob()` → `deploy()` — a full redeploy
   (SSH connect, re-pull every image, restart every container) just to
   nudge one already-degraded optional service.
2. That button only exists on the transient `/setup` screen. Once the app
   moves into the main NeuroStudio shell, there was no way to retry
   Jupyter at all — `tool_view.dart`'s existing "Retry Start" button for a
   failed module calls `ModuleNotifier.launchModule`, but for a Docker-
   managed, launcher-external service like Jupyter (`startStrategy: "none"`
   in `modules.json`) that only re-probes HTTP health server-side; it can
   never actually restart the container, because launcher-control's own
   Docker Compose service has no docker socket mount and is deliberately
   hardened (`read_only`, `cap_drop: ALL` — `docker-compose.prod.yml:101-111`).
   Only an SSH-capable actor outside that container — i.e. the Flutter app
   itself — can do it.

## Changes

- `nmtk/neuro_toolkit/lib/services/deployment/deployment_service.dart`:
  added `Future<void> retryJupyter(String targetId)` to the
  `DeploymentService` interface.
- `client_deployment_service.dart`: implemented it — SSH-connects to the
  target, runs `docker compose --project-name nmtk -f docker-compose.yml
  -f docker-compose.prod.yml [-f docker-compose.remote.yml] up -d --no-deps
  jupyter-server` (same compose files `install.sh` already uploads/uses,
  just scoped to one service instead of the whole stack), then polls
  `:8008/api/status`. Clears the job's degraded-capability error on success.
- `deployment_notifier.dart`: added `retryJupyter()` on
  `BackendDeploymentNotifier` — resolves the relevant target (from the
  active job, falling back to the most-recently-updated saved target),
  calls the service method, and on failure keeps the
  `degraded optional capability: Jupyter` prefix (with the new failure
  reason appended) so the existing Recover-Jupyter button stays visible for
  another attempt instead of vanishing.
- `backend_setup.dart`: `_recoverJupyter()` now calls the new lightweight
  `retryJupyter()` instead of the old full-redeploy path.
- `tool_view.dart`: `_activateModule` special-cases `moduleId == 'jupyter'`
  to call `backendDeploymentProvider.retryJupyter()` instead of
  `launchModule('jupyter')` — this is the same "Retry Start" button already
  shown for any failed/degraded module, now actually reachable and
  functional for Jupyter from inside the main app, not just `/setup`.
- `test/backend_setup_screen_test.dart`: added a `retryJupyter` stub to the
  `_FakeDeploymentService` (new abstract method).
- `test/backend_setup_completion_test.dart`: the existing "degraded Jupyter
  deployment offers saved-target recovery" test had an empty `targets` list
  in its fixture, so after this change it was passing vacuously (the new
  `retryJupyter()` silently no-ops when it can't resolve a target). Fixed
  the fixture to include a matching target, added a `retryJupyterCalled`
  flag + fake override to the test notifier, and asserted the degraded
  error actually clears on a successful retry.

Deliberately narrow: hardcoding on `moduleId == 'jupyter'` in `tool_view.dart`
is a targeted patch, not a general "any degraded Docker-managed module"
fix — Jupyter is currently the only such module. A real systemic fix would
mean giving launcher-control a way to reach Docker (socket mount or a
sidecar), which is a bigger architecture decision intentionally not made
here. Recorded in gbrain: `project_jupyter_recovery_seamless_fix`.

## Verification

`flutter analyze` clean (same 2 pre-existing, unrelated `pubspec.yaml`
dependency-sort infos as before touching this). `flutter test
test/backend_setup_completion_test.dart test/backend_setup_screen_test.dart
test/services/client_deployment_service_test.dart test/tool_view_shell_test.dart`
— all green. Manual verification against a live degraded-Jupyter deploy
was not re-run in this session — flagged for the user to confirm on next
occurrence (tap "Recover Jupyter" on `/setup`, or "Retry Start" on the
Jupyter tile from inside NeuroStudio, and confirm it comes up without a
full redeploy).
