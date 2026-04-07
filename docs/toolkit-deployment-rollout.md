---
title: "Toolkit Deployment Rollout — Ordered Index, Checkpoints, and Test Plan"
labels: ["toolkit", "integration", "planning", "readme"]
---

# Purpose
This file is the master execution index for moving hardware deployment in the toolkit from fragmented experimentation to usable workflows.

It covers the ordered issue files for:
- Teensy
- PYNQ-Z2
- BrainChip Akida

Each issue already includes ownership guidance via the filename:
- `Opus` = top-tier agent task
- `Sonnet` = second-tier agent task

This README adds:
- the recommended execution order
- concrete checkpoints
- how to test each stage
- step-by-step manual UI acceptance scripts
- when parallel work is safe

# Important Operating Assumption
This rollout is for the **full toolkit**, not NeuroCNL alone.

The intended product shape is:
- NeuroCNL: author, parse, validate, simulate, determine deployability
- Neurochip: package, compile, flash, deploy, runtime interaction
- Neuro-Dream-Hand: optional runtime verification for control/HITL workflows
- Neurobench: optional benchmark/verification hooks where applicable
- NMTK: orchestration and guided multi-module UX

# Environment Guidance
Before implementation or testing, prefer using each module's own expected environment:

- `neurocnl`
  - from repo root:
  - `cd neurocnl`
  - `pip install -e ".[dev]"`
- `Neurochip`
  - from repo root:
  - `cd Neurochip`
  - `poetry install`
- `Neuro-Dream-Hand`
  - from repo root:
  - `cd Neuro-Dream-Hand`
  - `pip install -e ".[dev]"`
- `nmtk`
  - from repo root:
  - `cd nmtk/neuro_toolkit`
  - `flutter pub get`

If a test fails because of missing dev dependencies, fix the environment first before treating it as a code regression.

# Global Rollout Order
The rollout should be executed in this order:

## Block A: Teensy
1. [01-opus-teensy-deployment-contract.md](/Users/yoshimartodihardjo/NeuroMorphicToolKit/issues/01-opus-teensy-deployment-contract.md)
2. [02-sonnet-teensy-validator-enforcement.md](/Users/yoshimartodihardjo/NeuroMorphicToolKit/issues/02-sonnet-teensy-validator-enforcement.md)
3. [03-opus-teensy-neurocnl-to-neurochip-handoff.md](/Users/yoshimartodihardjo/NeuroMorphicToolKit/issues/03-opus-teensy-neurocnl-to-neurochip-handoff.md)
4. [04-sonnet-teensy-neurochip-compile-and-flash.md](/Users/yoshimartodihardjo/NeuroMorphicToolKit/issues/04-sonnet-teensy-neurochip-compile-and-flash.md)
5. [05-sonnet-teensy-deploy-via-toolkit-ui.md](/Users/yoshimartodihardjo/NeuroMorphicToolKit/issues/05-sonnet-teensy-deploy-via-toolkit-ui.md)
6. [06-sonnet-teensy-runtime-verification-handoff.md](/Users/yoshimartodihardjo/NeuroMorphicToolKit/issues/06-sonnet-teensy-runtime-verification-handoff.md)
7. [07-opus-teensy-final-integration-review.md](/Users/yoshimartodihardjo/NeuroMorphicToolKit/issues/07-opus-teensy-final-integration-review.md)

## Block B: PYNQ-Z2
8. [08-opus-pynq-support-semantics.md](/Users/yoshimartodihardjo/NeuroMorphicToolKit/issues/08-opus-pynq-support-semantics.md)
9. [09-opus-pynq-runtime-artifact-contract.md](/Users/yoshimartodihardjo/NeuroMorphicToolKit/issues/09-opus-pynq-runtime-artifact-contract.md)
10. [10-sonnet-pynq-export-alignment.md](/Users/yoshimartodihardjo/NeuroMorphicToolKit/issues/10-sonnet-pynq-export-alignment.md)
11. [11-opus-pynq-neurochip-runtime-core.md](/Users/yoshimartodihardjo/NeuroMorphicToolKit/issues/11-opus-pynq-neurochip-runtime-core.md)
12. [12-sonnet-pynq-neurocnl-to-neurochip-handoff.md](/Users/yoshimartodihardjo/NeuroMorphicToolKit/issues/12-sonnet-pynq-neurocnl-to-neurochip-handoff.md)
13. [13-sonnet-pynq-dream-hand-sitl-verification.md](/Users/yoshimartodihardjo/NeuroMorphicToolKit/issues/13-sonnet-pynq-dream-hand-sitl-verification.md)
14. [14-sonnet-pynq-toolkit-ui.md](/Users/yoshimartodihardjo/NeuroMorphicToolKit/issues/14-sonnet-pynq-toolkit-ui.md)
15. [15-sonnet-pynq-nmtk-orchestration.md](/Users/yoshimartodihardjo/NeuroMorphicToolKit/issues/15-sonnet-pynq-nmtk-orchestration.md)
16. [16-opus-pynq-final-integration-review.md](/Users/yoshimartodihardjo/NeuroMorphicToolKit/issues/16-opus-pynq-final-integration-review.md)

