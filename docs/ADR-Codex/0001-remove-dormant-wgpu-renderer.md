# ADR 0001: Remove the Dormant Native WGPU Renderer

## Status

Accepted

## Context

The macOS-only `nmtk_wgpu` renderer was disabled by default after its `CVPixelBuffer` bridge crashed on the first real draw. The supported visualization path has continued to use Flutter fragment shaders, while every macOS build still compiled and bundled the unused Rust library.

## Decision

Remove the Rust crate, Flutter texture bridge, FFI bindings, feature switch, and native build integration. Keep `createNeuronRenderer` as the stable shared API and make it unconditionally return `FragmentShaderNeuronRenderer`.

This supersedes the native-renderer portion of `docs/ADR-claude/0027-dual-rendering-pipeline.md`. The independent Flutter `TileGridNeuronRenderer` remains the supported high-density chip visualization path.

## Consequences

- macOS builds no longer require Cargo or bundle `libnmtk_wgpu.dylib`.
- NeuroCNL simulation visualization remains cross-platform and uses the already-supported fragment-shader renderer.
- Reintroducing a native renderer requires a new verified design and ADR rather than reviving the crash-prone bridge implicitly.
