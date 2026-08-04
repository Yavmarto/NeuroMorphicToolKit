# Mobile Setup step feature parity + embedded connection dot stuck red

Plan file: `~/.claude/plans/i-need-you-to-shimmying-fog.md`

## Part A — Mobile Setup step parity
`neurocnl/frontend/lib/screens/studio/steps/setup_step.dart`:
- Added "Load from server" row to the mobile Workspace section (was fully implemented but unreachable on mobile). Fixed `_ServerWorkspacePickerDialog`'s hardcoded 640px width, which would have overflowed at phone width (same fix `_HubWorkspacePickerDialog` already had).
- Extracted the duplicated `MaterialBanner` block into one `_errorBanner()` helper; used it at both desktop sites (now via spread) and two new mobile sites — `_workspaceError` and `_downloadError` were previously set on failure but never rendered on mobile (silent failures).
- Reused `_buildSelectedPlatformsList()` (already layout-agnostic) directly in the mobile layout, right after the "Target platform" row — this closes three gaps at once: "Manage Targets" (akida/sc_neurocore_fpga), the per-target reachability dot, and per-target quick-remove, none of which existed on mobile before.
- Added a busy spinner to the "Import from device" row while `_isImportingDataset` is true (desktop already had one).

## Part B — Embedded connection dot stuck red
Root cause: `NeurocnlStudioApp._bootstrap()` (`neurocnl/frontend/lib/app.dart`) persisted the launcher-supplied `initialServerUrl` but never called `checkConnection()` against it, so `serverConfigProvider`'s status stayed `ConnectionStatus.unknown` (red dot) forever in embedded mode, regardless of whether the backend was reachable. `didUpdateWidget` also ignored a changed `initialServerUrl`.

- Converted `NeurocnlStudioApp`/`_NeurocnlStudioAppState` to `ConsumerStatefulWidget`/`ConsumerState`.
- `_bootstrap()` now fires an unawaited `checkConnection(url)` after persisting the URL (fire-and-forget so the 5s health-check timeout doesn't stall the boot spinner).
- `didUpdateWidget` now detects a changed `initialServerUrl` and re-checks it (without remounting the router).
- Rejected re-keying `tool_view.dart`'s `KeyedSubtree` (the other candidate fix) — `NeurocnlShellAdapter` owns neurocnl's entire `ProviderScope` below that key, so that would wipe the whole workspace/canvas/pipeline state on every reconnect.
- Defense in depth in `studio_step_drawer.dart`: the embedded tap handler now re-checks the connection after the launcher's popup closes (not just standalone), and `_recheckConnection` now checks the *actual current* URL instead of hardcoding the default.

## Tests
- New `test/app_server_url_sync_test.dart`: mounting with `initialServerUrl` moves status off `unknown`; updating `initialServerUrl` on an already-mounted app re-checks the new URL.
- Extended `test/screens/studio_mobile_step_drawer_test.dart`: drawer dot color matches `serverConfigProvider` state (connected → `healthyColor`, failed → `errorColor`).
- Extended `test/screens/studio_responsive_audit_test.dart`: "Load from server" reachable + picker doesn't overflow; workspace error banner surfaces and dismisses on mobile; "Manage Targets"/reachability dot/quick-remove reachable on mobile; dataset-import spinner shows on mobile. Also corrected a stale comment/title claiming "Manage Targets is desktop-only".

## Verification
- `flutter analyze`: no new issues (same 51 pre-existing, unrelated).
- `flutter test`: 1678 passing (was 1670; +8 new), same 4 pre-existing unrelated failures (FPGA/Akida deploy-target-form tests, a file-picker `setUpAll`).
