# Hardware Testing Procedure

This document describes how to verify Neurochip hardware-facing workflows
without conflating simulator coverage, host-side artifact generation, and
real-board execution.

## Target Distinctions

Neurochip has multiple hardware paths and they do not prove the same thing:

- **Teensy 4.1**: host-generated firmware plus serial flashing
- **PYNQ Z2**: board-hosted FastAPI runtime plus local FPGA control through the
  `pynq` library
- **Akida**: scaffold export plus optional SDK-backed deployment

Do not use the Teensy E2E test as evidence that PYNQ deployment is working.

## PYNQ Z2 Real-Board Validation

For a networked PYNQ Z2, the real-board path is:

1. Install Neurochip on the board with `poetry install -E pynq`.
2. Place `snn_overlay.bit` and `snn_overlay.hwh` under
   `neurochip/overlays/`.
3. Start the Neurochip API on the board:

```bash
cd Neurochip
poetry run uvicorn neurochip.app.main:app --host 0.0.0.0 --port 8002
```

4. From the host, call:

```bash
curl http://<board-ip>:8002/hardware/pynq/preflight
curl http://<board-ip>:8002/hardware/pynq/status
```

Treat the result as follows:

- `ok`: real-board runtime is ready
- `failed`: hardware runtime selected but overlay assets are incomplete
- `degraded`: simulator fallback active; not a real-board proof

5. Only after preflight is `ok`, exercise:

- `POST /hardware/pynq/deploy`
- `POST /hardware/pynq/run`
- `POST /hardware/pynq/verify`

For a full operator-oriented walkthrough, see
`docs/neurochip/pynq_z2_deployment_guide.md`.

## Prerequisites

- `socat`: Used to create virtual serial port pairs.
- `pyserial`: Python library for serial communication.
- `pytest`: Test runner.

## Simulated Teensy Flashing

Since physical Teensy hardware may not always be connected, we use a mock simulator and virtual serial ports.

### 1. Setup Virtual Serial Ports

Run the following command to create a pair of connected virtual serial ports:

```bash
socat -d -d PTY,link=/tmp/ttyV0,raw,echo=0 PTY,link=/tmp/ttyV1,raw,echo=0 &
```

This creates `/tmp/ttyV0` and `/tmp/ttyV1`. Data sent to one will be received by the other.

### 2. Run the Mock Simulator

The mock simulator (`neurochip/tests/mock_teensy.py`) listens on one end of the virtual serial pair and sends an `ACK` response when it receives data.

```bash
python3 neurochip/tests/mock_teensy.py /tmp/ttyV1
```

### 3. Execute the Flash Job

When calling the `flash` API or using `flash_service`, specify `/tmp/ttyV0` as the port. The service will detect the `/tmp/ttyV` prefix and enter simulation mode.

## Automated Verification Suite

The `neurochip/tests/test_hardware_pipeline.py` script automates the full pipeline:
1.  **Quantization**: Simulates weight quantization for a given SNN network.
2.  **Compilation/Export**: Generates the target-specific deployment package (Teensy, Loihi 2, Akida, BrainScaleS, SpiNNaker).
3.  **Flash**: Uploads the generated firmware to the virtual serial port and verifies the response.

To run the suite:

```bash
cd neurochip
PYTHONPATH=.. poetry run pytest tests/test_hardware_pipeline.py
```

What this proves:

- target-specific package generation works
- mock flashing paths work for Teensy
- expected archive contents are present

What this does not prove:

- a PYNQ board ran a real overlay
- a Teensy board executed the generated firmware on physical hardware

## Supported Targets

Verification ensures that the generated zip packages contain the expected files for each hardware profile:

- **Teensy 4.1**: `main.ino`, `platformio.ini`, `network_params.h`, `lif_engine.h`.
- **Loihi 2**: `deploy.py`, `config.json`, `crossbar_weights.bin`.
- **Akida**: `model.json`, `weights.bin`.
- **BrainScaleS**: `config.json`, `params.bin`.
- **SpiNNaker**: `network.py`, `spinnaker.json`.

## Test Interpretation Matrix

- `tests/integration/test_teensy_e2e.py`: cross-module Teensy payload and
  firmware-export contract; not a PYNQ hardware test
- `neurochip/tests/test_pynq_backend.py`: PYNQ backend lifecycle and simulator
  fallback behavior
- `neurochip/tests/test_pynq_sitl_verify.py`: PYNQ verification route and
  report-shape coverage

Only `/hardware/pynq/preflight == ok` plus successful runtime calls on the
board-hosted service should be treated as real PYNQ board validation.
