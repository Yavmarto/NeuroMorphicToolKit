# Setup screen never advances after backend ready + add quick-connect field

Ask: user ran the standard remote deploy (`make docker-ex-m
REMOTE_HOST=moosebuntu@192.168.2.51`); the pasted log tail ended with
`[nmtk-deploy] Backend and launcher control are ready`, but the app stayed
on the setup screen instead of continuing into NeuroStudio. Separately,
requested a way to connect directly to an already-running server by IP
without going through the full SSH-deploy form.

## Root cause (bug 1)

`install.sh` (`nmtk/neuro_toolkit/assets/deployment/install.sh:50-82`)
verifies suite_api/launcher-control/jupyter readiness itself entirely via
`127.0.0.1` (loopback, from on the deploy host) before writing
`stage=completed` to the status file. `ClientDeploymentService._pollRemoteJob`
(`nmtk/neuro_toolkit/lib/services/deployment/client_deployment_service.dart:458-501`)
reads that status file, and on `stage == completed` re-verifies from
scratch via `_verifyRemoteApis` — hitting the *external* host/IP rather
than loopback. If that external re-check fails for any reason the
loopback check wouldn't hit (firewall, NAT, docker port-publishing), it
throws, the exception propagates out of `fetchJob`, and
`BackendDeploymentNotifier._pollTick`'s generic `catch (_)` just counts
failures — the job's `stage` is never persisted as `completed`, so
`_BackendSetupFormState`'s completion gate (`backend_setup.dart:233-254`)
never fires `onDeploymentReady`, even though install.sh already proved the
backend ready.

## Changes

- `client_deployment_service.dart`: wrapped the `_verifyRemoteApis` call
  inside `_pollRemoteJob` in try/catch. A failure there now downgrades to
  a warning on the job (`error: 'External verification warning: ...'`)
  instead of blocking completion — install.sh's own loopback check is
  trusted, and the real authoritative check
  (`LauncherControlBootstrapService.ensureReady()`, run immediately after
  via `onDeploymentReady -> connectToDeploymentTarget`) still runs against
  the real host and will surface a proper error if it's genuinely
  unreachable.
- `backend_setup.dart`: added a "Already have a server running?" card at
  the top of `BackendSetupForm`, above the existing target/mode/details
  sections — a single host field + Connect button
  (`_buildQuickConnectSection`/`_handleQuickConnect`). On tap it builds a
  minimal `DeploymentTarget` and calls the same
  `widget.onDeploymentReady` callback the full deploy flow uses, which
  reuses `LauncherBootstrapNotifier.connectToDeploymentTarget` (persists
  `launcherControlApiBaseUrl`/`suiteApiBaseUrl`, reruns bootstrap) — no new
  provider plumbing needed. Deliberately placed on the single `/setup`
  screen rather than a new dialog, per
  [[remove-duplicate-server-connect-dialog]] which intentionally removed
  a duplicate host-entry `AlertDialog` elsewhere in favor of this one flow.
  Field label kept short ("Server host or IP") after a mobile-viewport
  (390px) `RenderFlex` overflow with a longer label surfaced via the
  existing mobile test harness.
- `test/backend_setup_screen_test.dart`: added a widget test asserting the
  quick-connect card renders and calls `onDeploymentReady` with a
  `DeploymentTarget` carrying the entered host.

## Verification

`flutter analyze` clean (2 pre-existing, unrelated `pubspec.yaml`
dependency-sort infos only). `flutter test test/backend_setup_completion_test.dart
test/backend_setup_screen_test.dart test/services/client_deployment_service_test.dart`
— all green (7 tests total, including the new quick-connect test and both
mobile-viewport variants). Manual verification against a live remote
deploy (the SSH/status-file polling path) was not re-run in this session —
flagged for the user to confirm against `moosebuntu@192.168.2.51` on next
deploy.

**Correction:** the user's standard run/test command changed the same day
(uncommitted `AGENTS.md` edit) to plain `flutter run -d macos` from
`nmtk/neuro_toolkit` — `make docker-ex-m` is deprecated. See
[[reference_deploy_command]]. To exercise the quick-connect field: run
`flutter run -d macos`, land on `/setup` (no backend found by default),
then use "Already have a server running?" to connect to `192.168.2.51`
directly.
