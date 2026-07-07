# Fix: Akida Manage Targets Error & SC-NeuroCore Hardware Target Selection

## Verified Implementation Status (2026-07-04)

**Status: DONE.** Both root causes described in the plan are fixed in the current `neurocnl/frontend` code; the doc's "AWAITING APPROVAL" status line is stale.

Evidence:

- **Bug 1 (Akida Manage Targets dialog never opens on fetch failure):** FIXED. `lib/screens/studio_screen.dart` now has `_handleManageHardwareTarget` (around line 1134) whose `catch (error)` block builds a `_HardwareTargetDialogData` with an empty entry list and `loadErrorMessage: formatDeployError(...)` instead of returning early — the code comment at that call site literally reads `// Open the dialog anyway so the user can see the error and still add a target manually (Bug 1 fix: dialog never silently returns).` `lib/screens/studio/hardware_target/hardware_target_dialog.dart` defines `loadErrorMessage` on `_HardwareTargetDialogData` (line ~245/253) and renders an `NmtkStatusBanner`-style warning when set (line ~72-74), matching the plan's proposed change exactly.
- **Bug 2 (SC-NeuroCore has no PYNQ target picker):** FIXED. `lib/services/studio_target_registry_service.dart` has `fetchPynqBoards()` (line 67) and `savePynqBoard()` (line 82). `lib/screens/studio_screen.dart` wires `'sc_neurocore_fpga'` into `_loadHardwareTargetDialogData` (case at line 461) and the save path (case at line 519), plus device-selection at lines 426/430. `lib/screens/studio/deploy/deploy_workspace_panel.dart` no longer globally suppresses the Manage Targets button for FPGA RTL — it explicitly branches `isFpgaRtl = selectedTarget == 'sc_neurocore_fpga'` (line 78) and renders board-selection content/labels for it (lines 80-89), replacing the old blanket `showManageButton = !isLavaHardware && !isFpgaRtl` suppression. `add_hardware_target_form.dart` has a `'sc_neurocore_fpga'` form case (line 287, `_buildScNeuroCoreForm()`) and target-type-specific handling (line 511).
- **Default PYNQ board auto-select:** present — `_loadDefaultHardwareTargets()` (studio_screen.dart line 392) is called from `initState`-equivalent (line 237) and covers all target types including the newly-wired FPGA case.
- Git history confirms active, iterated work on this exact area post-plan-date: `e1b7c1a6 progress on fixing akida and pynq`, `b25c5fb7 Pynq fix, seems to actually work now`, `4540fbf3 Akida Pynq update`, `73c8f862 akida fix`, `42cabc95 progress on akida deployment`.

**What's still missing:** nothing functionally blocking — the plan's Definition of Done items (dialog opens with warning banner, PYNQ picker present, boards addable/selectable, default auto-select, `flutter test`/`dart analyze` clean) all appear satisfied by the code as it stands today. The only loose end is documentation hygiene: this file's header still says `Status: ⏳ AWAITING APPROVAL`, which should be updated to reflect that the work has since been implemented and merged (the duplicate copy at `current tasks/archive/June 2/2026-06-02-akida-manage-targets-pynq-target-picker.md` was intentionally left untouched per instructions).

---

**Created:** 2026-06-02  
**Module:** `neurocnl/frontend/`  
**Priority:** P1 — Blocks hardware validation path (PYNQ-Z2 & BrainChip AKida)  
**Status:** ⏳ AWAITING APPROVAL

---

## Problem

Two issues in CNL Studio's Deploy panel, both uncovered during the Hardware Validation Plan (`docs/Hardware Validation Plan_ PYNQ-Z2 and BrainChip AKida.md`):

1. **Akida — Manage Targets crashes with "could not reach launcher control service"**  
   Clicking "Manage Targets" for the Akida deploy target makes a `GET http://127.0.0.1:8090/api/launcher/akida/hosts` request to the launcher control service. When the service is unreachable the catch block in `onManageHardwareTarget` shows a snackbar error and returns — the dialog never opens. The user has no way to add or select a host.

