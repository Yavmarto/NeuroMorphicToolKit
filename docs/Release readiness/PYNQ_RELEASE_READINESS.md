# PYNQ Z2 Workflow — Release-Readiness Notes

**Date**: 2026-04-08
**Issue**: #16 — Opus Final PYNQ Toolkit Integration Review

## Status Summary

The PYNQ Z2 workflow is **release-ready for export and simulator-backed deployment**. All four reviewed paths are functional with the caveats noted below.

## What Works

### Export-Only Path
- `plan_pynq_exportability()` evaluates 9 constraints (neuron count, synapse count, memory budget, weight quantizability, neuron models, learning rules, topology, bit-width, recurrence)
- Three verdicts: `EXPORTABLE`, `EXPORTABLE_WITH_WARNINGS` (>80% capacity), `NOT_EXPORTABLE`
- Artifact ZIP generation produces 5 contract-compliant files: `overlay_config.json`, `weights.bin`, `register_map.json`, `manifest.json`, `README.md`
- Weight packing supports int4 (nibble-packed), int8, and int16 bit-widths
- `validate_pynq_artifact_completeness()` enforces ZIP structure

### Rejected-Network Path
- 8 export-time rejection codes in `PynqRejectionReason` enum
- 2 deploy-time rejection codes (`BOARD_UNREACHABLE`, `OVERLAY_LOAD_FAILURE`)
- Fail-closed invariant enforced by Pydantic `model_validator`: rejections present iff state is negative
- UI surfaces rejection reasons with human-readable messages

### Deployable Path (Simulator Fallback)
- NeuroCNL-to-Neurochip handoff maps artifact to deploy payload
- Neurochip backend: overlay load, MMIO weight configuration, DMA spike transfer
- `PynqSimulator` provides full LIF execution path when `pynq` library is unavailable
- Lifecycle states: `UNLOADED` -> `LOADED` -> `CONFIGURED` -> `RUNNING` -> `CONFIGURED`
- Status polling via `GET /hardware/pynq/status`

### Runtime Verification (SITL)
- 5 default stimulus cases (single spike, multi-spike, burst, high-index)
- Custom stimulus case injection via request body
- Per-step timing and correctness reporting
- Integrated as optional final step in UI workflow

### Toolkit UI Orchestration
- Dashboard entry point ("PYNQ Deploy" button)
- Four-step stepper: Prepare -> Deploy -> Monitor -> Verify
- State machine in `PynqDeployProvider` manages full workflow
- REST client calls NeuroCNL (port 8000) and Neurochip (user-configured endpoint)

## Test Coverage

| Module | Tests | Status |
|--------|-------|--------|
| NeuroCNL Exporter | 8 | Pass |
| NeuroCNL Handoff | 30 | Pass |
| NeuroCNL Contracts | 25 | Pass |
| Neurochip Backend | 31 | Pass |
| Neurochip Properties | 5 | Pass |
| Neurochip SITL | 20 | Pass |
| Dream-Hand SITL | 17 | Pass |
| **Total** | **136+** | **Pass** |

## What's Blocked

| Item | Reason | Impact |
|------|--------|--------|
| Real PYNQ hardware deployment | `snn_overlay.bit` + `.hwh` require Xilinx Vivado synthesis | Cannot test on physical board |
| Bitstream is not in-repo | FPGA synthesis is a manual, vendor-toolchain step | Expected; simulator covers CI |

## Board-Readiness Guardrails

- Relative PYNQ bitstream names now resolve against `Neurochip/neurochip/overlays/`.
- Real-board readiness is exposed via `GET /hardware/pynq/preflight`.
- Preflight returns:
  - `ok` when hardware runtime is active and both overlay files are present
  - `failed` when hardware runtime is active but overlay assets are incomplete
  - `degraded` when simulator fallback is active, which keeps CI usable but is not real-board proof

## Out of Scope

- **FINN integration** (Phase 2): automated HLS compilation from network IR
- **Single orchestration endpoint**: UI chains calls manually; no server-side pipeline endpoint
- **Mypy cleanup**: ~370 pre-existing type errors in Neurochip (not PYNQ-specific)
- **print() -> logging migration**: cosmetic, does not affect correctness

## Contracts & Defense-in-Depth

Hardware limits are mirrored across three layers:
1. **Authoritative source**: `Neurochip/neurochip/targets/pynq_z2.json`
2. **NeuroCNL contract**: `PynqHardwareLimits` in `pynq_deployment_contract.py`
3. **Neurochip contract**: `MAX_NEURONS`, `MAX_SYNAPSES` in `pynq_runtime_artifact_contract.py`

Memory budget formula (consistent across both):
```
weight_bytes  = num_synapses * (bit_width / 8)
neuron_bytes  = MAX_NEURONS * 6       # voltage (4B) + refractory (2B)
index_bytes   = num_synapses * 8      # pre + post indices (4B each)
total_kb      = (weight_bytes + neuron_bytes + index_bytes) / 1024
```

## Integration Fixes Applied (Issue #16)

1. **Weight packing correctness**: `_pack_weights_bytes()` now branches on bit-width (was always int4)
2. **Semantic overflow check**: weight count validated against `MAX_SYNAPSES` (was `MAX_NEURONS`)
3. **Rejection message accuracy**: synapse capacity message uses `{bit_width}` placeholder (was hardcoded "int4")
4. **Hardware JSON completeness**: `synapse_capacity` added to `pynq_z2.json`
5. **Dart status enum alignment**: `loaded` and `running` states added to `PynqDeployJobStatus`
6. **Documentation truthfulness**: artifact list corrected, pipeline status updated
