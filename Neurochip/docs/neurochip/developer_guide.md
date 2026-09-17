# Adding a new hardware target profile

This guide will walk you through the process of adding a new hardware target profile to the NeuroChip toolkit.

## Overview

Hardware profiles are JSON manifests stored in the `neurochip/targets/` directory. These profiles define the capabilities and constraints of a specific hardware target, which NeuroChip uses for compatibility analysis and estimation.

## Step-by-Step Guide

### 1. Create a New JSON Manifest
Create a new `.json` file in `neurochip/targets/` (e.g., `my_custom_chip.json`).

### 2. Define Hardware Specifications
Populate the JSON file with the following fields:

```json
{
    "id": "my_custom_chip",
    "name": "My Custom Chip",
    "manufacturer": "Company X",
    "description": "A high-performance neuromorphic chip for specialized SNN applications.",
    "core_count": 64,
    "neuron_capacity": 500000,
    "supported_neuron_models": ["LIF", "AdaptiveLIF"],
    "weight_bit_widths": [4, 8, 16],
    "on_chip_memory_kb": 4096,
    "io_pins": 24,
    "clock_speed_mhz": 200.0,
    "power_envelope_mw": 300.0,
    "pj_per_spike_op": 15.0,
    "access": "commercial",
    "notes": "Requires custom toolchain version 1.2 or higher."
}
```

### 3. Validate Against HardwareProfile Schema
Ensure that your profile respects the `HardwareProfile` contract defined in `neurochip/contracts/hardware_contracts.py`.

- `neuron_capacity >= 1`
- `core_count` between 1 and 128.
- `on_chip_memory_kb` between 1 KB and 16,384 KB.
- `clock_speed_mhz` between 1.0 MHz and 1,000.0 MHz.

### 4. Test the New Profile
Restart the NeuroChip backend. The new profile should automatically appear in the **Gallery** and the **Target Selector** dropdown in the dashboard.

### 5. (Optional) Implement Custom Generators
If the new target requires a specific firmware format, you may need to add a new generator in `neurochip/app/services/` and a corresponding router in `neurochip/app/routers/export.py`.
