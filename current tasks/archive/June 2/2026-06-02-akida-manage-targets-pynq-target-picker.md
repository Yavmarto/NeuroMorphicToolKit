# Fix: Akida Manage Targets Error & SC-NeuroCore Hardware Target Selection

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
