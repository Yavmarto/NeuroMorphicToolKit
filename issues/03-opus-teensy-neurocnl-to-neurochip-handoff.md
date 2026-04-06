---
title: "Opus — Build NeuroCNL to Neurochip Teensy Handoff"
labels: ["teensy", "integration", "neurochip", "mapping"]
---

# Goal
Map validated NeuroCNL networks into the exact payload Neurochip needs for Teensy firmware generation.

# Scope
- IR/Nengo to `NetworkInput` mapping
- provenance attachment
- deterministic payload generation
- fail-closed unsupported cases

# Deliverables
- shared handoff mapper
- integration tests for one deployable and one rejected network

# Why Opus
This is the highest-risk semantic integration seam.

# Depends On
- [01-opus-teensy-deployment-contract.md](/Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/issues/01-opus-teensy-deployment-contract.md)
- [02-sonnet-teensy-validator-enforcement.md](/Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/issues/02-sonnet-teensy-validator-enforcement.md)
