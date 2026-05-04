# PYNQ Z2 FPGA Inference Implementation Plan

Date: 2026-04-14

## Summary

This plan turns the current PYNQ Z2 path from:

- exportable overlay package
- board-hosted runtime API
- simulator-backed verification

into:

- a **real fixed overlay** that runs inference on the PYNQ Z2 FPGA fabric
- a truthful cross-module contract between `neurocnl` and `Neurochip`
- a repeatable board provisioning and validation path

This plan is intentionally **not** a generic FINN-for-arbitrary-SNNs project.
The first deliverable is a **fixed overlay v1** with a narrow supported subset.
Automated FPGA compilation is Phase 2.

## Goal

Make `POST /hardware/pynq/run` perform **real FPGA-backed inference** on a
PYNQ Z2 board when:

- the board-hosted Neurochip service is running
- `pynq` is installed on the board
- the canonical overlay assets are present
- the deploy payload matches the installed overlay contract

## Non-Goals

- Arbitrary SNN-to-bitstream compilation in v1
- Broad topology support in v1
- FINN integration as the first real-hardware path
- Promoting NeuroCNL's `pynq` support claim above `approximate — export only`
  until the hardware path and tests are actually complete

## Chosen Architecture

### Overlay Strategy

Use a **fixed memory-mapped overlay** as v1. Do not start with FINN.

The overlay is:

- `overlay_id = "snn_overlay_v1"`
- one dense feedforward layer engine
- static weights
- synchronous timestep execution
- MMIO control plane
- DMA stimulus input and spike output

### Supported Network Subset for v1

The v1 overlay supports only:

- neuron model: `LIF`
- topology: feedforward only
- learning rules: none
- delays: none
- weight precision: `int8` only
- maximum neurons: `256`
- maximum synapses: `15360`
- maximum populations: `2`
- one dense connection matrix from input population to output population

These numbers are intentionally conservative. They are the overlay contract,
not a theoretical board maximum.

### Runtime Mode Truthfulness

The system must preserve three distinct truths:

- **artifact exportable**: NeuroCNL/Neurochip can produce the package
- **hardware ready**: board runtime active and overlay assets installed
- **hardware verified**: deploy/run/verify succeeded against the real board

Simulator-backed success must never be reported as hardware inference.

## Required Contract Changes

### `neurocnl`

Update the PYNQ-facing contracts and support docs so they describe the overlay
that actually exists.

Write set:

- `neurocnl/contracts/pynq_deployment_contract.py`
- `neurocnl/contracts/pynq_runtime_artifact_contract.py`
- `neurocnl/neurocnl/planner.py`
- `neurocnl/neurocnl/handoff/neurochip_pynq_handoff.py`
- `neurocnl/backend/app/routers/deploy.py`
- `neurocnl/docs/support_matrix.md`

Required changes:

- Replace board-wide generic limits with overlay-v1 limits where the current
  contract implies runtime eligibility.
- Keep the overall `pynq` status as `approximate — export only` until real
  board validation lands.
- Make the deploy payload carry:
  - `overlay_id`
  - `overlay_version`
  - `weight_bit_width`
  - `max_supported_neurons`
  - `max_supported_synapses`
  - exact `register_map` provenance or manifest reference
- Fail closed if the requested network is outside the overlay-v1 subset.

### `Neurochip`

Write set:

- `Neurochip/neurochip/targets/pynq_z2.json`
- `Neurochip/neurochip/contracts/pynq_runtime_artifact_contract.py`
- `Neurochip/neurochip/app/services/pynq_generator.py`
- `Neurochip/neurochip/app/services/pynq_backend.py`
- `Neurochip/neurochip/app/services/pynq_overlay_assets.py`
- `Neurochip/neurochip/app/routers/pynq.py`

Required changes:

- Move from board-generic runtime assumptions to overlay-v1 assumptions.
- Add `overlay_manifest.json` as a required runtime asset alongside `.bit` and
  `.hwh`.
- Generate `register_map.json` and deploy metadata from the overlay manifest,
  not a hardcoded default alone.
- Reject deploy requests whose `overlay_id`, `overlay_version`, neuron limit, or
  bit-width do not match the installed overlay.
- Keep simulator fallback optional and intact for non-board environments.

## Hardware Deliverables

Create a dedicated hardware source tree in `Neurochip`:

- `Neurochip/hardware/pynq_z2/README.md`
- `Neurochip/hardware/pynq_z2/hls/`
- `Neurochip/hardware/pynq_z2/rtl/`
- `Neurochip/hardware/pynq_z2/vivado/`
- `Neurochip/hardware/pynq_z2/scripts/`
- `Neurochip/hardware/pynq_z2/overlay_manifest.json`

### Overlay v1 Definition

The overlay must expose:

- AXI4-Lite control registers:
  - start
  - reset
  - done
  - error
  - input neuron count
  - output neuron count
  - timestep count
  - threshold base pointer or MMIO window
- AXI DMA input stream for spike stimulus
- AXI DMA output stream for spike results
- BRAM or equivalent storage for:
  - weights
  - thresholds
  - membrane state
  - refractory state

### Overlay Manifest

`overlay_manifest.json` must be the hardware source of truth and contain:

