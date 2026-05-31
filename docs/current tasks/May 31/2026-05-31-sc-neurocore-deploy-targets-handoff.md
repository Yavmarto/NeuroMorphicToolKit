# SC-NeuroCore Deploy Targets — Layout Fix + Teensy Removal

Date: 2026-05-31
Module: `neurocnl/frontend` (CNL Studio Deploy pane)
Status: Implemented, lib analyzes clean, deploy/dropdown/pipeline tests green.

## Problem

In the Studio Deploy pane the two SC-NeuroCore targets
(`sc_neurocore_sim`, `sc_neurocore_fpga`) fell through the `switch` default
arm in `deploy_target_workspace.dart` and rendered the **Teensy** workspace
(serial-port + bit-width + flash UI). That layout is wrong for both:

- SC-NeuroCore simulation is a software simulator, not a serial device.
- SC-NeuroCore FPGA is an offline RTL/bitstream synthesis path, not a
  flashable USB board.

The request was to fix the layout using a logical SC-NeuroCore shape (verified
against the GitHub repo) and remove the Teensy target entirely from this
surface.

## Source of truth (GitHub `anulum/sc-neurocore`)

The SC-NeuroCore deploy plane emits one artefact per target. Relevant rows:

| Target | Artefact | Source of truth |
|---|---|---|
| FPGA (Xilinx/Intel/Lattice) | SystemVerilog RTL + bitstream | Rust IR → Verilog emitter |
| Python wheel | `sc_neurocore_engine` (maturin) | Rust engine + PyO3 |
| Edge cdylib | `lib*.so` | Rust crate |
| GPU | WGSL shaders | Shared Rust kernels |

FPGA explicitly does not depend on Python/serial at runtime. This matches the
backend note in `neurocnl/runtime/sc_neurocore_simulator.py`: `to_verilog`
(FPGA RTL export) is "intentionally out of scope" for the runtime simulator —
it is a static code-gen step, "surfaced only in the Deploy catalog".

The backend already treats `sc_neurocore_sim` as a first-class simulator:
`/api/simulators/capabilities`, `/preflight`, and `/run` all accept it
(`neurocnl/backend/app/routers/simulators.py`), and node support is defined in
`neurocnl/runtime/nir_support.py`.

## New layout

- `sc_neurocore_sim` → routed to the shared `SimulatorPanel`
  (`initialBackend: 'sc_neurocore_sim'`), exactly like `lava_sim` /
  `snntorch_sim`. Listed under "Software simulators" in the catalog.
- `sc_neurocore_fpga` → new dedicated `_StudioScNeuroCoreFpgaWorkspace`
  (`lib/screens/studio/deploy/sc_neurocore_fpga_workspace.dart`). It is an
  informational, offline RTL surface: states the artefact (SystemVerilog RTL +
  bitstream), source of truth (Rust IR → Verilog emitter), vendor toolchains
  (Xilinx / Intel / Lattice), and a "View NIR Artifact" button reusing the
  existing compiled-artifacts dialog. No serial port, no flash, no device
  pairing.
- The Deploy-target row hides the "Manage Targets" device picker for
  `sc_neurocore_fpga` (and `lava`), since neither has a pairable device.

## Teensy removal

Removed end-to-end from the Studio Deploy surface:

- Catalog entry `teensy` (`deploy_target_catalog.dart`).
- `_StudioTeensyWorkspace` part + file (`deploy/teensy_workspace.dart`, deleted).
- `teensy_deploy_provider.dart` (deleted) and `widgets/teensy_deploy_panel.dart`
  (deleted), plus `test/widgets/teensy_deploy_panel_test.dart` (deleted).
- Teensy branches in `studio_screen.dart`: dialog-data loader, save handler,
  device-select/sync, deploy-validation scheduler, and the `serviceName`
  ternary.
- `StudioTeensyTargetProfile`, `fetchTeensyProfiles`, `saveTeensyProfile`, and
  the `_teensyProfilesKey` in `studio_target_registry_service.dart`.
- Teensy/serial-port plumbing in the hardware-target form + dialog
  (`detectedSerialPorts`, `serialPort`, the serial-port dropdown, the dead
  `_mergeHardwareTargetEntries` helper).
- Default deploy target changed from `teensy` → `pynq`
  (`models/workspace_file.dart`, `providers/workspace_provider.dart` deep-link
  allowlist now includes `sc_neurocore_sim` + `sc_neurocore_fpga`).