## Block C: Akida
17. [17-opus-akida-support-levels.md](/Users/yoshimartodihardjo/NeuroMorphicToolKit/issues/17-opus-akida-support-levels.md)
18. [18-opus-akida-deployment-contract.md](/Users/yoshimartodihardjo/NeuroMorphicToolKit/issues/18-opus-akida-deployment-contract.md)
19. [19-opus-akida-shared-mapping-layer.md](/Users/yoshimartodihardjo/NeuroMorphicToolKit/issues/19-opus-akida-shared-mapping-layer.md)
20. [20-opus-akida-neurochip-runtime-alignment.md](/Users/yoshimartodihardjo/NeuroMorphicToolKit/issues/20-opus-akida-neurochip-runtime-alignment.md)
21. [21-sonnet-akida-toolkit-ui-and-benchmark-hooks.md](/Users/yoshimartodihardjo/NeuroMorphicToolKit/issues/21-sonnet-akida-toolkit-ui-and-benchmark-hooks.md)
22. [22-opus-akida-final-integration-review.md](/Users/yoshimartodihardjo/NeuroMorphicToolKit/issues/22-opus-akida-final-integration-review.md)

# Parallelization Rules
Use these rules to avoid wasted work:

- Do **not** start UI/orchestration work for a target until the target's contract/support semantics are defined.
- Do **not** start cross-module handoff work until both:
  - the deployability contract exists
  - NeuroCNL validation/planner behavior is aligned with that contract
- Safe parallel work begins after the contract layer is stable.

Safe parallel windows:
- After `01`, `02`, `03`:
  - `04` and `05` can proceed in parallel
  - `06` can start once `04` has stabilized
- After `08` and `09`:
  - `10`, `14`, and partial prep for `13` can proceed
  - `11` stays on the critical path
- After `17` and `18`:
  - `21` can begin with mocked states
  - `19` and `20` remain critical-path top-tier work

# Concrete Checkpoints
These are the minimum exit conditions for each block.

## Teensy Block Checkpoints
### Checkpoint T1: Contract and validation are real
Must be true after `03`:
- NeuroCNL can classify a network as Teensy-deployable or not
- at least one network is accepted
- at least one network is rejected with a clear reason
- a stable payload can be produced for Neurochip

### Checkpoint T2: Compile/flash path is wired
Must be true after `04`:
- firmware generation is callable from the toolkit flow
- serial port listing works
- flash job start/poll works
- upload/compile errors surface clearly

### Checkpoint T3: Product workflow is usable
Must be true after `07`:
- user can author in NeuroCNL
- see deployability status
- trigger Teensy deployment through the toolkit
- optionally run runtime verification

## PYNQ Block Checkpoints
### Checkpoint P1: Semantics are honest
Must be true after `10`:
- toolkit distinguishes `exportable` from `deployable`
- NeuroCNL export emits the agreed artifact structure
- UI and planner can present correct support state

### Checkpoint P2: Runtime is no longer placeholder-only
Must be true after `12`:
- Neurochip runtime core can load/configure/run through a real or simulated backend
- NeuroCNL can hand off deployable artifacts to Neurochip

### Checkpoint P3: Workflow is usable as an early product
Must be true after `16`:
- user can see whether a network is export-only or deployable
- submit deployment through the toolkit
- observe runtime/verification status
- optionally run Dream-Hand SITL verification

## Akida Block Checkpoints
### Checkpoint A1: Product claims are explicit
Must be true after `18`:
- toolkit distinguishes `unsupported`, `exportable_scaffold`, and `sdk_deployable`
- planner and contract enforce that distinction

