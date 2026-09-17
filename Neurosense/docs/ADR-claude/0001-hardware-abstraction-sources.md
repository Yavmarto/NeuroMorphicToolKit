# ADR 0001: Hardware Abstraction Sources

## Status
Accepted

## Context
Biosignal data comes from diverse hardware platforms (BrainFlow-compatible EEG/EMG boards, Prophesee event cameras, PYNQ FPGAs) as well as synthetic generators for development. Each has a fundamentally different data format, sampling rate, and connection protocol.

## Decision
Abstract all data sources behind a device manager pattern with dedicated routers for each source type (`devices.py`, `prophesee.py`, `pynq.py`) and a unified `stream.py` router for common streaming operations. A synthetic data generator enables full-stack development and testing without physical hardware. Support levels are tiered as validated or prototype via `infer_support_level()`.

## Consequences
- **Positive:** New hardware can be integrated by adding a source plugin without modifying the core pipeline; synthetic data enables development without hardware dependencies.
- **Negative:** Abstraction may obscure hardware-specific capabilities and timing characteristics; each new source requires a dedicated router and driver implementation.

## Status Update (2026-07-16 audit)
Support levels are not just "validated or prototype." `infer_support_level()` in
`neurosense/app/services/session_artifact.py` (lines 55-61) actually returns one of three
tiers: `"validated"` (synthetic capture mode/device), `"prototype"` (`pynq` or `prophesee`
device types), and `"experimental"` as the default fall-through — which covers everything
else, including BrainFlow-compatible devices like OpenBCI Cyton/Ganglion. This ADR's
exhaustive "or" statement omits the experimental tier entirely.