- `sc_neurocore_sim` added to the simulator-target sets in
  `screens/studio_screen.dart` and `providers/pipeline_provider.dart`.

### Intentionally NOT removed

- `ApiClient.getTeensyNetworkPayload` and the Neurochip client serial/flash +
  `exportTeensyFirmware` methods. They are still reached by
  `deployToNeurochip` (shared `/deploy/teensy/network` endpoint) used by the
  in-scope `neurochip_handoff_coordinator`. Removing them would force a
  Mockito regen and cross into the Neurochip handoff contract.
- `nmtk_module_contracts` Studio→Neurochip handoff mapping (`teensy41`) and its
  tests. That is the Neurochip module's own hardware contract (Neurochip still
  ships a Teensy workspace); out of scope for the neurocnl Deploy pane.

## Files touched

Frontend lib:
- `lib/screens/studio/deploy/deploy_target_catalog.dart`
- `lib/screens/studio/deploy/deploy_target_workspace.dart`
- `lib/screens/studio/deploy/deploy_workspace_panel.dart`
- `lib/screens/studio/deploy/sc_neurocore_fpga_workspace.dart` (new)
- `lib/screens/studio/deploy/teensy_workspace.dart` (deleted)
- `lib/screens/studio_screen.dart`
- `lib/screens/studio/shared/studio_widgets.dart` (dropped orphan `_StudioInlineError`)
- `lib/screens/studio/hardware_target/add_hardware_target_form.dart`
- `lib/screens/studio/hardware_target/hardware_target_dialog.dart`
- `lib/services/studio_target_registry_service.dart`
- `lib/providers/api_provider.dart`
- `lib/providers/pipeline_provider.dart`
- `lib/providers/workspace_provider.dart`
- `lib/models/workspace_file.dart`
- `lib/providers/teensy_deploy_provider.dart` (deleted)
- `lib/widgets/teensy_deploy_panel.dart` (deleted)

Tests:
- `test/widgets/teensy_lava_workspace_no_section_card_test.dart` →
  renamed to `sc_neurocore_lava_workspace_no_section_card_test.dart`; Teensy
  group rewritten to cover the FPGA RTL workspace.
- `test/widgets/deploy_targets_no_nested_cards_test.dart` (dropdown keys)
- `test/screens/studio_screen_test.dart` (PYNQ default text, removed fake
  `fetchTeensyProfiles`)
- `test/screens/studio_responsive_audit_test.dart` (test name)
- `test/pipeline_provider_exploration_test.dart` (teensy → sc_neurocore_fpga)
- `test/simulator_preflight_provider_test.dart` (target generators/comments)
- `test/widget_test.dart` ('Teensy 4.1 Deploy' → 'PYNQ Deploy')
- `test/governance/zeta_first_audit_test.dart` (comment)
- `test/widgets/teensy_deploy_panel_test.dart` (deleted)

## Verification

- `flutter analyze lib` → clean (remaining 4 issues pre-existing, unrelated).
- `flutter analyze` (full) → no new errors; remaining items are pre-existing
  lints in unrelated files.
- `flutter test` deploy/dropdown/pipeline suites → all green:
  - `sc_neurocore_lava_workspace_no_section_card_test.dart`
  - `deploy_targets_no_nested_cards_test.dart`
  - `pipeline_provider_exploration_test.dart`
  - `widget_test.dart` → "Studio deploy panel is the canonical deployment path".
- `dart format` applied to all changed lib + test files.

### Known pre-existing failures (NOT caused by this change)

Two `studio_screen_test.dart` tests fail with `A Timer is still pending even
after the widget tree was disposed` — "comparison panel shows cached and
uncached files" and "hides cached output after editing reopened file". They
render the `comparison` panel (never the deploy panel) and fail in isolation;
the suite also warns it creates an `HttpClient`. One `widget_test.dart` case,
"Canvas sweep route restores the sweep workspace", fails with a sweep-form
`RenderFlex` overflow — also unrelated to the deploy target.

## Follow-ups / suggestions

- If a Mockito regen is run later, consider also removing the now-unused
  `getTeensyNetworkPayload` once `deployToNeurochip` is migrated off the
  `/deploy/teensy/network` endpoint name.
- The pre-existing comparison-panel pending-timer failures and the sweep
  overflow are worth a separate fix; they predate and are independent of this
  change.