### Checkpoint A2: Shared mapping exists
Must be true after `20`:
- NeuroCNL can map validated IR into a shared Akida deployment representation
- Neurochip consumes that representation for package generation/runtime

### Checkpoint A3: Workflow is usable and honest
Must be true after `22`:
- user sees real support level in UI
- deployable cases route through Neurochip
- optional benchmark/verification hooks exist
- scaffold-only cases are clearly labeled as such

# How to Test
Do not treat "test" as meaning only unit tests. Each issue should be validated in two ways:

1. automated checks in the module that owns the change
2. manual UI acceptance in the launcher and module frontends

Run the narrow automated checks first, then the UI script that matches the checkpoint you are trying to close.

# Manual UI Acceptance
These are the human step-by-step checks an implementer should run in the UI.

## Shared Launcher Setup Script
Use this before any target-specific manual test.

1. Launch NMTK.
2. Complete onboarding if it appears, then open `Catalog`.
3. Confirm these modules are present in the catalog:
   `CNL Studio`, `NeuroChip`, `NeuroBench`, and `NDH Simulator`.
4. Install the modules needed for the target under test:
   `CNL Studio` and `NeuroChip` are always required.
   `NDH Simulator` is required for Teensy verification and optional PYNQ SITL verification.
   `NeuroBench` is optional for Akida benchmark hooks.
5. Go to `Dashboard`.
6. Click `Start` for each required module.
7. Wait until each module shows `Running` or `Degraded`.
8. Click `Open` for `CNL Studio`.
9. In the first-run `Server Configuration` screen, verify the backend URL, click `Check Connection`, wait for a healthy connection result, then click `Save & Continue`.
10. Confirm the Studio opens on the main editor and the pipeline bar is visible with `Parse`, `Validate`, `Generate`, `Simulate`, `Deploy`, and `Hardware`.

## Current Baseline Reality Check
Run this before changing product claims so the team has a shared baseline.

1. In `CNL Studio`, enter or load a known-good spec.
2. Confirm parse and validation run automatically from the editor flow and the `Parse` and `Validate` steps move to success.
3. Click `Run Simulation` and confirm `Generate` and `Simulate` succeed.
4. Open the `Deploy` route from the pipeline bar.
5. Confirm the screen only exposes the tabs `Simulation`, `Learning`, and `Export`.
6. Confirm there is no end-to-end target chooser for `Teensy`, `PYNQ-Z2`, or `Akida`.
7. Return to the pipeline bar and open `Hardware`.
8. Confirm the screen only supports serial connection, baud rate selection, live sensor data, and `EMERGENCY STOP`.
9. Record this as the baseline if the UI still behaves this way.

## Teensy Manual Acceptance

### Teensy Checkpoint T1
Goal: the Studio can truthfully classify a network as deployable or not before any real flashing flow is attempted.

1. Complete the shared launcher setup.
2. In `CNL Studio`, load a known-good Teensy-compatible spec.
3. Verify the pipeline reaches successful `Parse` and `Validate`.
4. Navigate to the deployment UI for the target under development.
5. Select `Teensy` as the target if a target chooser exists.
6. Confirm the UI shows a positive support state such as `Deployable`, `Supported`, or equivalent.
7. Confirm the UI also shows the mapped constraints that were satisfied.
8. Switch to a known-bad spec that violates a Teensy limit.
9. Confirm parse may still succeed but the deployment status becomes a clear rejection state.
10. Confirm the rejection reason is explicit, actionable, and target-specific.
11. Confirm the user is not offered a misleading flash/deploy action for the rejected case.

### Teensy Checkpoint T2
Goal: the toolkit can reach Neurochip, find a board, and start a compile/flash job with visible progress and errors.

1. Complete the shared launcher setup.
2. Ensure a Teensy board is physically connected over USB.
3. In `CNL Studio`, load a known-good Teensy-compatible spec and reach a positive deployability state.
4. Start the deploy flow and choose `Teensy`.
5. Confirm the UI can discover serial ports or board candidates.
6. Select the correct port or board.
7. Start the compile/flash action.
8. Confirm the UI shows state changes such as `Packaging`, `Generating firmware`, `Compiling`, `Flashing`, and `Completed`, or the equivalent steps.
9. Disconnect the board or choose an invalid port and repeat.
10. Confirm the UI shows a clear infrastructure failure state rather than hanging or silently succeeding.

