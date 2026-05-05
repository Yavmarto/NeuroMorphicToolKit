# CNL Studio Hardware Deployment Workflow

This guide describes the current user workflow in `CNL Studio`.

Use this mental model:

- `Studio` is the UI you use
- `Deploy` is the stage where hardware work happens
- `Teensy 4.1 Deploy`, `PYNQ Deploy`, and `Akida Deploy` are embedded Studio workspaces
- you do not need to open a separate `Neurochip` UI for this flow

The only major non-Studio step that still remains is the real physical `Teensy bridge loop` for the
gripper path, which still starts from the terminal.

---

## Before you start

Do the physical setup first.

### All setups

1. Wire the actuator or servo to the Teensy PWM output.
2. Wire the force sensor or FSR to Teensy analog pin `A0`.
3. Plug the Teensy into the machine or host path you will use.

### PYNQ-Z2 additionally

4. Connect the PYNQ board to your network.
5. Record its IP address or hostname.

### Akida additionally

4. Install the Akida PCIe card in a supported Linux or Windows machine.
5. Make sure that machine is reachable over the network if you will use it as a remote host.

---

## Main Studio flow

These are the exact high-level steps to follow in Studio.

1. Open `Studio`.
2. Load or write your `.cnl` spec.
3. Wait for parse and validation to settle.
4. Click the `Deploy` stage in the Studio pipeline.
5. In `Hardware targets`, click the target you want:
   - `Teensy 4.1`
   - `PYNQ`
   - `Akida`
6. If you do not already have a saved target, click `Manage Targets`.
7. In the dialog, click `Add new target`.
8. Fill in the target form and click `Save`.
9. Select the saved target in the dialog.
10. Close the dialog.
11. Use the target workspace below `Hardware targets` to complete readiness, install, and deploy steps.

The rest of this guide explains the exact steps for each target.

---

## Teensy 4.1 path in Studio

### What you click

1. Go to `Deploy`.
2. In `Hardware targets`, click `Teensy 4.1`.
3. Click `Manage Targets`.
4. If needed, click `Add new target`.
5. Fill in:
   - `Display name`
   - `Serial port`
6. Click `Save`.
7. Select the saved Teensy target.
8. Close the dialog.
9. In `Teensy 4.1 Deploy`, choose the bit-width:
   - `8-bit`
   - `16-bit`
   - `32-bit`
10. Click `Check Readiness`.
11. Review the readiness banner, warnings, and any rejection reasons.
12. If readiness looks correct, click `Deploy`.
13. Wait for Studio to move through:
   - `Generating Teensy firmware package`
   - `Flashing Teensy firmware`
   - `Teensy deploy completed successfully`

### What this does today

Current Studio behavior for the Teensy path:

- validates the current spec for the selected Teensy bit-width
- generates the firmware package
- starts the flash flow
- waits for verification feedback

### What to expect

If it works, you should see:

- a success phase banner
- flash progress
- no rejection reasons

If it fails, you should see:

- a failure phase banner
- inline error text
- any rejection reasons or warnings returned by the deployability path

---

## PYNQ path in Studio

### What you click

1. Go to `Deploy`.
2. In `Hardware targets`, click `PYNQ`.
3. Click `Manage Targets`.
4. If needed, click `Add new target`.
5. Fill in:
   - `Display name`
   - `Board host or IP`
   - `SSH username`
   - `SSH port`
   - `Auth mode`
   - `SSH password` or `SSH key path`
   - optional `Runtime API key`
   - optional `Runtime API URL override`
   - optional `Overlay version`
6. Click `Save`.
7. Select the saved PYNQ board.
8. Close the dialog.
9. In `PYNQ Deploy`, confirm the fixed `8-bit` target.
10. Click `Check Readiness`.
11. Review the support-state banner, warnings, and rejection reasons.
12. Click `Install`.
13. Wait for the install step to finish.
14. If needed, click `Check Readiness` again.
15. Once the selected board is ready, click `Deploy`.
16. Wait for the deploy status banner to update.

### What this does today

Current Studio behavior for the PYNQ path:

