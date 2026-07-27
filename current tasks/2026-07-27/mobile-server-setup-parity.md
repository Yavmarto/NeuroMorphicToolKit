# Mobile parity for "set up / connect to server"

Ask: make the mobile Flutter build functionally equivalent to desktop for
the first-run "set up and connect to a server" flow.

## Root cause found

`ServerSetupScreen`/`BackendSetupForm`/`FirstRunSetupScreen` are already
100% platform-agnostic widget trees — no `Platform.*`/`MediaQuery`
branching in them. The actual break was one layer down: in
`nmtk/neuro_toolkit/lib/main.dart`, `LauncherBootstrapHost` only overrode
`launcherBootstrapStateProvider`/`controlApiServiceProvider` when
`LauncherBootstrapData.isReady`. During first-run setup
(`isReady == false` but the control API had already been resolved
elsewhere), `BackendSetupForm` read the *ambient, unoverridden*
`controlApiServiceProvider`, which defaults to a hardcoded
`127.0.0.1:<port>` — so "Set up a new server" always talked to a dead
localhost, regardless of what host the user actually connected to. Desktop
was rarely affected because it auto-spawns a local launcher control
service on `127.0.0.1` (see `launcher_control_bootstrap_service.dart`'s
`isNativeDesktop`), which happens to match the hardcoded default. Mobile
has no local option at all (`isNativeDesktop` excludes Android/iOS), so it
was always broken there.

## Changes

- `nmtk/neuro_toolkit/lib/main.dart`: scope the control-API providers
  whenever `data.bootstrapState`/`data.controlApiService` are resolved,
  not only when `isReady`.
- `nmtk/neuro_toolkit/lib/screens/first_run_setup_screen.dart`: hide the
  "Install with Homebrew" button on mobile (`Process.start` isn't
  supported on Android/iOS, and it installs onto the device running the
  app, not the connected launcher host); clarified copy about which
  machine needs Python.
- `nmtk_ui_core/lib/widgets/server_setup_screen.dart`: two bugs found via
  new mobile-viewport tests —
  1. the setup card's "connect first" unavailable-message was dead code
     because the outer conditional already gated on the same
     `setupAvailable` flag that hid the whole section instead of
     explaining it;
  2. the header `Row` had no `Expanded` around its title `Text`, causing
     a `RenderFlex` overflow at phone widths (390px).
- New/extended tests: `nmtk_ui_core/test/server_setup_screen_test.dart`
  (new), `nmtk/neuro_toolkit/test/backend_setup_completion_test.dart`
  (added a phone-viewport (390x844) variant of the existing deploy test).

## Verification

`flutter analyze` clean on all touched files. `flutter test` green for
`nmtk_ui_core` (170/170, excluding one pre-existing unrelated compile
failure in `zeta_test.dart` caused by a `zeta_flutter_theme` API version
mismatch) and for the touched `neuro_toolkit` test files. Two pre-existing,
unrelated failures noticed in the full `neuro_toolkit` suite
(`test/governance/material_icons_audit_test.dart`,
`test/process_manager_test.dart` — the latter flaky under parallel load,
passes in isolation) — neither touches files in this change; left as-is,
out of scope.

Durable notes recorded in gbrain:
`mobile-setup-connect-provider-scoping-fix`.