### Teensy Checkpoint T3
Goal: the end-to-end product workflow is usable by a non-expert without dropping to ad hoc scripts.

1. Complete the shared launcher setup with `NDH Simulator` installed if runtime verification is part of the issue.
2. In `CNL Studio`, write or load a working spec.
3. Confirm the editor, pipeline bar, validation output, and deployment status all stay consistent.
4. Deploy to `Teensy` through the intended toolkit flow.
5. Confirm the user gets a success state and an artifact/job summary at the end.
6. If runtime verification is implemented, start it from the UI or the launcher-guided handoff, not by a hidden one-off command.
7. Confirm runtime status updates are visible and understandable.
8. Trigger one expected failure path such as an unsupported spec or disconnected board and confirm recovery guidance is visible.

## PYNQ-Z2 Manual Acceptance

### PYNQ Checkpoint P1
Goal: the toolkit clearly distinguishes export-only from real deployable support.

1. Complete the shared launcher setup.
2. In `CNL Studio`, load a known-good PYNQ-compatible spec.
3. Open the deployment flow and choose `PYNQ-Z2`.
4. Confirm the UI shows whether the network is `Exportable` or `Deployable`.
5. Confirm the user can inspect why the support level is what it is.
6. Load a spec that should only be exportable.
7. Confirm the UI allows export but does not present the same affordances as a fully deployable case.
8. Confirm the wording does not imply real board execution when only artifact generation is available.

### PYNQ Checkpoint P2
Goal: the runtime path is real enough that the user can submit a deployment and observe execution state.

1. Complete the shared launcher setup.
2. Prepare either a real PYNQ-Z2 board or the agreed simulated backend.
3. In `CNL Studio`, load a deployable PYNQ test case.
4. Start the PYNQ deployment flow.
5. Confirm the toolkit shows the artifact bundle that will be handed off to Neurochip.
6. Submit the deployment.
7. Confirm the UI shows at least these phases or their equivalents:
   `Pack artifact`, `Transfer or load runtime`, `Configure`, `Run`.
8. Confirm success produces a visible job result, runtime summary, or verification summary.
9. Trigger one unsupported mapping case and confirm the failure is reported before the user reaches a fake `Run` state.

### PYNQ Checkpoint P3
Goal: the workflow is usable as an early product, even if still limited.

1. Complete the shared launcher setup with `NDH Simulator` if SITL verification is included.
2. In `CNL Studio`, load one deployable PYNQ case and one export-only PYNQ case.
3. Confirm the UI differentiates them consistently in all relevant screens.
4. Run deployment for the deployable case and confirm end-to-end progress is visible.
5. Run export for the export-only case and confirm the UX clearly stops at export rather than pretending it deployed.
6. If SITL verification exists, launch it through the intended toolkit handoff and confirm the user can read the result.

## Akida Manual Acceptance

### Akida Checkpoint A1
Goal: support levels are explicit and honest.

1. Complete the shared launcher setup.
2. In `CNL Studio`, open the deployment flow and select `Akida`.
3. Test one clearly unsupported spec, one scaffold-only spec, and one intended SDK-deployable spec.
4. Confirm the UI uses distinct states for `Unsupported`, `Exportable scaffold`, and `SDK deployable`, or equally explicit wording.
5. Confirm each state includes a short explanation of what the user can actually do next.
6. Confirm unsupported and scaffold-only cases do not expose misleading full deployment actions.

### Akida Checkpoint A2
Goal: the shared mapping and Neurochip handoff are visible and testable.

1. Complete the shared launcher setup.
2. Load an intended SDK-deployable Akida case.
3. Start the deployment flow.
4. Confirm the UI surfaces the mapped representation, artifact summary, or compatibility summary before handoff.
5. Submit the handoff to Neurochip.
6. Confirm the user can see that Neurochip received the Akida deployment representation rather than an opaque black-box action.
7. Trigger one mapping rejection and confirm the error references the mapping/compatibility layer instead of failing later with an unhelpful runtime error.

### Akida Checkpoint A3
Goal: the product is usable and honest for the cases it supports.

1. Complete the shared launcher setup with `NeuroBench` if benchmark hooks are part of the issue.
2. Verify the three support states from A1 are still presented consistently.
3. Run a supported Akida deployment case end to end.
4. Confirm the final state tells the user whether the model was deployed, packaged only, or benchmarked.
5. If benchmark hooks exist, launch them from the intended UI path and confirm the result is visible without manual spelunking.
6. Confirm scaffold-only cases stop at the scaffold/package stage and say so clearly.

