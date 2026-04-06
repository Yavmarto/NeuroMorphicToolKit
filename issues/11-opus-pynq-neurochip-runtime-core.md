---
title: "Opus — Implement Neurochip PYNQ Runtime Core"
labels: ["pynq", "neurochip", "runtime", "toolkit"]
---

# Goal
Turn the Neurochip PYNQ backend from placeholder behavior into real runtime logic.

# Scope
- overlay load
- MMIO writes
- DMA/register execution path
- structured runtime errors
- simulator/test double for CI

# Deliverables
- real PYNQ runtime core in Neurochip
- tests for runtime and simulator paths

# Why Opus
This is the hardest technical step in the PYNQ path.

# Depends On
- [09-opus-pynq-runtime-artifact-contract.md](/Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/issues/09-opus-pynq-runtime-artifact-contract.md)
