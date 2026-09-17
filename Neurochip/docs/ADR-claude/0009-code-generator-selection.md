# ADR 0009: Code Generator Selection

## Status
Accepted

## Context
Neurochip must generate deployment-ready code for 6+ hardware targets (PYNQ bitstreams, Teensy C firmware, Lava Python, BrainScaleS configuration, NeuroML XML, Akida models), each with fundamentally different output formats and toolchain requirements.

## Decision
Implement separate code generator modules per target (`pynq_generator.py`, `teensy_generator.py`, `lava_generator.py`, `brainscales_generator.py`, `neuroml_generator.py`, `akida_simulator.py`). Each generator consumes the deployment manifest and hardware profile contracts to produce target-specific output. Generator selection is driven by the target device enum in the deployment contract.

## Consequences
- **Positive:** Per-target generators are independently maintainable and testable; enum-driven selection ensures only valid target combinations are attempted.
- **Negative:** 6+ generator modules require parallel maintenance as contract schemas evolve; no fallback mechanism if a generator fails — the deployment simply errors.

## Status Update (2026-07-16 audit)
The generator module roster in this ADR's Decision no longer matches `neurochip/app/services/` (confirmed via directory listing). `lava_generator.py` does not exist — the real Lava-target file is `lava_backend.py`. `akida_simulator.py` does exist, but its module docstring identifies it as "Akida Simulator — test double for CI environments without the Akida SDK," not the production generator; the real production path is `akida_generator.py` (a thin shim documented as exposing `generate_akida_package` for `export.py` to import) backed by `akida_backend.py`, which transparently delegates to `AkidaSimulator` only when the `akida` SDK is unavailable. `pynq_generator.py`, `teensy_generator.py`, `brainscales_generator.py`, and `neuroml_generator.py` do still exist as named. The ADR also omits several generator/backend modules that exist today: `loihi_generator.py`, `spinnaker_generator.py`, `spinnaker2_backend.py`, and `speck_backend.py` (Speck also has `speck_compiler.py`, `speck_errors.py`, `speck_samna_runtime.py`, `speck_simulator.py`).
