# CEL-129: Persistent "cannot connect to server" banner survives a recovered connection

## Problem

Reported in CEL-128: the app starts, the green connection icon shows a good
connection, but a "Connection Problem" / "NeuroStudio Problem" banner in the
top-right notification stack still says the backend can't be reached. The
banner is deliberately persistent (`duration: null`) and nothing ever cleared
it once a later request succeeded.

## Root cause (confirmed)

1. `reportHostedFeatureError` (`lib/screens/tool_view/cross_module_navigation.dart`)
   pushed a persistent `NmtkNotification` keyed `hosted-feature-error:connection`
   (or `:authentication`) for **every** failed request from the embedded module.
2. `dismiss()` existed on `NmtkNotificationCenterController` but was never called
   for those keys anywhere in the codebase.
3. `NmtkFeatureLaunchContext` had only `onReportError` — there was no success /
   recovery signal from the module surface, so a stale banner could never be
   cleared.

A cold backend that takes a couple of seconds to become healthy fails the
module's first few requests, the banner appears during the startup race, and —
because nothing reports the later success — it stays even after the connection
recovers.

## Fix

Two changes, in `nmtk_module_contracts` (shared contract) and the launcher:

1. **Recovery signal.** `NmtkFeatureLaunchContext` gains an optional
   `onRecovered` callback (no-op by default). `AdminTokenHttpClient` invokes it
   whenever a request completes without a network failure or a 401/403, and the
   neurocnl providers thread it through. The launcher wires it to
   `clearHostedFeatureError`, which cancels pending cards and dismisses live
   `hosted-feature-error:connection` / `:authentication` banners. The first
   successful request after a failure clears the stale banner.

2. **Startup grace.** Connection/auth reports are now queued for a 5-second
   grace window (`hostedFeatureErrorStartupGrace`) instead of showing
   immediately. A recovery signal inside the window cancels the queued card
   entirely (startup race never shows a banner at all). Only a backend that is
   still failing when the window expires promotes the card; once live, repeat
   reports refresh it in place until a recovery dismisses it. This also keeps a
   genuinely dead backend from silently showing nothing.

## Manual repro / QA note

**Repro (before the fix):**
1. Cold-start the suite backend (`docker compose up -d --force-recreate`, then
   immediately launch the app) so the backend is still warming up for the first
   couple of seconds.
2. Open NeuroStudio while the backend is not yet healthy. A "Connection
   Problem" banner appears.
3. Wait for the backend health check to go green (green connection icon).
   **Bug:** the banner is still there and never goes away.

**Validation (after the fix):**
1. Repeat step 1–2. During the first ~5s the connection error is suppressed; if
   the backend becomes healthy within the window, **no banner ever appears**.
2. If the backend is still failing after the window, the banner appears with a
   "Backend Setup" action (real problem still surfaced).
3. Backend recovers mid-session (e.g. `docker compose restart suite_api`):
   the next successful NeuroStudio request dismisses the banner automatically.
4. Kill the backend while NeuroStudio is open, then bring it back up. The
   banner should appear while it is down and disappear once a request succeeds
   again.
5. Regression checks: the banner still shows for a genuinely dead backend; the
   "Backend Setup" action still opens the server popup; navigation/unexpected
   errors still use the bottom SnackBar.

**Automated coverage added:**
- `nmtk/neuro_toolkit/test/report_hosted_feature_error_test.dart` — recovery
  during the grace window never shows the banner; recovery after the banner is
  live dismisses it (connection and auth); existing banner/SnackBar paths
  preserved (tests pump `hostedFeatureErrorStartupGrace`).
- `nmtk/neuro_toolkit/test/features/neurocnl/services/admin_token_http_client_test.dart`
  — success reports recovery; 401 reports authentication (no recovery); network
  failure reports connection (no recovery); admin-token header still attached.
- `nmtk_module_contracts/test/feature_launch_contract_test.dart` — `onRecovered`
  is wired and defaults to a no-op.

## Files changed

- `nmtk_module_contracts/lib/src/feature_launch_contract.dart`
- `nmtk/neuro_toolkit/lib/features/neurocnl/services/admin_token_http_client.dart`
- `nmtk/neuro_toolkit/lib/features/neurocnl/providers/{api_provider,simulator_provider,neurobench_panel_provider,canvas/sync_provider,server_config_provider}.dart`
- `nmtk/neuro_toolkit/lib/screens/tool_view/cross_module_navigation.dart`
- `nmtk/neuro_toolkit/lib/screens/tool_view/module_surface_builder.dart`

## Verification

- `nmtk_module_contracts`: `flutter analyze` clean; `flutter test` 4/4 pass.
- `nmtk/neuro_toolkit`: `flutter analyze` clean for this change (3 pre-existing
  `app_router.dart` warnings untouched); `flutter test` all pass except 4
  pre-existing failures (`workbench_feature_boundary`, `project_screen`,
  `akida_runtime_reasons`, `flutter_audit_guardrails`) that also fail with this
  change stashed.
