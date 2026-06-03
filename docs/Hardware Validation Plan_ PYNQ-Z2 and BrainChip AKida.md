# Hardware Validation Plan: PYNQ-Z2 and BrainChip AKida
## Purpose
Prove that the deploy and inference pipeline runs on physical neuromorphic hardware, not a software simulator. Simulators are the default fallback in Neurochip, so this plan defines hardware-only gates, explicit evidence criteria, and numbered step-by-step procedures for both the in-app (CNL Studio) and CLI paths.
## Files delivered
* `pyproject.toml` registers `golden_path`, `pynq_hardware`, and `akida_hardware` pytest marks plus `asyncio_mode=auto`.
* `.github/workflows/golden-path.yml` adds one automatic software golden-path job and two manually-triggered hardware jobs.
* `tests/integration/test_golden_path_pynq_hardware.py` validates PYNQ-Z2 hardware with preflight, deploy, status, inference, and SITL verification.
* `tests/integration/test_golden_path_akida_hardware.py` validates BrainChip AKida hardware with status, map, inference, and on-device package generation.
## How the system distinguishes hardware from simulator
### PYNQ-Z2
`Neurochip/neurochip/app/services/pynq_backend.py` reports `runtime_mode="hardware"` only when the PYNQ runtime is reachable through the local Python environment or `NEUROCHIP_PYNQ_PYTHON`. The deploy endpoint accepts `require_hardware=true`; if the backend is in simulator mode, it returns HTTP 503 before any deploy can succeed.
### BrainChip AKida
`Neurochip/neurochip/app/services/akida_backend.py` calls `akida.devices()`. A non-empty list returns `runtime_target="hardware"`; an empty list falls back to `runtime_target="akd1000_simulator"`; missing SDK uses `runtime_target="software_fallback"`. After **Map Runtime**, the Studio panel shows a **Runtime target** key-value row that must read `hardware`; the status line reads "Mapped to physical Akida hardware."
## PYNQ-Z2 (sc-neurocore) — Step-by-step validation
### Prerequisites
1. Power on the PYNQ-Z2 board and connect it to the host machine (USB/Ethernet).
2. Ensure `pynq` is importable in the Python environment that runs Neurochip, or set `NEUROCHIP_PYNQ_PYTHON=/path/to/pynq-python`.
3. Install overlay assets into the configured overlay directory: `snn_overlay.bit`, `snn_overlay.hwh`, and `overlay_manifest.json`. Use the launcher's **Install Overlay** step if you have not done this yet.
4. Start the Neurochip backend: `uvicorn neurochip.app.main:app --port 9000`.
### In-app path (CNL Studio → SC-NeuroCore FPGA RTL)
This path compiles the NIR artifact; runtime validation is done via the CLI or API after flashing.
1. Open CNL Studio. Write or load a CNL network spec in the editor.
2. Open the **Validate** panel. Confirm Layer 1, Layer 2, and backend_support all pass (green). If backend_support shows `unsupported`, the network cannot be deployed.
3. Click the **Deploy** tab in the sidebar.
4. Open the **Deploy target** dropdown (top of the panel) and select **SC-NeuroCore (FPGA RTL)**.
5. The workspace shows: artifact type = SystemVerilog RTL + bitstream, source = Rust IR → Verilog emitter.
6. Click **View NIR Artifact** to confirm the compiled NIR graph is present and non-empty.
7. Outside the app: run `sc-neurocore deploy <artifact.nir>` to emit RTL and synthesise the bitstream for the PYNQ-Z2 target.
8. Flash the resulting `.bit` file to the PYNQ-Z2 using Vivado or the PYNQ flash tool.
9. Proceed to the CLI validation steps below to confirm the runtime is using the flashed hardware.
### CLI / API validation (confirms real hardware, not simulator)
Run these after the board is flashed and the Neurochip backend is running in hardware mode.
**Step 1 — Preflight probe** (proves the PYNQ device driver opened successfully):
```warp-runnable-command
curl -s http://localhost:9000/hardware/pynq/preflight | python3 -m json.tool
```
Confirm: `runtime_mode` is `hardware` and `preflight_status` is `ok` or `degraded` (not `failed`). If `runtime_mode` is `simulator`, the board is not detected — check power, cable, and `NEUROCHIP_PYNQ_PYTHON`.
**Step 2 — Deploy with hardware guard** (HTTP 503 = simulator; HTTP 200 = real FPGA):
```warp-runnable-command
curl -s -X POST "http://localhost:9000/hardware/pynq/deploy?require_hardware=true" \
  -H "Content-Type: application/json" \
  -d '{"weights":[0.8,0.2,0.3,0.9],"require_hardware":true}' | python3 -m json.tool
```
Confirm: HTTP 200 and `runtime_mode` is `hardware`. A 503 means no physical PYNQ device was detected.
**Step 3 — Run inference** (output spikes come from FPGA fabric):
```warp-runnable-command
curl -s -X POST http://localhost:9000/hardware/pynq/run \
  -H "Content-Type: application/json" \
  -d '{"input_spikes":[1,0],"timesteps":1}' | python3 -m json.tool
```
Confirm: response contains `output_spikes` (a list) and `execution_time_us > 0`.
**Step 4 — SITL verification** (structured I/O matrix from real FPGA):
```warp-runnable-command
curl -s -X POST http://localhost:9000/hardware/pynq/verify \
  -H "Content-Type: application/json" \
  -d '{"weights":[0.8,0.2,0.3,0.9],"stimulus_cases":[{"label":"zero","input_spikes":[0,0],"expected_output_spikes":null,"timesteps":1},{"label":"ch0","input_spikes":[1,0],"expected_output_spikes":null,"timesteps":1},{"label":"full","input_spikes":[1,1],"expected_output_spikes":null,"timesteps":1}]}' | python3 -m json.tool
```
Confirm: `total_cases` ≥ 1 and each step has `passed: true` and a non-zero `execution_time_us`.
**Step 5 — Automated test suite** (full 5-check pass/fail gate):
```warp-runnable-command
export PYNQ_HARDWARE_TEST=true NEUROCHIP_URL=http://localhost:9000
python -m pytest tests/integration/test_golden_path_pynq_hardware.py -m pynq_hardware -v -s
```
All 5 tests must be green. Any simulator fallback causes an explicit FAIL with a hardware checklist.
### CI trigger
Run the **Golden Path CI Gate** workflow manually, enable **Run PYNQ-Z2 hardware tests**. The job uses `runs-on: [self-hosted, pynq-z2]` and sets `PYNQ_HARDWARE_TEST=true`. A pre-check step exits before pytest if the service is not in hardware mode.
## BrainChip AKida — Step-by-step validation
### Prerequisites
1. Plug the BrainChip AKida USB device into the host machine.
2. Install the Akida SDK in the Neurochip Python environment: `pip install akida==2.19.1 tensorflow==2.19.* cnn2snn==2.19.1`.
3. Confirm the device is visible: `python3 -c "import akida; print(akida.devices())"` — must return a non-empty list.
4. Start the Neurochip backend: `uvicorn neurochip.app.main:app --port 9000`.
### In-app path (CNL Studio → Akida workspace)
1. Open CNL Studio. Write or load a CNL network spec.
2. Open the **Validate** panel. Layer 1, Layer 2, and backend_support must all pass.
3. Click the **Deploy** tab.
4. Open the **Deploy target** dropdown and select **Akida**.
5. The Akida Runtime workspace appears. Under it, select or create an Akida host via **Manage Targets**. The host must point to the Neurochip service (e.g. `http://localhost:9000`).
6. Choose the AKida version (AKIDA1 or AKIDA2) and bit-width (4-bit recommended for hardware).
7. Click **Check Readiness**. The status line confirms whether the host can reach the Neurochip backend. If it shows an error, verify the host URL and that the Neurochip service is running.
8. Click **Generate Package**. The backend lowers the CNL spec to an AKida mapped network and generates a deployment ZIP. The panel shows a support-state banner (green = exportable).
9. Click **Map Runtime**. The backend calls `POST /api/neurochip/akida/map` on the host. When complete, two key-value rows appear:
    * **SDK status** — must be `deployable`
    * **Runtime target** — must be `hardware`
   The status line reads: **"Mapped to physical Akida hardware."**
   If Runtime target shows `akd1000_simulator`, the USB chip was not detected. If it shows `software_fallback`, the SDK is not installed.
