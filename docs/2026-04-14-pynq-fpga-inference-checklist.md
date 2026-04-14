# PYNQ Z2 FPGA Inference Execution Checklist

Date: 2026-04-14

This is the execution companion to
`docs/2026-04-14-pynq-fpga-inference-implementation-plan.md`.

Use it as the resume point for implementation.

## Current Truth

- `neurocnl` can export a PYNQ artifact ZIP and hand off to Neurochip.
- Neurochip has a board-hosted PYNQ runtime API and a simulator fallback.
- Real FPGA inference is blocked because the repo does not yet ship a real
  overlay plus manifest that the runtime can load.

## Fixed Decisions

- v1 uses a **fixed overlay**, not generic FINN compilation
- v1 supports:
  - `LIF` only
  - feedforward only
  - static weights only
  - `int8` weights only
  - max `256` neurons
  - max `65536` synapses
  - max `2` populations
- overlay identity:
  - `overlay_id = "snn_overlay_v1"`
  - `overlay_version = "1.0.0"`

## Write Sets

### Root docs

- `docs/2026-04-14-pynq-fpga-inference-implementation-plan.md`
- `docs/2026-04-14-pynq-fpga-inference-checklist.md`

### `neurocnl`

- `contracts/pynq_deployment_contract.py`
- `contracts/pynq_runtime_artifact_contract.py`
- `neurocnl/planner.py`
- `neurocnl/handoff/neurochip_pynq_handoff.py`
- `backend/app/routers/deploy.py`
- `docs/support_matrix.md`

### `Neurochip`

- `neurochip/targets/pynq_z2.json`
- `neurochip/contracts/pynq_runtime_artifact_contract.py`
- `neurochip/app/services/pynq_generator.py`
- `neurochip/app/services/pynq_backend.py`
- `neurochip/app/services/pynq_overlay_assets.py`
- `neurochip/app/routers/pynq.py`
- `hardware/pynq_z2/**`
- `neurochip/overlays/**`

## Ordered Task List

### Task 1. Narrow the software contract to overlay-v1

Definition of done:

- both modules reject networks outside the v1 subset
- payloads include `overlay_id` and `overlay_version`
- support docs stay truthful

Checks:

- `neurocnl` planner tests pass
- PYNQ handoff tests pass
- Neurochip contract tests pass

### Task 2. Define `overlay_manifest.json`

Definition of done:

- one manifest schema exists
- runtime reads it
- generator and backend both consume it

Manifest fields:

- `overlay_id`
- `overlay_version`
- `target_part`
- `dma_ip_name`
- `snn_ip_name`
- `register_map`
- `weight_layout`
- `threshold_layout`
- `supported_weight_bit_widths`
- `supported_neuron_models`
- `max_neurons`
- `max_synapses`

### Task 3. Implement the fixed overlay

Definition of done:

- HLS or RTL source exists in `Neurochip/hardware/pynq_z2/`
- synthesis produces `.bit` and `.hwh`
- manifest is emitted with the same build

Minimum hardware surface:

- AXI4-Lite control block
- AXI DMA input
- AXI DMA output
- threshold storage
- weight storage
- LIF state update

### Task 4. Make preflight validate the installed overlay

Definition of done:

- preflight checks `.bit`, `.hwh`, and manifest
- preflight reports `ok`, `failed`, or `degraded`
- `ok` only when hardware runtime is active and assets are complete

### Task 5. Align deploy payload with runtime layout

Definition of done:

- `overlay_config.json` fields match the overlay's true register and memory map
- `weights.bin` layout matches hardware expectations
- deploy rejects overlay mismatch

### Task 6. Provision a real board

Definition of done:

- board setup steps are scriptable
- Neurochip runs on the board with `-E pynq`
- overlay assets are installed in the canonical location
- host can call `/health`, `/preflight`, `/status`

### Task 7. Add real-board validation

Definition of done:

- one hardware smoke test exists
- one hardware verify test exists
- both assert `runtime_mode == hardware`
- both require `preflight_status == ok`

### Task 8. Only then consider automated compilation

Definition of done:

- a compiler wrapper can emit the same `.bit`, `.hwh`, and manifest contract
- produced assets work with the same deploy/run/verify runtime

## Commands To Reuse Later

Board-side service start:

```bash
cd Neurochip
poetry install -E pynq
poetry run uvicorn neurochip.app.main:app --host 0.0.0.0 --port 8002
```

Host-side readiness checks:

```bash
curl http://<board-ip>:8002/health
curl http://<board-ip>:8002/hardware/pynq/preflight
curl http://<board-ip>:8002/hardware/pynq/status
```

## Acceptance Gate

Do not claim FPGA inference is complete until all are true:

- overlay assets exist
- manifest exists
- preflight returns `ok`
- deploy succeeds on the board
- run succeeds on the board
- verify succeeds on the board
- docs distinguish hardware mode from simulator mode

## Explicit Anti-Goals

Do not:

- start by wiring FINN into the current export ZIP
- keep the current broad PYNQ limits for v1 runtime claims
- rename simulator-backed tests to imply hardware proof
- upgrade the support matrix claim before real-board validation exists

## Next Best First Action

When resuming, start with:

1. add `overlay_manifest.json` schema
2. narrow `neurocnl` and Neurochip PYNQ contracts to overlay-v1
3. implement the fixed overlay hardware tree
