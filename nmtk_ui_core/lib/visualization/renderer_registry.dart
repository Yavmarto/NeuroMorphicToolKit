import 'dart:io' show Platform;

import 'package:nmtk_ui_core/visualization/fragment_shader_renderer.dart';
import 'package:nmtk_ui_core/visualization/renderer_interface.dart';
import 'package:nmtk_ui_core/visualization/wgpu_native_renderer.dart';

/// Default-off: `SharedPixelBuffer::write_rows` (rust/nmtk_wgpu/src/texture_bridge/macos.rs)
/// crashes the whole process with SIGSEGV on the first real draw call (confirmed via
/// macOS crash report — objc_msgSend_uncached failure inside CVPixelBufferLockBaseAddress).
/// Re-enable via `--dart-define=NMTK_WGPU_RENDERER=true` only for native-side debugging.
const bool kEnableWgpuRenderer = bool.fromEnvironment(
  'NMTK_WGPU_RENDERER',
  defaultValue: false,
);

/// Picks the neuron renderer for the current platform/build. Falls back to
/// [FragmentShaderNeuronRenderer] if the native renderer isn't enabled, isn't
/// supported on this platform, or fails to load (missing dylib, wrong arch,
/// codesigning issue) — checked here, before any code commits to the
/// native renderer's `Texture`-widget contract.
NeuronRenderer createNeuronRenderer() {
  if (kEnableWgpuRenderer && Platform.isMacOS) {
    try {
      return WgpuNativeNeuronRenderer();
    } catch (_) {
      return FragmentShaderNeuronRenderer();
    }
  }
  return FragmentShaderNeuronRenderer();
}
