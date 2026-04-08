---
title: "Opus — Define Toolkit Teensy Deployment Contract"
labels: ["teensy", "integration", "toolkit", "architecture"]
---

# Goal
Define the shared contract for what a NeuroCNL-authored network must satisfy to be deployable to Teensy through the toolkit.

# Scope
- supported neuron/topology subset
- timestep and execution assumptions
- max neurons/synapses
- allowed I/O mapping shape
- fail-closed deployability verdicts

# Deliverables
- contract spec in NeuroCNL and matching schema expectations for Neurochip
- clear planner states for deployable vs not deployable
- documented rejection reasons

# Why Opus
This is the backbone for all later Teensy work.

# Depends On
- none
