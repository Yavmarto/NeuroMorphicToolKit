import 'dart:io' show Platform;

import 'package:nmtk_ui_core/visualization/fragment_shader_renderer.dart';
import 'package:nmtk_ui_core/visualization/renderer_interface.dart';
import 'package:nmtk_ui_core/visualization/wgpu_native_renderer.dart';

/// Stage 3: default-on for macOS (see "Staged rollout" in
/// `tasks/30 june/implementation_plan.md`). Rollback switch:
/// `--dart-define=NMTK_WGPU_RENDERER=false`. Delete once
/// `FragmentShaderNeuronRenderer` is no longer needed as a fallback.
const bool kEnableWgpuRenderer =
    bool.fromEnvironment('NMTK_WGPU_RENDERER', defaultValue: true);

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
