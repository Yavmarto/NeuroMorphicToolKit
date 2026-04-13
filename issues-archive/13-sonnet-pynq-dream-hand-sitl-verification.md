---
title: "Sonnet — Add Optional Dream-Hand PYNQ SITL Verification"
labels: ["pynq", "verification", "dream-hand", "toolkit"]
---

# Goal
Let the toolkit optionally verify deployed PYNQ artifacts using Dream-Hand's SITL pattern.

# Scope
- feed known stimuli
- compare expected outputs
- expose coarse timing/correctness signals

# Deliverables
- optional SITL verification flow
- verification results surfaced back to toolkit UX

# Why Sonnet
This reuses existing SITL patterns more than it invents new architecture.

# Depends On
- [12-sonnet-pynq-neurocnl-to-neurochip-handoff.md](/Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/issues/12-sonnet-pynq-neurocnl-to-neurochip-handoff.md)
