---
title: "Implement Hardware-Aware Constraint Validation for SpiNNaker Targets"
labels: ["enhancement", "validation", "hardware", "spinnaker"]
---

## Audit Status

Status as of 2026-04-13: `partially implemented`

What is already landed:
- `neurocnl/neurocnl/layers/spinnaker2_validator.py` enforces neurons-per-core and fan-in checks for the `spinnaker2` backend.
- Layer-level tests cover the main `spinnaker2` validation path and oversized-neuron rejection.

What is still open:
- The implementation is clearly `spinnaker2`-specific; it does not yet obviously satisfy the broader `spinnaker` and `spinnaker2` wording in this issue.
- The issue asked for clearer pre-export hardware rejection coverage, especially around fan-in and user-facing failure messaging.
- Keep this issue open until the validation surface and tests are explicit about backend coverage and the remaining hardware-limit checks are fully exercised.

# Problem Statement
While the basic SNN translation and generation for SpiNNaker/SpiNNaker2 (via `spinnaker_exporter.py` and `spinnaker2_exporter.py`) are correctly mapping NetworkIR primitives to pyNN-style definitions, there is currently a lack of rigorous, hardware-specific constraint validation in the NeuroCNL validation pipeline.

SpiNNaker architectures have strict hardware limitations concerning core utilization (e.g., maximum neurons per core, synapse memory limits) and interconnect routing (maximum fan-in/fan-out, bandwidth constraints). If a network exceeds these physical limits, it will successfully pass our current Layer 1/2 validations and export gracefully, only to fail later during the actual placement and routing compilation stage on the hardware toolchain (e.g., PACMAN).

# Proposed Solution
1. **Extend Layer Validation:** Introduce specific Layer 1/Layer 2 invariant checks or a dedicated hardware profile validator that enforces SpiNNaker hardware constraints prior to the export step.
2. **Core Utilization Checks:** Implement validation checks to ensure population sizes do not exceed the typical maximum limits per ARM core (e.g., 255 neurons per core for standard configurations) or verify that the populations can be safely split/partitioned by the backend without violating CNL semantics.
3. **Routing/Synapse Checks:** Add assertions to validate that the total number of incoming connections (fan-in) to any single population or core does not exceed the available synaptic memory limitations.

# Acceptance Criteria
- [ ] A new `SpiNNakerValidator` (or additions to existing Layer 1/2 validators) is created.
- [ ] Constraints for maximum neurons per core and maximum fan-in are enforced during the validation phase when the target backend is `spinnaker` or `spinnaker2`.
- [ ] The validation pipeline correctly rejects networks that violate these hardware constraints, providing a clear error message to the user before code export occurs.
- [ ] Tests are written to ensure that valid networks pass and oversized/overconnected networks fail validation.
