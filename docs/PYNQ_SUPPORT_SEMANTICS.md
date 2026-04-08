# PYNQ Support Semantics

## Overview

This document defines the **truthfulness boundary** for PYNQ Z2 support in the NeuroMorphic ToolKit. The toolkit uses a **two-tier support model** that distinguishes between what the toolkit can produce offline (export) and what requires real hardware (deployment).

## Definitions

### Exportable

**The toolkit can quantize weights and produce PYNQ overlay artifacts offline. No board required.**

An `EXPORTABLE` verdict means:
- All network populations fit within the 65,536 neuron limit
- Total synapse count fits within the 65,536 synapse limit (at int4 quantization)
- All float weights can be mapped to the target fixed-point bit-width (int4/int8/int16)
- All neuron models are in the supported set: `{LIF, Izhikevich}`
- No on-chip learning rules are declared
- No recurrent/feedback connections, lateral inhibition, or spatial connectivity in the network
- Estimated memory usage fits within the 512 KB on-chip BRAM budget

Output artifacts (contract ZIP contents):
- `overlay_config.json` — populations, connections, quantized thresholds
- `weights.bin` — packed fixed-point weight bytes (int4 nibble-packed, int8, or int16)
- `register_map.json` — Zynq-7000 MMIO register offsets
- `manifest.json` — target device and checksum metadata
- `README.md` — human-readable artifact summary

### Deployable

**Overlay artifacts can be loaded and executed on real PYNQ Z2 hardware.**

A `DEPLOYABLE` verdict means:
- Export succeeded (all `EXPORTABLE` constraints met)
- Real PYNQ Z2 board is reachable via network (Ethernet/USB)
- Overlay bitstream loaded successfully onto Zynq-7000 programmable logic
- DMA channels and SNN IP core are accessible

> **Note**: `DEPLOYABLE` is a **runtime** state resolved by the Neurochip PYNQ backend (issue #11). The planner cannot produce this verdict at planning time.

## Support States

| State | When Produced | Meaning |
|-------|--------------|---------|
| `EXPORTABLE` | Planning time | All constraints met; overlay package can be generated |
| `EXPORTABLE_WITH_WARNINGS` | Planning time | Constraints met but near thresholds (>80% capacity) |
| `NOT_EXPORTABLE` | Planning time | One or more blocking rejections; export not possible |
| `DEPLOYABLE` | Runtime (issue #11) | Export succeeded AND overlay running on board |
| `NOT_DEPLOYABLE` | Runtime (issue #11) | Export OK but board unreachable or overlay load failed |

## Rejection Reasons

### Export-Time Rejections (Deterministic)

| Code | Description |
|------|-------------|
| `exceeds_neuron_capacity` | Network requires >65,536 neurons |
| `exceeds_synapse_capacity` | Network requires >65,536 synapses |
| `exceeds_memory_budget` | Estimated memory exceeds 512 KB |
| `weight_not_quantizable` | Weights cannot map to target int4/int8/int16 |
| `unsupported_neuron_model` | Model not in {LIF, Izhikevich} |
| `unsupported_learning_rule` | On-chip learning not supported on FPGA overlay |
| `unsupported_topology` | Recurrent connections or advanced topology features |
| `weight_bit_width_unsupported` | Requested bit-width not in {4, 8, 16} |

### Deploy-Time Rejections (Runtime)

| Code | Description |
|------|-------------|
| `board_unreachable` | PYNQ Z2 board not reachable at configured endpoint |
| `overlay_load_failure` | Bitstream flash failed on Zynq-7000 |

## Truthfulness Rules

1. **The toolkit MAY claim "PYNQ Exportable"** when `plan_pynq_exportability()` returns `EXPORTABLE` or `EXPORTABLE_WITH_WARNINGS`.

2. **The toolkit MUST NOT claim "PYNQ Deployable"** unless runtime board connectivity is confirmed and overlay load succeeds. This is issue #11 scope.

3. **The UI MUST visually distinguish** export-ready (blue/teal) from deploy-ready (green) states. This prevents users from conflating "I can generate files" with "my board is running."

4. **The planner MUST surface quantization failures** before any export attempt. Users must not encounter surprise `ValueError` exceptions during export if the planner could have detected the issue.

5. **Verdict strings at the API level** use `"exportable"` / `"exportable_with_warnings"` / `"not_exportable"` — deliberately distinct from the generic backend verdicts `"faithful"` / `"approximate"` / `"unsupported"` to make the semantic boundary explicit.

## Comparison: Teensy vs PYNQ

| Aspect | Teensy 4.1 | PYNQ Z2 |
|--------|-----------|---------|
| **Primary verdict axis** | Deployability | Exportability |
| **Critical constraint** | I/O pin count, neuron capacity | Weight quantization, synapse count |
| **Verdict at plan time** | `DEPLOYABLE` / `NOT_DEPLOYABLE` | `EXPORTABLE` / `NOT_EXPORTABLE` |
| **Runtime dependency** | USB serial connection | Network connection to board |
| **Export artifact** | C firmware code (`.ino` + `.h`) | JSON config + binary weights |
| **UI color** | Green (deploy-ready) | Blue/teal (export-ready) |
| **Full pipeline** | Yes (plan → export → flash → verify) | Yes with simulator fallback (plan → export → deploy → verify); real hardware blocked on bitstream synthesis |

## Scope Boundary

This document (issue #08) defines **only** the semantic contract and planner surface:
- `PynqSupportState` enum and `PynqExportResult` contract
- `plan_pynq_exportability()` planner function
- UI model and presentation rules

Related issues handle downstream concerns:
- **Issue #09**: Shared PYNQ runtime artifact contract (package format, metadata)
- **Issue #10**: Align NeuroCNL PYNQ export with artifact contract
- **Issue #11**: Neurochip PYNQ runtime core (real overlay load, DMA, MMIO)
- **Issue #12**: NeuroCNL-to-Neurochip handoff (deploy request, remote endpoint, status)

## Contract Files

| File | Purpose |
|------|---------|
| `neurocnl/neurocnl/contracts/pynq_deployment_contract.py` | Python contract: limits, enums, result model |
| `neurocnl/neurocnl/planner.py` | `plan_pynq_exportability()` + integration into `plan_backend_support()` |
| `nmtk_ui_core/lib/models/pynq_deployment_model.dart` | Dart UI model mirroring Python contract |
| `Neurochip/neurochip/contracts/deployment_contracts.py` | `PYNQ_Z2` in `TargetDevice` enum |
