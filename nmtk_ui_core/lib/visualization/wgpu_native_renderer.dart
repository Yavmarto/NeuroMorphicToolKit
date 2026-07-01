import 'dart:ffi' hide Size;

import 'package:ffi/ffi.dart' as ffi;
import 'package:flutter/widgets.dart';
import 'package:nmtk_ui_core/visualization/renderer_interface.dart';
import 'package:nmtk_ui_core/visualization/src/nmtk_wgpu_bindings.dart';
import 'package:nmtk_wgpu_renderer_plugin/nmtk_wgpu_renderer_plugin.dart';

/// Stage 1-3 native renderer: bridges spike/density frames into the
/// nmtk_wgpu Rust crate over `dart:ffi`, which renders into a shared
/// `CVPixelBuffer` displayed through a Flutter [Texture] widget. See
/// `tasks/30 june/implementation_plan.md` for the staged rollout — Stage 1
/// proved the bridge (a fixed solid color), Stage 2 added particle
/// rendering, Stage 3 added the density-grid (1M-neuron) tier.
class WgpuNativeNeuronRenderer implements NeuronRenderer {
  final NmtkWgpuBindings _bindings = NmtkWgpuBindings.instance;

  Pointer<Void> _handle = nullptr;
  int? _textureId;
  bool _creating = false;

  final ValueNotifier<int?> _textureIdNotifier = ValueNotifier<int?>(null);
  final ValueNotifier<String?> _error = ValueNotifier<String?>(null);

  @override
  void attach(Size size) {
    final width = size.width.toInt();
    final height = size.height.toInt();
    if (_handle != nullptr) {
      _bindings.resize(_handle, width, height);
      return;
    }
    if (_creating) return;
    _creating = true;

    final handle = _bindings.create(width, height);
    if (handle == nullptr) {
      _error.value = 'nmtk_wgpu: renderer_create failed (no GPU adapter?)';
      _creating = false;
      return;
    }
    _handle = handle;
    _registerTexture();
  }

  Future<void> _registerTexture() async {
    try {
      final pixelBufferPtr = _bindings.getPixelBuffer(_handle).address;
      // Draw (and thus lock/touch the CVPixelBuffer) once *before* handing
      // the pointer to Flutter's texture registry. CVPixelBufferLockBaseAddress
      // realizes the buffer's backing Objective-C class on first use; if that
      // first use instead happens after registerTexture(), the engine's
      // raster thread can call copyPixelBuffer() and race our first lock on
      // the same never-before-touched object, crashing in the ObjC runtime's
      // class-realization path (SIGSEGV in _getCVPixelBuffer, seen via a
      // macOS crash report). Drawing first serializes that one-time
      // realization on this thread before any other consumer can see the
      // pointer. Also doubles as Stage 1's bridge proof — a solid-color
      // marker is visible even with no backend connected. pushFrame() takes
      // over once real frames arrive.
      _bindings.drawFrame(_handle);
      final id = await NmtkWgpuRendererPlugin.registerTexture(pixelBufferPtr);
      _textureId = id;
      await NmtkWgpuRendererPlugin.textureFrameAvailable(id);
      _textureIdNotifier.value = id;
    } catch (e) {
      _error.value = 'nmtk_wgpu: texture registration failed: $e';
    } finally {
      _creating = false;
    }
  }

  // Copies `frame.spikeData` into a native buffer for the duration of this
  // call only — Dart's Float32List is GC-heap memory, not safe to hand a
  // long-lived pointer to. See the implementation plan's "Zero-copy claim"
  // section for why this single bounded copy is the deliberate choice, not
  // an oversight.
  @override
  void pushFrame(VisualizationFrame frame) {
    if (_handle == nullptr) return;
    if (frame.scale == VisualizationScale.density) {
      final grid = frame.densityGrid;
      if (grid.isNotEmpty) {
        final nativeBuf = ffi.calloc<Float>(grid.length);
        try {
          nativeBuf.asTypedList(grid.length).setAll(0, grid);
          _bindings.pushDensity(_handle, nativeBuf, grid.length, frame.gridW, frame.gridH);
        } finally {
          ffi.calloc.free(nativeBuf);
        }
      }
    } else {
      final spikes = frame.spikeData;
      if (spikes.isNotEmpty) {
        final nativeBuf = ffi.calloc<Float>(spikes.length);
        try {
          nativeBuf.asTypedList(spikes.length).setAll(0, spikes);
          _bindings.pushSpikes(
            _handle,
            nativeBuf,
            spikes.length,
            frame.totalNeuronCount,
            frame.simulationTimeMs,
          );
        } finally {
          ffi.calloc.free(nativeBuf);
        }
      }
    }
    _bindings.drawFrame(_handle);
    final textureId = _textureId;
    if (textureId != null) {
      NmtkWgpuRendererPlugin.textureFrameAvailable(textureId);
    }
  }

  @override
  Widget buildSurface(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: _error,
      builder: (context, error, _) {
        if (error != null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(error, textAlign: TextAlign.center),
            ),
          );
        }
        return ValueListenableBuilder<int?>(
          valueListenable: _textureIdNotifier,
          builder: (context, textureId, _) {
            if (textureId == null) {
              return const Center(child: Text('Initializing native renderer...'));
            }
            return Texture(textureId: textureId);
          },
        );
      },
    );
  }

  @override
  void dispose() {
    final textureId = _textureId;
    final handle = _handle;
    _textureId = null;
    _handle = nullptr;

    // Unregister the Flutter texture before destroying the Rust handle.
    // nmtk_renderer_destroy currently leaks the CVPixelBuffer rather than
    // releasing it (see its doc comment in lib.rs for why), so this
    // ordering isn't load-bearing today — but keep it: it's what Stage 2/3
    // needs once destroy actually frees the buffer instead of leaking it.
    // Chained, not awaited: `dispose()` must stay synchronous per the
    // NeuronRenderer contract.
    Future<void> unregistered = Future<void>.value();
    if (textureId != null) {
      unregistered = NmtkWgpuRendererPlugin.unregisterTexture(textureId);
    }
    if (handle != nullptr) {
      unregistered.then((_) => _bindings.destroy(handle));
    }

    _textureIdNotifier.dispose();
    _error.dispose();
  }
}
