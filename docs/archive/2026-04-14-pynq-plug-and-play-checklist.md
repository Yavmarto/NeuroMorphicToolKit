# PYNQ Z2 Plug-and-Play Checklist

Date: 2026-04-14

Companion to:

- `docs/2026-04-14-pynq-plug-and-play-deployment-plan.md`

## Key Conclusion

Real PYNQ inference still needs **some software on the board** because the
local `pynq` library, overlay load, MMIO, and DMA are board-local operations.

What should change is **what** we deploy:

- not the full Neurochip module
- yes to a thin `neurochip-pynq-agent`

## Current Limitation

Today the user is effectively expected to provide a running remote
Neurochip-compatible endpoint manually.

The current UI and handoff logic do not provision the board for them.

## Target UX

Desired user path:

1. Power and network the board
2. Open launcher
3. Pair board
4. Click `Provision`
5. Wait for `Ready`
6. Click `Deploy`
7. Click `Infer`

No manual terminal steps.

## Ordered Work

### 1. Extract the board runtime agent

Done when:

- a minimal `neurochip-pynq-agent` package exists
- it owns only PYNQ runtime routes
- it can load the overlay and run inference locally

### 2. Add board provisioning to launcher control

Done when:

- launcher control can connect to the board
- upload the runtime bundle
- upload overlay assets
- install or update the service
- start and restart the service
- read preflight and status

### 3. Add paired-board state to the launcher

Done when:

- launcher stores paired board metadata
- board selection uses a paired device, not a raw URL field
- users can reprovision and repair from UI

### 4. Add appliance-image support

Done when:

- a prebuilt image path exists
- first-boot pairing works
- stock-user setup is simpler than SSH provisioning

### 5. Integrate with deploy and inference flows

Done when:

- NeuroCNL deploy flow targets a paired board
- launcher exposes provisioning and readiness
- real-board inference can be started without manual board setup

## Write Sets

### Launcher

- paired board model
- provisioning provider
- control-plane actions
- PYNQ UI flow
- preflight and doctor coverage

### Neurochip

- runtime agent package
- shared PYNQ runtime contracts
- install bundle generation
- service unit template
- overlay asset installer

### NeuroCNL

- consume paired-board configuration instead of manual board URL
- keep truthful support claims until real flow is complete

## Acceptance Gate

Do not call it plug-and-play until:

- no manual SSH session is required
- no manual package install is required
- no manual `uvicorn` launch is required
- no manual `.bit/.hwh` copy is required
- launcher preflight reports board readiness correctly
- real-board inference succeeds from the guided flow

## Step-By-Step UI Test Guide

Use this when testing the real launcher-owned PYNQ flow on a board.

### Before You Start

Make sure all of these are true first:

- the PYNQ board is powered on
- the board is on the same network as the machine running NMTK
- you know the board hostname or IP
- you know the SSH username and either the password or SSH key path
- the launcher and launcher control service are running

For most stock images the default SSH username is `xilinx`.

### Happy-Path UI Script

1. Open the NMTK launcher.
2. Open the `PYNQ Z2 Deploy` screen.
3. In `CNL Specification`, paste a known-good PYNQ-compatible spec.
4. Pick the desired weight bit-width.
5. Click `Check Exportability`.
6. Confirm the `Prepare` step turns successful and that the verdict card does not reject the network.
7. In the `Paired Board` card, leave `Remembered board` empty if this is a first-time board.
8. Enter:
   - `Display name`
   - `Board host or IP`
   - `SSH username`
   - `SSH port`
   - `Auth mode`
   - password or `SSH key path`
   - optional `Runtime API key`
   - optional `Overlay version`
9. Click `Pair Board`.
10. Confirm the board now appears in `Remembered board`.
11. Click `Test SSH`.
12. Confirm the board state moves to `Reachable`.
13. Click `Provision Runtime`.
14. Wait for provisioning to finish.
15. If the board state becomes `Overlay Missing`, place the externally built
    `snn_overlay.bit` and `snn_overlay.hwh` files under
    `Neurochip/overlay_staging/pynq_z2/` on the host machine.
16. Click `Install Overlay`.
17. Click `Check Readiness`.
18. Confirm the state becomes either:
   - `Ready`
   - `Degraded Optional Capability`
19. Treat `Ready` as the normal success case.
20. Treat `Degraded Optional Capability` as usable only if the warning is clearly optional.
21. Treat `Provision Failed`, `Error`, or a failed preflight message as blockers.
22. Confirm a `Deployment Package` card is visible after exportability passes.
23. Optionally enable `Run SITL verification after deploy`.
24. Optionally set `Bitstream path override` if this board needs a non-default path.
25. Click `Deploy To Board`.
26. Watch the stepper and confirm the flow advances through:
   - `Prepare`
   - `Deploy`
   - `Monitor`
   - `Verify` when SITL is enabled
27. Confirm `Deployment Status` becomes visible and shows a real job state rather than a blank or fake success.
28. If SITL verification is enabled, confirm the result card shows either `SITL Verification Passed` or `SITL Verification Failed`.

### Recovery Actions To Test

Run these checks after the happy path works:

1. Click `Restart Runtime` and then `Check Readiness` again.
2. Confirm the board returns to `Ready` or `Degraded Optional Capability`.
3. Click `New Pairing` and confirm the form resets cleanly for another board.
4. Re-select the remembered board and confirm its saved metadata is restored.
5. Click `Delete` only on a disposable test pairing and confirm it disappears from `Remembered board`.

### Failure Cases To Test

At minimum, test these UI-visible failures:

1. Enter a bad host or wrong password and confirm `Test SSH` does not produce a fake success.
2. Use a board without overlay assets and confirm the state becomes `Overlay Missing`.
3. Trigger a preflight problem and confirm the UI surfaces it as `preflight failed`, not as a vague generic error.
4. Trigger an optional-capability warning and confirm the UI surfaces it as `degraded optional capability`, not as a hard failure.
5. Try a PYNQ spec that is exportable but not suitable for runtime deployment and confirm the UI stops at export/package guidance instead of pretending the board is ready.

### What To Record During Manual Testing

Capture these details for each test run:

- spec used
- board hostname or IP
- selected auth mode
- whether provisioning was first-time or repeat
- final board state
- preflight status and message
- deploy job status
- SITL result, if enabled
- any exact UI wording that looked misleading

## First Recommended Implementation Step

Start by extracting the board-side `neurochip-pynq-agent`.

That is the dependency that determines the rest of the provisioning and UI
shape.
