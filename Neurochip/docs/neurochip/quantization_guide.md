# Quantization Trade-offs per Target Platform

This document describes the quantization trade-offs and constraints for different hardware platforms supported by NeuroChip.

## Overview

Quantization is the process of reducing the bit-width of weights in an SNN model to fit the target's hardware constraints. This reduces memory usage and power consumption, but may lead to a loss in model accuracy.

## Target-Specific Quantization Profiles

### Intel Loihi 2
- **Supported Bit-widths**: 1, 2, 4, 8 bits
- **Trade-off**: Higher bit-widths (e.g., 8-bit) offer the best accuracy but consume more on-chip memory. 4-bit is the most common for balanced performance.
- **Constraint**: Accuracy loss must be less than 25%.

### BrainChip Akida
- **Supported Bit-widths**: 1, 2, 4 bits
- **Trade-off**: Akida is designed for ultra-low power. 4-bit quantization is recommended for most applications, while 1-bit or 2-bit quantization is used for high-efficiency scenarios with possible accuracy loss.

### Teensy 4.1 (ARM Cortex-M7)
- **Supported Bit-widths**: 8, 16, 32 bits
- **Trade-off**: Teensy 4.1 can handle 32-bit floating point, but 8-bit or 16-bit fixed-point quantization is recommended to reduce memory footprint and improve performance on large networks.

### SpiNNaker
- **Supported Bit-widths**: 16, 32 bits
- **Trade-off**: SpiNNaker uses 32-bit fixed-point representation. 16-bit quantization can be used to optimize memory and communication overhead on the ARM-based nodes.

### BrainScaleS
- **Supported Bit-widths**: 4, 6 bits
- **Trade-off**: BrainScaleS uses analog synapses with discrete weight levels. 4-bit or 6-bit quantization is required to map digital weights to the analog physical parameters.

## Summary Table

| Hardware Target | Recommended Bit-width | Min Bit-width | Max Bit-width |
| --- | --- | --- | --- |
| Intel Loihi 2 | 4-bit | 1-bit | 8-bit |
| BrainChip Akida | 4-bit | 1-bit | 4-bit |
| Teensy 4.1 | 8-bit | 8-bit | 32-bit |
| SpiNNaker | 32-bit | 16-bit | 32-bit |
| BrainScaleS | 4-bit | 4-bit | 6-bit |

## Best Practices

- **Baseline**: Always start with a float32 baseline for your model.
- **Iterative Testing**: Use the **Quantization Explorer** to iteratively test lower bit-widths.
- **Accuracy Loss Limit**: Aim for less than 10% accuracy loss for mission-critical applications. NeuroChip enforces a maximum limit of 25%.