- validates the current `.cnl` spec for the fixed PYNQ flow
- checks whether the selected remembered board is usable
- installs or prepares the board runtime path
- deploys the validated payload once the board is ready

### What to look for

Healthy signs:

- selected board is shown at the top of `PYNQ Deploy`
- support-state banner is success or warning rather than failure
- deploy status appears after deployment starts

Blocking signs:

- rejection reasons after `Check Readiness`
- selected board is missing
- board never reaches a ready state

---

## Akida path in Studio

### What you click

1. Go to `Deploy`.
2. In `Hardware targets`, click `Akida`.
3. Click `Manage Targets`.
4. If needed, click `Add new target`.
5. Fill in:
   - `Display name`
   - `Host address`
   - `SSH user`
   - `SSH port`
   - `SSH password`
   - `Neurochip runtime URL`
   - `Control API URL`
   - `Remote install root`
   - `Target service user`
6. Click `Save`.
7. Select the saved Akida host.
8. Close the dialog.
9. In `Akida Deploy`, choose:
   - `AKIDA1` or `AKIDA2`
10. Choose bit-width:
   - `1-bit`
   - `2-bit`
   - `4-bit`
11. Click `Check Readiness`.
12. Review the support-state banner, warnings, rejection reasons, and SDK-verification result when present.
13. Click `Install`.
14. Wait for the install step to finish.
15. If needed, click `Check Readiness` again.
16. Click `Deploy`.
17. Wait for the activity line and SDK verification result to update.

### What this does today

Current Studio behavior for the Akida path:

- checks whether the current network can be scaffolded for the chosen Akida version and bit-width
- uses the selected remembered host
- installs or prepares the host path
- generates the deploy package
- runs SDK verification against the selected runtime target

### What to look for

Healthy signs:

- selected host is shown at the top of `Akida Deploy`
- support-state banner is success or warning rather than failure
- `SDK verification passed` appears after a successful deploy path

Blocking signs:

- rejection reasons after `Check Readiness`
- no saved host selected
- SDK verification does not pass

---

## Real gripper loop step

If your goal is a real physical gripper workflow, there is still one manual step outside Studio.

After the Studio deploy flow is complete, start the Teensy bridge loop from the terminal:

```bash
cd Neuro-Dream-Hand
python examples/hardware_teensy_demo/run_hardware_demo.py --port /dev/ttyACM0
```

Replace `/dev/ttyACM0` with the actual serial port for your Teensy.

This is still required today for the real bridge loop path.

---

## Short operator checklists

### Fast Teensy checklist

1. Open `Studio` -> `Deploy`.
2. Select `Teensy 4.1`.
3. Click `Manage Targets`.
4. Add or select the saved serial target.
5. Choose bit-width.
6. Click `Check Readiness`.
7. Click `Deploy`.

### Fast PYNQ checklist

1. Open `Studio` -> `Deploy`.
2. Select `PYNQ`.
3. Click `Manage Targets`.
4. Add or select the saved board.
5. Click `Check Readiness`.
6. Click `Install`.
7. Click `Check Readiness` again if needed.
8. Click `Deploy`.

### Fast Akida checklist

1. Open `Studio` -> `Deploy`.
2. Select `Akida`.
3. Click `Manage Targets`.
4. Add or select the saved host.
5. Choose Akida version and bit-width.
6. Click `Check Readiness`.
7. Click `Install`.
8. Click `Check Readiness` again if needed.
9. Click `Deploy`.

---

## What is still not purely Studio-only

These parts still sit outside the exact click path above:

- physical wiring
- custom FPGA overlay synthesis
- the real Teensy bridge loop command

---

## Summary

If you want the exact current user workflow, do this:

1. work in `Studio`
2. go to `Deploy`
3. choose `Teensy 4.1`, `PYNQ`, or `Akida`
4. use `Manage Targets` to save or pick the hardware target
5. use `Check Readiness`
6. use `Install` when the target provides that step
7. use `Deploy`
8. if you need the real physical Teensy bridge loop, start `run_hardware_demo.py` from the terminal
