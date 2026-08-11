# Add-Akida-host form crashed on the SSH user field + backend Akida runtime missing

Date: 2026-08-11

## 1. Typing in "SSH user" threw setState-during-build

### Symptom

Studio → Deploy → Manage Akida targets → **Add new target** → type in **SSH user**:

```
setState() or markNeedsBuild() called during build.
This _AddHardwareTargetForm widget cannot be marked as needing to build because the
framework is already in the process of building widgets.
The widget which was currently being built when the offending call was made was:
  _StudioFormField
```

### Root cause

`ZetaTextFormField` (zeta_flutter 1.4.5, `lib/src/interfaces/form_field.dart:69-72`) derives
`initialValue` from `controller.text` **at widget-construction time**:

```dart
super(initialValue: controller != null ? controller.text : (initialValue ?? ''));
```

So on every rebuild, `ZetaTextFormFieldState.didUpdateWidget` (line 108-111) sees
`oldWidget.initialValue != widget.initialValue` and writes
`effectiveController.text = widget.initialValue!` — **during build**. That write dispatches the
controller's listeners, and `_AddHardwareTargetFormState._onAkidaUsernameChanged` called
`setState(() {})` straight from that listener → assertion.

This is the exact hazard already documented in
`nmtk/neuro_toolkit/lib/screens/backend_setup.dart:289-306`; the Studio form had not adopted the
same mitigation.

Second latent instance of the same bug: `_onAkidaHostChanged` writes
`_runtimeApiUrlController.text` / `_controlApiUrlController.text` from inside the host
controller's listener. Reachable once **Advanced settings** is open (those two fields are only
mounted then) — the write makes *those* fields call `setState` during build.

### Fix — `neurocnl/frontend/lib/screens/studio/hardware_target/add_hardware_target_form.dart`

- Service-account warning now lives behind a private `ValueNotifier<bool>
  _usernameIsServiceAccount` rendered by a `ValueListenableBuilder`, and the listener bumps it
  from a post-frame callback. No `setState`, so the text fields are never rebuilt by typing —
  which also stops Zeta's write-back from clearing the caret mid-word.
- `_onAkidaHostChanged` defers the URL derivation to a post-frame callback
  (`_deriveAkidaUrlsFromHost` holds the unchanged body).
- `_serviceUserController` gets the same listener, so changing the service account under Advanced
  settings re-evaluates the warning (it was stale before).

### Regression test

`neurocnl/frontend/test/screens/studio_screen_test.dart` —
"StudioScreen Akida add form takes SSH user keystrokes": types host then SSH user, asserts
`tester.takeException()` is null, and asserts the service-account warning appears while typing.
Helper `_studioFieldFor(label)` added because Zeta renders the label as a sibling of the input,
so `find.widgetWithText` never matches.

Result: `flutter test test/screens/studio_screen_test.dart` → 42/42 pass.
`flutter test test/screens/studio_responsive_audit_test.dart` → 19/19 pass.
`flutter analyze` on both changed files → clean.

## 2. Akida runtime is NOT running on the 192.168.68.53 backend

Probed live:

| Check | Result |
| --- | --- |
| `:9000/api/suite/health` | `ok` |
| `:9000/api/suite/health/modules` | neurocnl / neurosim / neurochip / neurobench / neurosense online; neurohub degraded |
| `:9000/api/neurochip/health` | healthy, proxies hardware to `neurochip-hw-worker:8002` |
| `:9000/api/neurochip/akida/status` | **404** |
| `:9000/api/neurochip/hardware/lava/status` | **404** |
| `:9000/hardware/pynq/status` | 200 |
| `:9000/api/neurochip/hardware/speck/status` | 200 (`sdk_available: false`, reported gracefully) |
| `:9000/api/neurochip/serial/ports` | 200 |
| `:8090/health` (launcher-control) | ok, `akidaHosts: []` |
| `:8090/api/launcher/akida/hosts` | `[]` |

Reading: the hardware worker **is** running (pynq/speck/serial answer), but its akida and lava
routers were skipped at import. `workers/neurochip_hw/main.py:45-49` swallows `ImportError` per
router and logs a warning, so the whole route family simply vanishes with a bare 404.

At HEAD both routers import cleanly with no SDK installed (verified:
`python3 -c "import neurochip.app.routers.akida"` → OK, imports are all first-party and
`AKIDA_AVAILABLE` is guarded in `akida_backend.py:44-50`). So the running image is **stale** —
it predates the modules the current akida router imports (`contracts.akida_model_bundle_contract`,
`services.akida_model_jobs`). Redeploying the backend restores the routes.

Also: zero Akida hosts are paired, consistent with the user wanting to add one.

Not diagnosed further: the worker's own log line naming the failed import. The stack runs as
rootless Podman under the lingering `nmtk-deploy` user (uid 1001) and `sudo` on the host needs an
interactive password, so the container log was unreadable from here.

### Follow-up worth doing

A missing hardware SDK should look like Speck's `sdk_available: false`, not a 404. Consider
mounting a stub `/api/neurochip/akida/status` that reports the import failure when the real router
cannot load, so the app can say *why* the Akida dot is red instead of showing a dead route.
