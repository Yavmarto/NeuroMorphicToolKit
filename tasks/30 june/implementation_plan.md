# Phase 3 — Wgpu Native Graphics Visualization Upgrade

**Task:** Network visualization upgrade to 1,000,000 neurons using native GPU compute.

---

## Background

Phase 2 (Flutter Fragment Shaders) successfully demonstrated the UI/Backend integration and the `BulkSpikeFrame` binary protocol. However, Flutter's custom shaders are strictly limited to **fragment** (per-pixel) operations. Rendering 100,000+ independent particles requires **vertex** shaders and instanced rendering, which Flutter blocks.

To achieve the requirement of 1,000,000 neurons at 30+ FPS, we are moving directly to Phase 3: **Rust + Wgpu**. This completely bypasses Flutter's graphics engine, giving us low-level access to the device's native GPU APIs (Metal/Vulkan).

---

> [!IMPORTANT]
> ## User Review Required
> **Build System Complexity:** This plan introduces a Rust toolchain dependency to the Flutter frontend build process. We will need to use `flutter_rust_bridge` or configure native CMake/Xcode build scripts to compile the Rust library (`.so`, `.dylib`) and bundle it with the app. Are you comfortable adding Rust to the frontend build pipeline?

---

## Architectural Concept

The pipeline is structured as three isolated components passing a baton:

1. **The Backend (Python):** Streams the exact same `BulkSpikeFrame` (binary `Float32List`) over WebSockets. (No changes needed).
2. **The Rust Graphics Engine (`nmtk_wgpu`):** A native Rust library bundled inside the app. It uses the `wgpu` crate to talk directly to the GPU. It exposes a simple C-interface to initialize a graphics context, receive a raw memory pointer to the spike data, and draw it using native instanced vertex shaders.
3. **The Flutter Bridge (`WgpuNativeNeuronRenderer`):** A Dart class that implements our existing `NeuronRenderer` interface. It does **not** draw anything. It simply receives the data, passes the memory pointer down to Rust via FFI, and mounts a Flutter `Texture` widget. Rust draws directly to that hardware texture, and Flutter just displays the final picture.

---

## Platform Expectations (The /viz-demo)

Because we are dropping down to the bare metal, performance will scale directly with the host device's physical GPU, rather than Flutter's software overhead. Here is what you will see on the `/viz-demo` screen across different platforms:

### 1. Mac ARM & iOS (Apple Silicon)
- **Backend:** `wgpu` compiles to **Metal**.
- **Performance:** **Flawless (1M+ neurons at 60 FPS).**
- **Why:** Apple Silicon uses Unified Memory Architecture (UMA). When Dart passes the `Float32List` memory pointer to Rust, Rust maps it directly to the GPU without a costly PCIe bus transfer. The 10k (Raster), 100k (Particle), and 1M (Heatmap) demos will all run butter-smooth without breaking a sweat.

### 2. Android
- **Backend:** `wgpu` compiles to **Vulkan**.
- **Performance:** **Excellent to Good, depending on the chip.**
- **Why:** High-end Androids (modern Snapdragons) will push 100k-500k particles at 60 FPS effortlessly. Pushing a full 1,000,000 points on a phone might cause thermal throttling after a few minutes, dropping the frame rate to 30 FPS. Low-end phones will run the 10k and 100k demos perfectly but may struggle with 1M.

### 3. Windows & Linux (Desktop)
- **Backend:** `wgpu` compiles to **DirectX 12** or **Vulkan**.
- **Performance:** **Flawless (1M+ neurons at 60-144 FPS).**
- **Why:** With a dedicated desktop GPU, transferring the few megabytes of spike data across the PCIe bus every frame is trivial. The GPU will easily render millions of points.

---

## Proposed Changes

### 1. The Rust Crate
#### [NEW] `neurocnl/frontend/rust/nmtk_wgpu/`
A new Rust crate depending on `wgpu` and `wgpu_hal`.
- Exposes FFI functions: `renderer_init()`, `renderer_push_spikes(ptr, count)`, `renderer_get_texture_id()`.
- Implements a Vertex Shader (`.wgsl`) that takes instanced coordinates and expands them into glowing quads (point sprites).
- Handles the platform-specific boilerplate of creating a shared hardware texture (e.g., `CVPixelBuffer` on Apple, `HardwareBuffer` on Android) that Flutter can read.

### 2. The Flutter FFI Bindings
#### [NEW] `lib/visualization/wgpu_native_renderer.dart`
Implements `NeuronRenderer`.
- Uses `dart:ffi` to load the Rust dynamic library.
- On `attach()`, calls `renderer_init()` and registers the returned texture ID with a Flutter `Texture` widget.
- On `pushFrame()`, passes the raw `Float32List` memory address to Rust. No data copying occurs.

### 3. The Seamless Swap
#### [MODIFY] `lib/visualization/renderer_registry.dart`
```dart
NeuronRenderer rendererFor(VisualizationScale scale) {
  // Flip the switch: We now return the Rust renderer instead of the Fragment shaders.
  if (useNativeRenderer) return WgpuNativeNeuronRenderer();
  return FragmentShaderNeuronRenderer(scale: scale);
}
```
All existing UI components, including `VisualizationPanel` and the `/viz-demo` shell, remain **100% untouched**. They will automatically switch from using the failing fragment shaders to the lightning-fast Wgpu backend.

---

## Verification Plan

1. **Rust Toolchain:** Verify that the Rust library compiles to `.dylib` (Mac) and can be loaded via `DynamicLibrary.open` in Dart.
2. **Texture Registration:** Ensure the shared texture draws a solid color (e.g., green) to the Flutter `Texture` widget to confirm the bridge is working before writing shaders.
3. **Demo Execution:** Launch `/dev/viz-demo` on macOS. Verify that the 10k, 100k, and 1M tabs display the data correctly and maintain a stable 60 FPS using the Rust backend.
