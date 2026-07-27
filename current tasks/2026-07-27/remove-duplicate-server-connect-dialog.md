# Remove duplicate "connect to server" screen + verify 192.168.2.34 backend

Ask: user saw what looked like 2 setup/server-connect screens, and
"Save & Retry" wasn't connecting for unclear reasons.

## Investigation

`server_setup.dart` being deleted (see [[mobile-server-setup-parity]] from
earlier the same day) looked like a broken mid-refactor state at first —
3 files still reference `ServerSetupScreen`/`ServerSetupMode` with no
matching import. Turned out **not** to be broken: that class was migrated
into `nmtk_ui_core/lib/widgets/server_setup_screen.dart` and re-exported
from the package barrel, which the callers already import. Confirmed via
`flutter analyze` (clean) in both `nmtk_ui_core` and `nmtk/neuro_toolkit` —
no fix needed there.

The real second screen: `tool_view.dart`'s `_showServerDialog` — a
hand-rolled `AlertDialog` behind the "Change Server" FAB, duplicating host
entry/validation/connect logic that already lives in the real
`ServerSetupScreen` flow at `/setup`.

Backend check: `192.168.2.34:8090/health` returned 200 `status: ok` /
`backendDeploymentReady: true` — live and healthy, deployed successfully
~30 min before this check (`deployment_state.json`, target
`"Remote-backend"`). No redeploy needed. Found a second, stale, **failed**
target entry `"MooseRyzen"` for the same host/IP (SSH permission-denied
from 2026-07-21) sitting alongside it — harmless right now since the
newer ready target sorts as "most recent," but a latent footgun.

## Changes — round 1

- `nmtk/neuro_toolkit/lib/screens/tool_view.dart`: deleted
  `_showServerDialog` entirely; its 4 "Change Server" FAB call sites now
  `context.go('/setup')` directly into the real setup screen. Dropped
  now-unused imports (`flutter/services.dart`, `services/ipv4_address.dart`).
- `nmtk/neuro_toolkit/test/tool_view_shell_test.dart`: updated the FAB test
  to expect direct navigation to `/setup` (no dialog, no intermediate
  "Setup New" tap).
- Deleted `nmtk/neuro_toolkit/lib/screens/python_setup.dart` — unrelated
  orphaned dead code (confirmed unreferenced anywhere), duplicated the
  Python-detection UI that's actually wired into
  `first_run_setup_screen.dart`.
- `nmtk/neuro_toolkit/deployment_state.json`: removed the stale
  `"MooseRyzen"` target entry (same host as `"Remote-backend"`, failed SSH
  auth) so there's only one saved target for 192.168.2.34.

## Round 2: the setup form still never appeared

After round 1, `/setup` was reachable directly, but clicking "Set up a new
server" on that screen never revealed the actual provisioning form (This
machine/Remote server/Kubernetes, Standalone/Docker/Podman) — it just sat
there. Root cause, found by reading
`nmtk_ui_core/lib/widgets/server_setup_screen.dart` in full:
`_ServerSetupScreenState._mode` was `late final ServerSetupMode _mode =
widget.initialMode;` — set once, **never reassigned anywhere**, not even
in `didUpdateWidget`. The button's `_handleSetup` only called
`onSetupRequested` (kicks off `LauncherBootstrapNotifier.startLocalSetup()`)
and toggled a loading label; nothing ever flipped `_mode` to
`ServerSetupMode.setup`, so the `AnimatedSwitcher` in `_buildSetupCard`
could never reach the `widget.setupBuilder!(context)` branch through the
button click. The design apparently intended the *parent* to drive this by
passing a new `initialMode`/`openOnBackendStep` after
`startLocalSetup()`, but `InAppFirstRunSetupScreen` (the actual screen
behind `/setup`) derives `openOnBackendStep` from a static route query
param and never watches `launcherBootstrapProvider` at all — it does not
even rebuild when that provider's state changes, so no parent-driven fix
was ever going to reach it.

**Fix** (single file, `nmtk_ui_core/lib/widgets/server_setup_screen.dart`):
made `_mode` mutable and had `_handleSetup` flip it to
`ServerSetupMode.setup` synchronously on tap, firing
`onSetupRequested` in the background instead of gating the reveal on it.
Removed the now-dead `_isPreparingSetup` field/label. Added a regression
test to `nmtk_ui_core/test/server_setup_screen_test.dart` that starts in
connect mode and asserts the setup form appears in the very next frame
after tapping the button (previously untested — the one existing test that
rendered the form constructed the widget directly in setup mode, never
exercising the click transition).

## Verification

`flutter analyze lib/` clean in both `nmtk_ui_core` and `nmtk/neuro_toolkit`.
`flutter test test/tool_view_shell_test.dart` (round 1) and
`flutter test test/server_setup_screen_test.dart` (round 2, 3/3 pass,
including the new regression test) both green. Re-curled
`192.168.2.34:8090/health` after round 1 edits — still 200/ok.
`deployment_state.json` re-parsed as valid JSON with a single remaining
target (`Remote-backend`/`selectedTargetId` unchanged).
