# ADR 0005: Multi-Format Export

## Status
Accepted

## Context
Users need to deploy the same CNL-specified network to multiple hardware targets, each requiring its own code format (C header for Teensy, Python for Lava, NeuroML for interoperability, bitstreams for PYNQ).

## Decision
Implement 10 exporters (C header, NeuroML, Lava, Loihi, SpiNNaker, SpiNNaker2, PYNQ, Rockpool, Sinabs, NIR) each as a separate module in `neurocnl/export/`. All exporters consume the normalized IR and produce target-specific code or configuration. Cross-module handoff modules (`neurochip_pynq_handoff.py`, `neurochip_teensy_mapper.py`) bridge neurocnl exports to Neurochip's deployment pipeline.

## Consequences
- **Positive:** One-exporter-per-format pattern keeps each exporter focused and independently testable; IR consumption ensures all exporters work from the same normalized representation.
- **Negative:** 10 exporters require significant maintenance as hardware SDKs evolve; handoff modules create tight coupling between neurocnl and Neurochip.
