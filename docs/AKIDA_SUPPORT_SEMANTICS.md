# Akida Support Semantics

## Overview

This document defines the **truthfulness boundary** for BrainChip Akida support in the NeuroMorphic ToolKit. The toolkit uses a **three-tier support model** that distinguishes between what is fundamentally unsupported, what the toolkit can produce offline (scaffold export), and what requires the Akida SDK for full deployment.

## Definitions

### Exportable Scaffold

**The toolkit can produce MetaTF project scaffolding and quantized weight artifacts offline. No Akida SDK or hardware required.**

An `EXPORTABLE_SCAFFOLD` verdict means:
- All population sizes fit within 256 neurons per Neural Processor (NP)
- Total neuron count fits within the 1,200,000 neuron limit
- Network neuron model is in the supported set: `{LIF}`
- Network topology passes the Akida1 or Akida2 capability checker
- Weight bit-width is in `{1, 2, 4}`
- Absolute weight values do not exceed 15.0
- All float weights can be mapped to the target fixed-point bit-width
- No on-chip learning rules are declared
- Estimated memory usage fits within the 8,192 KB on-chip budget

Output artifacts (scaffold ZIP contents):
- `model_config.json` -- populations, connections, quantized thresholds
- `weights.bin` -- packed fixed-point weight bytes
- `metatf_project/` -- MetaTF project structure skeleton
- `manifest.json` -- target device and checksum metadata
- `README.md` -- human-readable artifact summary and next steps

### SDK Deployable

**Model can be compiled and executed via the Akida SDK on hardware or AKD1000 simulator.**

An `SDK_DEPLOYABLE` verdict means:
- Export scaffold succeeded (all `EXPORTABLE_SCAFFOLD` constraints met)
- Akida Python SDK is importable (`import akida` succeeds)
- Model can be mapped to an Akida device or AKD1000 simulator
- For Akida2: recurrent connections handled as approximate (temporal blocks)

> **Note**: `SDK_DEPLOYABLE` is a **runtime** state. The planner cannot produce this verdict at planning time.

### Unsupported

**Network fundamentally cannot target Akida.**

An `UNSUPPORTED` verdict means one or more blocking rejections are present: wrong neuron model, unconstrained topology, capacity exceeded, or other incompatibility.

## Support States

| State | When Produced | Meaning |
|-------|--------------|---------|
| `EXPORTABLE_SCAFFOLD` | Planning time | All constraints met; scaffold package can be generated |
| `EXPORTABLE_SCAFFOLD_WITH_WARNINGS` | Planning time | Constraints met but near thresholds (>80%) or topology is approximate |
| `UNSUPPORTED` | Planning time | One or more blocking rejections; export not possible |
| `SDK_DEPLOYABLE` | Runtime | Scaffold OK AND Akida SDK available AND model mapped |
| `SDK_NOT_DEPLOYABLE` | Runtime | Scaffold OK but SDK unavailable or mapping failed |

## Rejection Reasons

### Export-Time Rejections (Deterministic)

| Code | Description |
|------|-------------|
| `exceeds_neuron_capacity` | Network requires >1,200,000 neurons |
| `exceeds_np_size` | One or more populations exceed 256 neurons per NP |
| `exceeds_memory_budget` | Estimated memory exceeds 8,192 KB |
| `weight_not_quantizable` | Weights cannot map to target 1/2/4-bit representation |
| `weight_exceeds_max` | Absolute weight value exceeds 15.0 |
| `unsupported_neuron_model` | Model not in {LIF} |
| `unsupported_learning_rule` | On-chip learning not supported |
| `unsupported_topology` | Network fails Akida1/Akida2 topology checks |
| `weight_bit_width_unsupported` | Bit-width not in {1, 2, 4} |
| `akida_connection_properties_on_v1` | Akida1 does not support spatiotemporal block properties |

### Runtime Rejections

| Code | Description |
|------|-------------|
| `sdk_not_available` | Akida Python SDK not importable |
| `device_mapping_failure` | Model could not be mapped to Akida device/simulator |

## Truthfulness Rules

1. **The toolkit MAY claim "Akida Exportable"** when `plan_akida_exportability()` returns `EXPORTABLE_SCAFFOLD` or `EXPORTABLE_SCAFFOLD_WITH_WARNINGS`.

2. **The toolkit MUST NOT claim "Akida Deployable"** unless the Akida SDK is available and model mapping succeeds. This is a runtime state.

3. **The UI MUST visually distinguish** scaffold-export (purple/indigo) from SDK-deploy (green) states. This prevents users from conflating "I have files" with "my model runs on Akida hardware."

4. **The planner MUST surface topology and weight constraint failures** before any export attempt. Users must not encounter surprise exceptions during export if the planner could have detected the issue.

5. **Verdict strings at the API level** use `"exportable_scaffold"` / `"exportable_scaffold_with_warnings"` / `"unsupported"` -- deliberately distinct from the generic backend verdicts `"faithful"` / `"approximate"` / `"unsupported"` and from PYNQ's `"exportable"` / `"not_exportable"` to make the semantic boundary explicit.

6. **When topology is classified as "approximate"** by `Akida2CapabilityChecker`, the toolkit MUST produce `EXPORTABLE_SCAFFOLD_WITH_WARNINGS` (not `EXPORTABLE_SCAFFOLD`) and include a warning about recurrent connection approximation.

## Akida Version Differences

| Aspect | Akida 1 (AKD1000) | Akida 2 |
|--------|-------------------|---------|
| Topology | Strictly sequential only | Allows branching, skip connections |
| Recurrence | Unsupported | Approximate (temporal blocks) |
| Lateral inhibition | Unsupported | Supported |
| Connection properties | Not supported | Spatial/temporal block mapping |
| Random topology | Unsupported | Capped at 10 in-edges per node |

## Comparison: PYNQ vs Akida

| Aspect | PYNQ Z2 | BrainChip Akida |
|--------|---------|-----------------|
| **Primary verdict axis** | Exportability | Scaffold exportability |
| **Critical constraint** | Weight quantization, synapse count | Topology, NP size |
| **Verdict at plan time** | `EXPORTABLE` / `NOT_EXPORTABLE` | `EXPORTABLE_SCAFFOLD` / `UNSUPPORTED` |
| **Runtime dependency** | Board connectivity | Akida SDK availability |
| **Export artifact** | JSON config + binary weights | MetaTF project + binary weights |
| **UI color** | Blue/teal | Purple/indigo |
| **Full pipeline** | Board overlay load | SDK compile + device map |

## Scope Boundary

This document (issue #17) defines **only** the semantic contract and planner surface:
- `AkidaSupportState` enum and `AkidaExportResult` contract
- `plan_akida_exportability()` planner function
- UI model and presentation rules

Related issues handle downstream concerns:
- **Issue #18**: Akida deployment contract (runtime SDK integration)
- Neurochip Akida backend (`akida_backend.py`) handles actual package generation

## Contract Files

| File | Purpose |
|------|---------|
| `neurocnl/neurocnl/contracts/akida_deployment_contract.py` | Python contract: limits, enums, result model |
| `neurocnl/neurocnl/planner.py` | `plan_akida_exportability()` + integration into `plan_backend_support()` |
| `nmtk_ui_core/lib/models/akida_deployment_model.dart` | Dart UI model mirroring Python contract |
| `Neurochip/neurochip/contracts/deployment_contracts.py` | `AKIDA` in `TargetDevice` enum |
