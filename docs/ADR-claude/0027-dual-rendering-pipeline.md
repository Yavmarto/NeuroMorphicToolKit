# ADR-0027: Dual Rendering Pipeline (WGPU vs Canvas) for High-Density Visualizations

**Status:** Accepted  
**Date:** 2026-07-09

## Context

The NeuroMorphicToolKit features visualization tools for simulating and analyzing spiking neural networks (SNNs). Historically, these visualizations were rendered using Flutter's built-in canvas and the `NeuronRenderer/VisualizationFrame` interface. However, as the scale of simulated networks grows (reaching up to 1 million neurons), the standard canvas approach suffers from significant performance degradation, unable to maintain interactive frame rates for dense chip-die visualizations.

To address this, a high-performance native wgpu neuron renderer (`nmtk_wgpu_renderer_plugin` in Rust) was introduced for the `/viz-demo`.

## Decision

1. **Dual Rendering Pipeline:** We adopt a dual rendering strategy. The existing canvas-based renderer will be retained for standard UI elements and low-density visualizations where Flutter's native declarative UI shines. For high-density, compute-heavy visualizations (like the chip-die view), we will use the native wgpu renderer.
2. **Separation of Concerns:** The `TileGridNeuronRenderer` (used for chip-die visualizations) is implemented as a self-contained entity that operates independently of the existing `NeuronRenderer/VisualizationFrame` interface.
3. **Zeta Tokens Invariant:** All dynamic visualizations, regardless of the underlying rendering pipeline, must consume Zeta design tokens for colors and styling, strictly prohibiting hardcoded colors.

## Rationale

- **Performance:** WGPU provides low-level, high-performance access to the GPU, enabling the rendering of millions of elements (e.g., neurons on a chip die) at 60 FPS, which is impossible with the standard Flutter canvas.
- **Maintainability:** Keeping `TileGridNeuronRenderer` separate prevents the legacy `NeuronRenderer` interface from becoming bloated with low-level GPU buffer management concepts that only apply to the wgpu pipeline. It allows the wgpu pipeline to evolve independently.
- **Consistency:** Enforcing Zeta tokens ensures visual consistency across the entire application, even when switching between native UI and custom GPU rendering.

## Consequences

- The `nmtk_wgpu_renderer_plugin` must be maintained alongside the Flutter codebase, requiring Rust expertise.
- Developers must explicitly choose between the canvas renderer and the wgpu renderer based on the expected scale of the visualization.
- UI theme changes (Zeta tokens) must be properly synchronized with the wgpu renderer's state.
