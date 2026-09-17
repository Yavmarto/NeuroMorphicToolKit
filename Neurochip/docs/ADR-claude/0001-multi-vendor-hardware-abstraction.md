# ADR 0001: Multi-Vendor Hardware Abstraction

## Status
Accepted

## Context
Neurochip must support 7+ neuromorphic hardware vendors (Intel Loihi 2, BrainChip Akida, SpiNNaker2, BrainScaleS, PYNQ, Teensy 4.1, Lava) with wildly different capabilities, APIs, and constraints. Each vendor exposes unique compilation targets, neuron models, and resource limits, making a unified deployment pipeline challenging without an abstraction layer.

## Decision
Define each hardware target as a static JSON profile in `neurochip/targets/` containing standardized fields (core_count, neuron_capacity, weight_bit_widths, power_envelope_mw). Services load these profiles to constrain compilation and estimation. A `HardwareProfile` Pydantic contract validates profiles at runtime.

## Consequences
- **Positive:** New hardware targets can be added by dropping a JSON file without code changes; services remain backend-agnostic.
- **Negative:** JSON profiles must be manually maintained as vendor SDKs evolve; no dynamic capability discovery.