10. In the **Run input vector** field, type comma-separated inputs matching the first population size (e.g. `1, 0, 0, 0` for a size-4 population).
11. Click **Run Inference**. The panel shows:
    * **Runtime target** — must be `hardware`
    * **Outputs** — the chip's output vector
    * **Telemetry** — fps and power (mW) when exposed by the SDK
    The status line reads: **"Run completed on physical Akida hardware."**
    If it reads "Run completed on AKD1000 simulator.", the physical chip was not in use.
### CLI / API validation (confirms real hardware, not simulator)
**Step 1 — Device probe** (proves the USB chip is enumerated):
```warp-runnable-command
curl -s http://localhost:9000/api/neurochip/akida/status | python3 -m json.tool
```
Confirm: `sdk_available` is `true`, `runtime_target` is `hardware`, and `device_info` contains the chip description string.
**Step 2 — Map to hardware** (invokes `akida.Model.map(device)` on the physical chip):
```warp-runnable-command
curl -s -X POST "http://localhost:9000/api/neurochip/akida/map?bit_width=4" \
  -H "Content-Type: application/json" \
  -d '{"akida_version":"akida1","input_population":"s","populations":[{"id":"s","size":4,"role":"sensory","population_type":"lif","provenance":[],"attributes":{}},{"id":"m","size":2,"role":"motor","population_type":"lif","provenance":[],"attributes":{}}],"connections":[{"source":"s","target":"m","units":2,"weight":0.5,"block_type":null,"provenance":[],"property_provenance":[],"attributes":{}}],"topology_verdict":"faithful","warnings":[],"network_summary":{"n_neurons":6,"n_synapses":8,"n_populations":2,"n_connections":1,"quantization_bits":4},"metadata_provenance":[]}' | python3 -m json.tool
```
Confirm: `runtime_target` is `hardware` and `sdk_status` is `deployable`.
**Step 3 — Run inference** (output from the physical chip):
```warp-runnable-command
curl -s -X POST http://localhost:9000/api/neurochip/akida/inference \
  -H "Content-Type: application/json" \
  -d '{"inputs":[1.0,0.0,0.5,0.0]}' | python3 -m json.tool
```
Confirm: `outputs` is a list and `telemetry` includes `fps` or `power` when the SDK exposes them.
**Step 4 — On-device package** (header confirms hardware was used for packaging):
```warp-runnable-command
curl -sI -X POST "http://localhost:9000/api/neurochip/akida/deploy/mapped?bit_width=4&deployment_mode=on_device" \
  -H "Content-Type: application/json" \
  -d '{"akida_version":"akida1","input_population":"s","populations":[{"id":"s","size":4,"role":"sensory","population_type":"lif","provenance":[],"attributes":{}},{"id":"m","size":2,"role":"motor","population_type":"lif","provenance":[],"attributes":{}}],"connections":[{"source":"s","target":"m","units":2,"weight":0.5,"block_type":null,"provenance":[],"property_provenance":[],"attributes":{}}],"topology_verdict":"faithful","warnings":[],"network_summary":{"n_neurons":6,"n_synapses":8},"metadata_provenance":[]}'
```
Confirm: `X-Akida-Deployment-Mode: on_device` and `X-Akida-Runtime-Target: hardware` appear in the response headers.
**Step 5 — Automated test suite** (full 4-check pass/fail gate):
```warp-runnable-command
export AKIDA_HARDWARE_TEST=true NEUROCHIP_URL=http://localhost:9000
python -m pytest tests/integration/test_golden_path_akida_hardware.py -m akida_hardware -v -s
```
All 4 tests must be green. `runtime_target=akd1000_simulator` or `software_fallback` causes an explicit FAIL with a checklist.
### CI trigger
Run the **Golden Path CI Gate** workflow manually, enable **Run BrainChip AKida hardware tests**. The job uses `runs-on: [self-hosted, akida-hardware]` and sets `AKIDA_HARDWARE_TEST=true`. A pre-check step exits before pytest if the service is not in hardware mode.
## Simulator rejection summary
| Check | Simulator value | Hardware value | How rejected |
| --- | --- | --- | --- |
| PYNQ preflight `runtime\_mode` | `simulator` | `hardware` | assert failure \+ checklist |
| PYNQ deploy `require\_hardware=true` | HTTP 503 | HTTP 200 | pytest\.fail immediately |
| AKida status `runtime\_target` | `akd1000\_simulator` or `software\_fallback` | `hardware` | assert failure \+ checklist |
| AKida map `runtime\_target` | same as above | `hardware` | assert failure |
| AKida on\-device deploy header | anything else | `hardware` | assert failure |
| In\-app Map Runtime status line | "Mapped to AKD1000 simulator\." | "Mapped to physical Akida hardware\." | visible in UI |
| In\-app Run Inference status line | "Run completed on AKD1000 simulator\." | "Run completed on physical Akida hardware\." | visible in UI |
## CI gate behavior
The software golden-path job runs automatically on push and nightly schedules. Hardware jobs never run in ordinary hosted CI; they require manual workflow dispatch and the corresponding self-hosted hardware runner. Each hardware job includes a pre-check step that exits with a clear error before pytest if the service reports simulator mode.
## Definition of done
D3 is complete when: the software golden path passes in CI; and the manually-triggered hardware jobs produce logs showing physical hardware identifiers (`device_info`, `runtime_mode=hardware`, `runtime_target=hardware`), successful inference outputs, and no simulator target values at any step.