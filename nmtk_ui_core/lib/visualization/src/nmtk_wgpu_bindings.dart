import 'dart:ffi';
import 'dart:io';

/// Hand-written `dart:ffi` bindings for the nmtk_wgpu Rust crate's 6-function
/// FFI surface (see `neurocnl/frontend/rust/nmtk_wgpu/src/lib.rs`). Not worth
/// generating via `ffigen` for a surface this small.
typedef _NmtkRendererCreateNative =
    Pointer<Void> Function(Uint32 width, Uint32 height);
typedef NmtkRendererCreateDart = Pointer<Void> Function(int width, int height);

typedef _NmtkRendererResizeNative =
    Void Function(Pointer<Void> handle, Uint32 width, Uint32 height);
typedef NmtkRendererResizeDart =
    void Function(Pointer<Void> handle, int width, int height);

typedef _NmtkRendererPushSpikesNative =
    Void Function(
      Pointer<Void> handle,
      Pointer<Float> ptr,
      IntPtr len,
      Uint32 totalNeuronCount,
      Float simulationTimeMs,
    );
typedef NmtkRendererPushSpikesDart =
    void Function(
      Pointer<Void> handle,
      Pointer<Float> ptr,
      int len,
      int totalNeuronCount,
      double simulationTimeMs,
    );

typedef _NmtkRendererPushDensityNative =
    Void Function(
      Pointer<Void> handle,
      Pointer<Float> ptr,
      IntPtr len,
      Uint32 gridW,
      Uint32 gridH,
    );
typedef NmtkRendererPushDensityDart =
    void Function(
      Pointer<Void> handle,
      Pointer<Float> ptr,
      int len,
      int gridW,
      int gridH,
    );

typedef _NmtkRendererDrawFrameNative = Void Function(Pointer<Void> handle);
typedef NmtkRendererDrawFrameDart = void Function(Pointer<Void> handle);

typedef _NmtkRendererGetPixelBufferNative =
    Pointer<Void> Function(Pointer<Void> handle);
typedef NmtkRendererGetPixelBufferDart =
    Pointer<Void> Function(Pointer<Void> handle);

typedef _NmtkRendererDestroyNative = Void Function(Pointer<Void> handle);
typedef NmtkRendererDestroyDart = void Function(Pointer<Void> handle);

class NmtkWgpuBindings {
  NmtkWgpuBindings._(DynamicLibrary lib)
    : create = lib
          .lookupFunction<_NmtkRendererCreateNative, NmtkRendererCreateDart>(
            'nmtk_renderer_create',
          ),
      resize = lib
          .lookupFunction<_NmtkRendererResizeNative, NmtkRendererResizeDart>(
            'nmtk_renderer_resize',
          ),
      pushSpikes = lib
          .lookupFunction<
            _NmtkRendererPushSpikesNative,
            NmtkRendererPushSpikesDart
          >('nmtk_renderer_push_spikes'),
      pushDensity = lib
          .lookupFunction<
            _NmtkRendererPushDensityNative,
            NmtkRendererPushDensityDart
          >('nmtk_renderer_push_density'),
      drawFrame = lib
          .lookupFunction<
            _NmtkRendererDrawFrameNative,
            NmtkRendererDrawFrameDart
          >('nmtk_renderer_draw_frame'),
      getPixelBuffer = lib
          .lookupFunction<
            _NmtkRendererGetPixelBufferNative,
            NmtkRendererGetPixelBufferDart
          >('nmtk_renderer_get_pixel_buffer'),
      destroy = lib
          .lookupFunction<_NmtkRendererDestroyNative, NmtkRendererDestroyDart>(
            'nmtk_renderer_destroy',
          );

  final NmtkRendererCreateDart create;
  final NmtkRendererResizeDart resize;
  final NmtkRendererPushSpikesDart pushSpikes;
  final NmtkRendererPushDensityDart pushDensity;
  final NmtkRendererDrawFrameDart drawFrame;
  final NmtkRendererGetPixelBufferDart getPixelBuffer;
  final NmtkRendererDestroyDart destroy;

  static NmtkWgpuBindings? _instance;

  /// Loads the dylib and resolves all symbols. Throws if unsupported on this
  /// platform or the dylib/symbols can't be found — callers (see
  /// `renderer_registry.dart`) must catch this and fall back to
  /// `FragmentShaderNeuronRenderer`.
  static NmtkWgpuBindings get instance {
    final existing = _instance;
    if (existing != null) return existing;
    if (!Platform.isMacOS) {
      throw UnsupportedError('nmtk_wgpu renderer is macOS-only in this phase');
    }
    // Embedded into Contents/Frameworks by CocoaPods, resolved via @rpath
    // the same way FlutterMacOS.framework's dylib is — see
    // nmtk_wgpu_renderer_plugin.podspec's install_name_tool step.
    final lib = DynamicLibrary.open('libnmtk_wgpu.dylib');
    final created = NmtkWgpuBindings._(lib);
    _instance = created;
    return created;
  }
}
