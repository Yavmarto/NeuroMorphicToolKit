# PYNQ Z2 Deployment Guide

This guide explains how Neurochip's PYNQ Z2 path works, how to deploy it to a
board that is already on the network, and which tests prove what.

## Mental Model

PYNQ Z2 is not deployed the same way as Teensy 4.1 or BrainChip Akida.

- **PYNQ Z2**: Neurochip runs as a FastAPI service on the board's ARM Linux
  side and uses the local `pynq` Python library to load the overlay, write
  registers, and drive DMA.
- **Teensy 4.1**: the host generates firmware and flashes it over serial.
- **BrainChip Akida**: the host generates a scaffold package and, when the
  Akida SDK is present, maps it through the SDK runtime.

That difference is intentional. The runtime API for PYNQ hardware is local to
the board, so the board is the runtime endpoint instead of a passive artifact
sink.

## What Counts as Real PYNQ Deployment

Neurochip distinguishes **exportable** from **deployable**:

- **Exportable** means the toolkit can produce the PYNQ artifact package
  offline.
- **Deployable** means a real board is reachable, the canonical overlay assets
  are present, and the hardware runtime can load them.

The canonical readiness check is `GET /hardware/pynq/preflight`.

- `ok`: hardware runtime active and both `snn_overlay.bit` and
  `snn_overlay.hwh` are present
- `failed`: hardware runtime active but overlay assets are incomplete
- `degraded`: simulator fallback active; useful for CI and local development,
  but not proof of a real-board run

If preflight returns `degraded`, you are not testing the board.

## Step-by-Step Deployment

### 1. Prepare the board

The PYNQ Z2 should already:

- boot a PYNQ Linux image
- be reachable over the network
- have Python and Poetry available, or another way to install Neurochip's
  Python dependencies

### 2. Copy the Neurochip module to the board

Copy the `Neurochip/` directory to the board with `scp`, `rsync`, or your
preferred transfer method.

### 3. Install Neurochip with the PYNQ extra

On the board:

```bash
cd Neurochip
poetry install -E pynq
```

The `pynq` dependency is optional on purpose. Host and CI environments should
still work without it.

### 4. Stage the board-ready overlay assets on the host

Place these externally built files under
`Neurochip/overlay_staging/pynq_z2/` on the host machine that runs the
launcher:

- `snn_overlay.bit`
- `snn_overlay.hwh`
- optional `overlay_manifest.json`

These files are not committed to the repo because they come from an external
Vivado synthesis flow. Without both files, the runtime can only truthfully
claim simulator-backed PYNQ support.

The launcher's `Install Overlay` action copies the staged host-side package to
`Neurochip/neurochip/overlays/` on the board-hosted runtime.

### 4b. PYNQ runtime interpreter auto-detection

The `install-pynq-agent.sh` bundle script prefers the board's canonical
PYNQ runtime at `/usr/local/share/pynq-venv/bin/python` when it exists
and can `import pynq; import pyxrt`. Using the canonical venv avoids the
"No Devices Found" failure that occurs when a plain `pip install pynq`
runs without the Xilinx-specific `pyxrt` / XRT device-tree glue.

- If the canonical runtime is present, the install script skips creating
  `$PYNQ_VENV_PATH` and points the systemd unit's
  `NEUROCHIP_PYNQ_PYTHON` at the canonical interpreter.
- If it is missing (or `pyxrt` is not importable), the script falls back
  to the isolated `$PYNQ_VENV_PATH` and installs `pynq` with pip.
- Override the probe path via `CANONICAL_PYNQ_PYTHON=/path/to/python` in
  the install environment.
- The resolved interpreter and its source are recorded in
  `install-status.json` as `effectivePynqPython` and `pynqRuntimeSource`
  (`canonical` or `isolated`). These are surfaced via
  `GET /hardware/pynq/status`.

### 5. Start the Neurochip API on the board

Use the current suite port for Neurochip:

```bash
cd Neurochip
poetry run uvicorn neurochip.app.main:app --host 0.0.0.0 --port 8002
```

### 6. Check board readiness from the host

From your workstation:

```bash
curl http://<board-ip>:8002/health
curl http://<board-ip>:8002/hardware/pynq/preflight
curl http://<board-ip>:8002/hardware/pynq/status
```

Only proceed with real-board claims if `/hardware/pynq/preflight` returns
`ok`.

If Neurochip authentication is enabled on the board, include the
`X-API-Key` header on all non-health requests.

If you are using the launcher-owned PYNQ flow, the operator steps are:

1. `Provision Runtime`
2. stage external overlay assets under `Neurochip/overlay_staging/pynq_z2/`
3. `Install Overlay`
4. `Check Readiness`

### 7. Export or hand off a deployable PYNQ payload

The normal host-side flow is:

1. Plan or export from NeuroCNL or another producer.
2. Send the resulting payload to the board-hosted Neurochip service.
3. Let the board-hosted service interact with the FPGA locally.

The PYNQ runtime endpoints are:

- `POST /hardware/pynq/deploy`
- `POST /hardware/pynq/run`
- `POST /hardware/pynq/verify`
- `GET /hardware/pynq/status`
- `GET /hardware/pynq/preflight`

### 8. Deploy the overlay configuration

Call `POST /hardware/pynq/deploy` with:

- `weights`
- optional `config`
- optional `bitstream_path`
- optional `register_map`

This loads the bitstream, configures weights through MMIO, and prepares the
runtime for execution.

### 9. Run inference

Call `POST /hardware/pynq/run` with:

- `input_spikes`
- `timesteps`

This sends stimulus through DMA and returns output spikes plus timing data.

### 10. Run verification

Call `POST /hardware/pynq/verify` after deployment.

This runs the PYNQ verification flow against the currently deployed backend or
against a fresh deployment if weights are included in the request.

Treat this as real-board verification only when preflight is `ok` and the
reported runtime mode is `hardware`.

## What the Tests Actually Prove

### `tests/integration/test_teensy_e2e.py`

This is a **Teensy pipeline** test, not a PYNQ deployment test.

It proves:

- NeuroCNL can validate and hand off a Teensy deployment payload
- Neurochip can turn that payload into a firmware ZIP
- rejection paths behave correctly
- the serial flash and verification APIs have the expected contract shape

It does **not** prove:

- that a PYNQ board ran anything
- that a Teensy board actually ran the generated network
- that FPGA MMIO or DMA executed on real hardware

### `Neurochip/neurochip/tests/test_pynq_backend.py`

This mainly proves:

- backend lifecycle behavior
- error mapping
- overlay-asset readiness checks
- simulator fallback behavior when `pynq` is not installed

By default, this is usually a simulator-backed test.

### `Neurochip/neurochip/tests/test_pynq_sitl_verify.py`

This proves:

- verification report structure
- default and custom stimulus behavior
- expected-output pass or fail logic
- router behavior for `POST /hardware/pynq/verify`

Again, unless the runtime is actually in hardware mode with real overlay
assets, this is simulator-backed validation.

## Recommended Validation Sequence

For a networked PYNQ board, use this order:

1. Confirm the board-side Neurochip service is reachable on port `8002`.
2. Confirm `/hardware/pynq/preflight` returns `ok`.
3. Export or hand off a PYNQ payload.
4. Call `/hardware/pynq/deploy`.
5. Call `/hardware/pynq/run` with known stimulus.
6. Call `/hardware/pynq/verify` for repeatable runtime checks.

Do not use `tests/integration/test_teensy_e2e.py` as evidence that PYNQ
hardware deployment is working. That test exercises the wrong target and the
wrong transport.