- `overlay_id`
- `overlay_version`
- `target_part`
- `supported_neuron_models`
- `supported_weight_bit_widths`
- `max_neurons`
- `max_synapses`
- `dma_ip_name`
- `snn_ip_name`
- `register_map`
- `weight_layout`
- `threshold_layout`

The runtime must read this file during preflight.

## Implementation Phases

### Phase 1. Truthful contracts and payload alignment

Deliverable:

- all software layers describe the same overlay-v1 subset

Steps:

1. Define overlay-v1 limits in both modules.
2. Add `overlay_id` and `overlay_version` to handoff and runtime payloads.
3. Update `neurocnl` planner and deploy route to gate against overlay-v1.
4. Update Neurochip generator and deploy route to validate against the same
   limits.
5. Keep all current user-facing claims at export-only / simulator-backed levels.

Acceptance criteria:

- a network outside overlay-v1 is rejected before runtime deploy
- a payload mismatched to the installed overlay is rejected at deploy time
- docs no longer imply that generic PYNQ Z2 support equals overlay-v1 support

### Phase 2. Real overlay implementation

Deliverable:

- `snn_overlay_v1.bit`
- `snn_overlay_v1.hwh`
- `overlay_manifest.json`

Steps:

1. Implement minimal HLS or RTL LIF engine.
2. Define register layout and DMA protocol.
3. Synthesize for `xc7z020clg400-1`.
4. Produce `.bit`, `.hwh`, and manifest.
5. Install them into `Neurochip/neurochip/overlays/` on the board.

Acceptance criteria:

- `pynq.Overlay()` loads the bitstream on the board
- DMA channels and SNN IP resolve by the expected names
- preflight returns `ok`

### Phase 3. Board-side runtime hardening

Deliverable:

- Neurochip runtime can deploy, run, and verify against the real overlay

Steps:

1. Load overlay assets from the canonical overlay directory.
2. Validate installed manifest against request payload.
3. Write thresholds and weights using the manifest-defined layout.
4. Stream input spikes through DMA.
5. Read output spikes and timing.
6. Expose structured runtime status and error codes.

Acceptance criteria:

- `POST /hardware/pynq/deploy` succeeds on the real board
- `POST /hardware/pynq/run` returns non-empty structured output for known
  stimuli
- `POST /hardware/pynq/verify` passes for golden cases on real hardware

### Phase 4. Real-board testing and operator workflow

Deliverable:

- repeatable real-board validation path

Steps:

1. Add a board provisioning script.
2. Add a board-side service start script.
3. Add a host-side smoke test script.
4. Add explicit real-hardware vs simulator assertions to tests and status
   surfaces.
5. Document the operator workflow in Neurochip docs.

Acceptance criteria:

- a clean board can be provisioned from docs/scripts alone
- hardware-ready and simulator-fallback states are clearly distinguishable
- at least one hardware smoke test and one verification run are documented and
  repeatable

### Phase 5. Phase 2 automated compilation

Deliverable:

- automated overlay generation for the narrow overlay-v1 target

Decision:

- this phase comes after a working fixed overlay
- FINN is optional and must emit the same manifest and runtime contract

Steps:

1. Add a `pynq_compiler` wrapper or build service.
2. Translate validated IR into overlay-v1 synthesis parameters.
3. Invoke Vivado/HLS or FINN-backed build tooling.
4. Emit `.bit`, `.hwh`, and `overlay_manifest.json`.
5. Install or publish those assets into the Neurochip runtime path.

Acceptance criteria:

- a supported network can produce board-loadable overlay assets automatically
- the produced assets match the same runtime contract used by the fixed overlay

## Tests and Verification

### `neurocnl`

Required tests:

- planner rejects networks outside overlay-v1
- deploy endpoint returns truthful exportability results
- handoff payload includes overlay metadata
- support-matrix and docs are aligned with current truthfulness boundary

### `Neurochip`

Required tests:

- overlay-manifest parsing
- deploy request rejection on overlay mismatch
- MMIO write layout matches manifest
- DMA input/output shape tests
- preflight `ok` / `failed` / `degraded` behavior

### Real-board tests

Add a hardware-only suite that requires:

- `runtime_mode == hardware`
- `preflight_status == ok`
- deployed overlay manifest present

Golden cases:

- single spike
- two-spike burst
- high-index spike
- below-threshold no-fire
- threshold-crossing fire

### Existing tests to keep

- `tests/integration/test_teensy_e2e.py` remains Teensy-only
- simulator-backed PYNQ tests remain valid for CI
- simulator tests must not be renamed or documented as hardware proof

## Rollout Rules

Do not change NeuroCNL's canonical support claim for `pynq` until:

1. overlay-v1 assets exist
2. board-side preflight returns `ok`
3. real-board deploy/run/verify tests exist
4. docs are updated in both modules

At that point, the docs may change from:

- `approximate — export only`

to something more precise, such as:

- `approximate — fixed-overlay FPGA inference`

but only if the support matrix and tests are updated in the same change.

## Risks

- The current repo-level PYNQ limits overstate v1 runtime capability.
- FINN may still be a poor fit for stateful LIF execution on Zynq-7000.
- BRAM pressure may force v1 limits lower than the current export contracts.
- If the overlay contract is not made explicit, cross-module drift will return.

## Resume-Here Pointer

If work resumes later, start with:

1. Phase 1 contract narrowing
2. `overlay_manifest.json` design
3. fixed overlay hardware implementation

Do not start with FINN wiring.
