# Test Integration Plan: BrainChip Akida

## Overview
This document details the test integration plan targeting **BrainChip Akida** technology. The goal here avoids CNN-to-SNN conversion constraints by parsing the pure, natural plain-English SNN specifications from NeuroCNL into a natively supported SNN architecture logic mapped onto Akida paradigms. 

## Usable Tutorials & Examples to Test

### 1. NeuroCNL Akida Native Generator & Validator Testing
Akida generation requires that topological conditions are met to accommodate invariants in the physical constraint pipeline. NMTK handles this via explicitly coded constraint validators (`akida_validator.py`) and a custom topology builder (`akida_generator.py`).

**Script Paths**:
- `neurocnl/neurocnl/generation/test_akida_generator.py`
- `neurocnl/neurocnl/layers/test_akida_validator.py`

**What it tests**:
- The validator enforces checks across native constraints (such as avoiding topological drifting and ensuring capability sets match valid `Layer 2` connections).
- The generator translates abstract SNN graphs to representations congruent to an Akida pipeline.

**How to run**:
Since Akida tools run into compatibility hurdles natively on macOS, they're predominantly validated remotely or through platform-agnostic test stubs. You can test SNN invariant constraints via:
```bash
pytest neurocnl/neurocnl/generation/test_akida_generator.py
```

### 2. End-To-End Translation Injection
You can adapt the general NeuroCNL testing tutorial `04_full_pipeline.py` script to trace the full compilation lifecycle including `akida_capabilities.py`.

**How to run**:
1. Look into `neurocnl/examples/04_full_pipeline.py`.
2. Provide a NeuroCNL constraint definition (e.g. `working_examples.md` files) to ensure SNN mapping properties remain viable when swapped to the BrainChip structural constraints.

## Official Documentation and External Tutorials

BrainChip provides the MetaTF toolset for Akida constraints, useful for validating NMTK's generated architectures:

- **Official MetaTF Documentation:** [doc.brainchipinc.com/](https://doc.brainchipinc.com/)
- **Akida Examples & Workflow Tutorials:** The developer hub and MetaTF documentation site include numerous workflow examples (e.g., PyTorch-to-Akida conversion flows). These are excellent reference architectures to test if the `akida_generator.py` inside NMTK follows the officially recommended hardware abstractions and quantization limits.
