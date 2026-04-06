---
title: "Sonnet — Enforce Teensy Deployability in NeuroCNL Planner and Validation"
labels: ["teensy", "validation", "planner", "toolkit"]
---

# Goal
Implement the NeuroCNL-side validation and planner logic that enforces the shared Teensy deployment contract.

# Scope
- planner verdict updates
- validator checks
- actionable error/warning messages
- rejected-network coverage

# Deliverables
- planner/validator changes
- tests for accepted and rejected networks

# Why Sonnet
This is mostly implementation against an agreed contract.

# Depends On
- [01-opus-teensy-deployment-contract.md](/Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/issues/01-opus-teensy-deployment-contract.md)
