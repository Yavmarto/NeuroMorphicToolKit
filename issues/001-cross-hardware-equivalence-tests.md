---
title: Cross-hardware equivalence tests
priority: 10
module: root
status: Open
---

# Objective
Verify given CNL specs produce equivalent spike behavior across Nengo, Loihi, and Teensy.

# Description
Cross-hardware parity forms the foundational claim parameter mapping equivalence correctly across hardware variants internally utilizing the NMTK abstractions. Test validations across multiple systems using explicit boundaries and metrics verify accurate parity. This spans neurocnl pipelines to Neurobench and Neuro-Dream-Hand testing flows dynamically simulating and mapping identical specs evaluating the hardware execution fidelity accurately against Nengo standards.

# Acceptance Criteria
- [ ] Verify identical CNL specs via Nengo reference.
- [ ] Produce spike outputs dynamically targeting identical schemas for Teensy, Loihi, and PYNQ variations.
- [ ] Develop parity assertions.
