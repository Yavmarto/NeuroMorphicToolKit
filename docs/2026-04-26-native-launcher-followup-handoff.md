# Native Launcher Follow-up Handoff

## Completed in this change

- Launcher sidebar population now comes from the eligible module manifest/runtime state instead of only persisted workspace sessions, which restores NeuroHub and NeuroSense visibility in native mode.
- Launcher module activation now opens a workspace session for visible modules that do not already have one.
- Hosted NeuroSim mode now suppresses nested shell chrome and correctly uses the dark Material theme variant.
- Hosted NeuroChip mode now suppresses nested shell chrome in the launcher surface.

## Validated so far

- `nmtk/neuro_toolkit/test/tool_view_test.dart`
- `Neurosim/frontend/test/widget_test.dart`
- `Neurochip/frontend/test/neurochip_shell_adapter_test.dart`
- Launcher doctor via `bash scripts/run_launcher_guardrails.sh --with-integration` reached `fatalCount: 0` with one pre-existing optional NeuroChip degradation for missing Lava.
- The full guardrail wrapper still exited non-zero because of unrelated existing failures outside this change:
	- `nmtk/neuro_toolkit/test/module_picker_panel_test.dart` hit a RenderFlex overflow rooted in `nmtk_ui_core/lib/widgets/surface_card.dart`.
	- Root integration tests failed to start because Python package `vcr` is not installed in the current environment.

## Remaining blocker

The remaining native-mode gap is the neurocnl one-click handoff flow.

Today neurocnl handoff code is browser-only:

- `neurocnl/frontend/lib/services/platform_helper_web.dart` depends on browser origin and `window.location.assign(...)`.
- `neurocnl/frontend/lib/services/platform_helper_stub.dart` returns `null` for origin and `false` for `openUrl(...)` on native.
- `neurocnl/frontend/lib/services/neurosim_handoff_coordinator.dart`, `neurocnl/frontend/lib/services/neurochip_handoff_coordinator.dart`, and the Akida handoff path all treat missing origin as "handoff unavailable".

I searched both neurocnl and `nmtk_ui_core` for an existing native launcher bridge and did not find one. There is currently no shared callback, service, or host API that lets a hosted child module ask the launcher to open another native module session.

## Recommended next implementation

Implement a small callback-based host navigation bridge in `nmtk_ui_core` and register it from the launcher.

Suggested contract:

1. Add a shared host bridge API in `nmtk_ui_core` that stays state-management-agnostic.
2. Let the launcher register a callback that can open/focus a module id plus optional deep link and restore state.
3. Update neurocnl handoff coordinators/screens to prefer the native host bridge when available.
4. Keep URL handoff as the web fallback.
5. Map the prepared handoff payload into native `deepLink` and/or `restoreState` for NeuroSim and NeuroChip adapters.

## Likely touch points for the next change

- `nmtk_ui_core/lib/` new shared host bridge surface plus barrel export.
- `nmtk/neuro_toolkit/lib/screens/tool_view.dart` or nearby launcher shell wiring to register the bridge.
- `neurocnl/frontend/lib/screens/studio_screen.dart`
- `neurocnl/frontend/lib/services/neurosim_handoff_coordinator.dart`
- `neurocnl/frontend/lib/services/neurochip_handoff_coordinator.dart`
- `neurocnl/frontend/lib/widgets/akida_deploy_panel.dart`
- Any hosted adapter paths in NeuroSim and NeuroChip that need to consume richer restore state.

## Secondary follow-up

I did not make a NeuroHub hosted-shell change in this pass. If NeuroHub still renders launcher-conflicting chrome when embedded, it likely needs the same `showShellChrome`-style hosted-mode split that was added for NeuroSim and NeuroChip.