# Automated Test Entry Points
After the manual UI script passes locally, run the narrow automated checks for the changed module and at least one adjacent integration check.

## NeuroCNL Test Entry Points
Useful for contract, planner, exporter, and prosthetic/hardware-adjacent changes:

```bash
cd neurocnl
python3 -m pytest neurocnl/test_planner.py -q
python3 -m pytest neurocnl/export/test_pynq_exporter.py -q
python3 -m pytest neurocnl/generation/test_akida_generator.py -q
python3 -m pytest neurocnl/layers/test_akida_validator.py -q
python3 -m pytest backend/tests/test_export_router.py -q
python3 -m pytest backend/tests/test_hardware_service.py -q
python3 -m pytest backend/tests/test_prosthetic_export.py -q
python3 -m pytest backend/tests/test_prosthetic_hardware.py -q
python3 -m pytest tests/e2e/test_export_and_jobs.py -q
```

Use these when:
- changing planner/deployability semantics
- changing NeuroCNL export contracts
- changing NeuroCNL frontend/backend handoff logic

## Neurochip Test Entry Points
Useful for firmware generation, runtime backends, routers, and flash flows:

```bash
cd Neurochip
poetry run pytest neurochip/tests/test_teensy_generator.py -q
poetry run pytest neurochip/tests/test_flash_service.py -q
poetry run pytest neurochip/tests/test_export_router.py -q
poetry run pytest neurochip/tests/test_export_ws.py -q
poetry run pytest neurochip/tests/test_pynq_backend.py -q
poetry run pytest neurochip/tests/test_routers.py -q
poetry run pytest neurochip/tests/test_targets_router.py -q
```

Use these when:
- changing compile/flash behavior
- changing PYNQ runtime logic
- changing Akida/PYNQ/Teensy deployment APIs

## Neuro-Dream-Hand Test Entry Points
Useful for runtime verification and HITL-adjacent integration:

```bash
cd Neuro-Dream-Hand
python3 -m pytest tests/test_neurodreamhand/test_serial_bridge.py -q
python3 -m pytest tests/test_neurodreamhand/test_hardware_pipeline_smoke.py -q
python3 -m pytest tests/test_neurodreamhand/test_hitl_latency.py -q
python3 -m pytest tests/test_neurodreamhand/test_emg_streamer.py -q
python3 -m pytest tests/test_neurodreamhand/test_emg_encoder.py -q
python3 -m pytest tests/properties/test_hitl_properties.py -q
```

Use these when:
- changing Teensy runtime verification
- changing PYNQ SITL verification
- changing protocol assumptions for hardware-linked flows

## NMTK Test Entry Points
Useful for orchestration and guided multi-module workflow work:

```bash
cd nmtk/neuro_toolkit
flutter test test/module_provider_test.dart
flutter test test/bundle_manager_test.dart
flutter test test/catalog_test.dart
flutter test test/launcher_e2e_test.dart
```

Use these when:
- adding toolkit orchestration
- changing module dependencies
- changing launcher workflow presentation

# Minimum Test Matrix by Issue Type
Use this checklist to avoid under-testing.

## Contract / semantics issue
Must include:
- one accepted case
- one rejected case
- one clear error-reporting assertion

## Handoff / mapping issue
Must include:
- payload shape assertion
- provenance retention assertion if applicable
- one unsupported mapping rejection

## Runtime / deploy issue
Must include:
- happy-path job/run test
- one infrastructure failure path
- one invalid-input or unsupported-target path

## UI / orchestration issue
Must include:
- status rendering
- loading/progress state
- failure state
- at least one end-to-end mocked workflow test

# Suggested Definition of Done
An issue is only done when:
- code is implemented
- the relevant narrow tests pass
- at least one adjacent-module integration check passes
- the user-facing semantics are still honest

# Notes
- Keep the old umbrella issue files as context only; use the numbered files as the implementation sequence.
- Prefer finishing the full Teensy block before moving the team onto deep PYNQ or Akida runtime work.
- If time is limited, the highest-value early product outcome is:
  - complete Teensy usable workflow
  - truthful PYNQ export/deploy distinction
  - truthful Akida support-level UX