2. **SC-NeuroCore (FPGA RTL) — no way to set a target hardware**  
   The "Manage Targets" button is explicitly suppressed (`showManageButton = !isLavaHardware && !isFpgaRtl`) and there is no PYNQ board picker anywhere in the `_StudioScNeuroCoreFpgaWorkspace`. The launcher control service already has full PYNQ CRUD at `/api/launcher/pynq/boards` — it is simply not wired up in the frontend.

---

## Root Causes

### Bug 1
`studio_screen.dart (1225–1241)` — The `onManageHardwareTarget` handler catches any fetch error, calls `_showMessage` (snackbar), and `return`s. The `_HardwareTargetDialog` is never opened.

### Bug 2
- `deploy_workspace_panel.dart (51–54)` — `isFpgaRtl = true` suppresses the button.
- `studio_screen.dart (458–465)` — `_loadHardwareTargetDialogData` has no `'sc_neurocore_fpga'` case.
- `add_hardware_target_form.dart (146–228)` — `_buildTypeSpecificForm` has no `'sc_neurocore_fpga'` case.
- `sc_neurocore_fpga_workspace.dart` — Static text only, no board badge.
- `studio_target_registry_service.dart` — No PYNQ fetch/save methods.

---

## Plan Reference

Warp plan: **"Fix Akida Manage Targets Error & SC-NeuroCore Hardware Target Selection"** (plan ID `29360f47-74f5-4290-ab39-392b387fe8e9`)

---

## Proposed Changes

### Bug 1 — Graceful fallback
- **`hardware_target_dialog.dart`** — Add optional `loadErrorMessage` to `_HardwareTargetDialogData`; show `NmtkStatusBanner` (warning) when set.
- **`studio_screen.dart`** — Catch block constructs `_HardwareTargetDialogData` with empty list + error message instead of returning. Dialog always opens; inline `_saveErrorMessage` already handles save failures.

### Bug 2 — PYNQ target picker
- **`studio_target_registry_service.dart`** — Add `fetchPynqBoards()` and `savePynqBoard()`.
- **`studio_screen.dart`** — Wire `'sc_neurocore_fpga'` into `_loadDefaultHardwareTargets`, `_loadHardwareTargetDialogData`, `_saveHardwareTarget`.
- **`deploy_workspace_panel.dart`** — Remove `&& !isFpgaRtl` from `showManageButton`.
- **`add_hardware_target_form.dart`** — Add `'sc_neurocore_fpga'` case: Display name, Host, SSH user (`xilinx`), SSH port, Password, Runtime API URL override, Overlay version, Default checkbox.
- **`sc_neurocore_fpga_workspace.dart`** — Accept `selectedDeviceLabel`/`selectedDeviceData` props; show `NmtkKeyValueRow(label: 'Target board', ...)`.

---

## Files Changed

| File | Change |
|---|---|
| `neurocnl/frontend/lib/services/studio_target_registry_service.dart` | Add `fetchPynqBoards`, `savePynqBoard` |
| `neurocnl/frontend/lib/screens/studio_screen.dart` | Error fallback + PYNQ wiring (4 touch points) |
| `neurocnl/frontend/lib/screens/studio/deploy/deploy_workspace_panel.dart` | Re-enable button for `sc_neurocore_fpga` |
| `neurocnl/frontend/lib/screens/studio/deploy/sc_neurocore_fpga_workspace.dart` | Add selected board display |
| `neurocnl/frontend/lib/screens/studio/hardware_target/hardware_target_dialog.dart` | `loadErrorMessage` in dialog data |
| `neurocnl/frontend/lib/screens/studio/hardware_target/add_hardware_target_form.dart` | PYNQ form fields |

No backend changes required.

---

## Definition of Done

- Clicking "Manage Targets" for Akida when the launcher service is down opens the dialog (with a warning banner) instead of showing a snackbar and closing.
- Clicking "Manage Targets" for SC-NeuroCore (FPGA RTL) opens a PYNQ board picker.
- PYNQ boards can be added, edited, and selected; the selected board name appears in the workspace.
- Default PYNQ board auto-selects on app launch.
- `cd neurocnl/frontend && flutter test` passes.
- `cd neurocnl/frontend && dart analyze` passes.
